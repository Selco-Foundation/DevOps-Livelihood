# Infrastructure Setup (AWS)

This document describes how to provision the AWS infrastructure for this project using the
Terraform code in `terraform/sample-aws`. It only covers **infrastructure provisioning**
(networking, EKS, RDS, S3, IAM). Application/service deployment onto the cluster is handled
separately in `deploy-as-code` and is not covered here.

> The `terraform/` folder also contains other configs (`egov-cicd`, `quickstart-aws-ec2`,
> `node-pool`, `sample-azure`, `sample-gke`, ...). These are generic/legacy templates from the
> eGov DIGIT framework used by other projects/environments and are **not** used for this
> project. Ignore them unless you know you need them.

## What gets created

Running `terraform/sample-aws` provisions:

- A VPC with public + private subnets, an Internet Gateway, a NAT Gateway, and route tables
  (`../modules/kubernetes/aws/network`)
- An EKS cluster and a managed node group, with the `vpc-cni`, `kube-proxy`, `coredns`, and
  `aws-ebs-csi-driver` addons (via `terraform-aws-modules/eks/aws`), gated by `create_eks`
- An IAM role (IRSA) for the EBS CSI driver, and a default `gp3` encrypted storage class
- A PostgreSQL RDS instance, gated by `create_rds` (`../modules/db/aws`)
- Two S3 buckets (`<cluster_name>-assets-bucket`, `<cluster_name>-filestore-bucket`) with
  public read policies, plus an IAM user/access key/policy scoped to the filestore bucket
- A Kubernetes secret (`egov-filestore`) in the cluster containing the filestore IAM
  credentials (only when `create_eks = true`)

## Prerequisites

### Tools (install locally or on a build box)

- **Terraform** >= 1.5.7 (required by the upstream `terraform-aws-modules/eks/aws` module).
  Install from [releases.hashicorp.com](https://releases.hashicorp.com/terraform/) or via
  `tfenv`. (`scripts/install_dependencies_ubuntu.sh` / `install_dependencies_mac.sh` install an
  older Terraform via the OS package manager — prefer a manual install to get a version that
  meets the `>= 1.5.7` requirement.)
- **AWS CLI v2** — used to authenticate Terraform and to generate the EKS auth token
  (`aws eks get-token`, invoked internally by the `kubernetes` provider block in `main.tf`).
- **kubectl** — to verify/interact with the cluster after it's created.
- **git**

### AWS account / credentials

- An AWS account and a set of credentials (IAM user access keys, or an SSO/role profile)
  configured locally, e.g. via `aws configure` or `aws configure sso`, resolvable by the
  Terraform AWS provider (env vars, shared credentials file, or SSO profile).
- The target region must have capacity/quota for: 1 VPC, 1 NAT Gateway + 1 Elastic IP, 1 EKS
  cluster, and enough EC2 instances of the chosen worker instance type.

### IAM permissions needed

Provisioning creates VPC networking, IAM roles/users/policies (including an OIDC provider for
IRSA), an EKS cluster and node group, RDS, and S3 — plus an S3 bucket and DynamoDB table for
the Terraform state backend. The simplest option is to run this with an IAM identity that has
**AdministratorAccess** (or equivalent) in the target account. If you need a scoped-down
policy instead, it must at minimum allow:

- `ec2:*` (VPC, subnets, route tables, IGW, NAT gateway, EIP, security groups)
- `eks:*`
- `iam:CreateRole`, `iam:AttachRolePolicy`, `iam:PutRolePolicy`, `iam:CreateUser`,
  `iam:CreateAccessKey`, `iam:CreatePolicy`, `iam:AttachUserPolicy`,
  `iam:CreateOpenIDConnectProvider`, `iam:PassRole` (for EKS/node-group/IRSA roles)
- `rds:*` (if `create_rds = true`)
- `s3:*` (asset/filestore buckets, plus the remote-state bucket)
- `dynamodb:*` (state lock table)
- `sts:GetCallerIdentity`

Whoever applies the Terraform also needs cluster access after creation — `enable_cluster_creator_admin_permissions = true`
in `main.tf` grants the identity that created the cluster admin access to it automatically.

## 1. Set up the remote state backend (one-time, per environment)

Terraform state is stored in S3 with DynamoDB locking. `terraform/sample-aws/remote-state`
creates that bucket + lock table:

```bash
cd infra-as-code/terraform/sample-aws/remote-state
```

**Change needed:** the AWS region is hardcoded in `main.tf` (`provider "aws" { region = "ap-south-2" }`).
Edit this file if you want the state bucket in a different region.

Set the bucket/table name (must be globally unique — it's also used as the DynamoDB table
name) in `variables.tf`, or override it on the command line:

```bash
terraform init
terraform apply -var="bucket_name=<your-unique-state-bucket-name>"
```

Do this once per environment (e.g. once for dev, once for prod) with a distinct bucket name
each time. Note the bucket name, key, region, and DynamoDB table name — you'll need them in
the next step.

## 2. Configure the environment (`sample-aws`)

```bash
cd infra-as-code/terraform/sample-aws
```

Start from an existing tfvars file (`tfvars/dev.tfvars`, `tfvars/prod.tfvars`) as a template,
or create a new one (e.g. `tfvars/staging.tfvars`). Variables you need to review/set:

| Variable | Notes |
|---|---|
| `aws_region` | AWS region for all resources |
| `cluster_name` | Used to name/tag the EKS cluster, S3 buckets, IAM user/policy — must be unique per environment |
| `vpc_cidr_block` | VPC CIDR (default `192.168.0.0/16`) |
| `network_availability_zones` | AZs for VPC subnets, must match `aws_region`; use at least 2 for HA |
| `availability_zones` | AZ(s) the EKS control plane / node group / RDS use, must match `aws_region` |
| `kubernetes_version` | EKS version |
| `architecture` | `x86_64` or `arm64` — picks the node AMI type and default instance types |
| `instance_types` | Optional override for worker node instance types (leave `[]` to use the architecture default) |
| `min_worker_nodes` / `desired_worker_nodes` / `max_worker_nodes` | Node group scaling config |
| `max_pods_per_node` | Requires prefix delegation (already enabled via the `vpc-cni` addon config) to go above the ENI-based default |
| `create_eks` | Set `false` to skip creating the EKS cluster/node group entirely |
| `create_rds` | Set `true` to provision the RDS PostgreSQL instance |
| `db_name` / `db_username` / `db_version` / `db_instance_class` | RDS settings (only relevant if `create_rds = true`); `db_name` must not contain hyphens/special characters |
| `filestore_namespace` | Kubernetes namespace the `egov-filestore` secret is created in |

`db_password` has no default and is **not** meant to be put in a tfvars file — Terraform will
prompt for it interactively at `plan`/`apply` time (or pass `TF_VAR_db_password` as an
environment variable in CI).

## 3. Initialize and apply

Point Terraform at the state backend created in step 1. Either pass values inline:

```bash
terraform init \
  -backend-config="bucket=<state-bucket-name>" \
  -backend-config="key=terraform/terraform.tfstate" \
  -backend-config="region=<state-bucket-region>" \
  -backend-config="dynamodb_table=<state-bucket-name>" \
  -backend-config="encrypt=true"
```

or put the same key/value pairs in a `backend.hcl` file and run
`terraform init -backend-config=backend.hcl`.

Then plan and apply with your environment's tfvars:

```bash
terraform plan  -var-file=tfvars/dev.tfvars
terraform apply -var-file=tfvars/dev.tfvars
```

This takes ~15-20 minutes (EKS cluster + node group creation is the slowest part).

## 4. Verify

```bash
aws eks update-kubeconfig --name <cluster_name> --region <aws_region>
kubectl get nodes
```

Terraform outputs (`outputs.tf`) also expose `vpc_id`, `private_subnets`, `public_subnets`,
`db_instance_endpoint`, `s3_assets_bucket`, and `s3_filestore_bucket` for use by the deployment
step.

## Tearing down

```bash
terraform destroy -var-file=tfvars/<env>.tfvars
```

The remote-state S3 bucket has `prevent_destroy = true` and is managed separately (in
`remote-state/`) — destroying `sample-aws` does not remove your state bucket/lock table.
