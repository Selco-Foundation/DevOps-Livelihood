#Backend-config
bucket = "selco-prod-githubaction-bucket"
key    = "digit-bootcamp-setup/terraform.tfstate"
region = "ap-south-1"
dynamodb_table = "selco-prod-githubaction-bucket"
encrypt = true


#Network
vpc_cidr_block = "192.168.0.0/16"

#DB
create_rds = true
db_name = "selcoproddb"
db_username = "selcoprod"
engine_version = "14.17"
db_instance_class = "db.m5.large"

#EKS
cluster_name = "selco-prod"
kubeconfig_name= "selco-prod"
node_name = "on-demand"
kubernetes_version = "1.35"
ami_id = "ami-0758de08253c90c00"
instance_type= "r5a.xlarge"
max_number_of_worker_nodes = "4"
number_of_worker_nodes = "3"
min_number_of_worker_nodes = "2"
coredns-version = "v1.13.2-eksbuild.1"
kube-proxy-version = "v1.35.0-eksbuild.2"
aws_ebs_csi_driver = "v1.56.0-eksbuild.1"


# Kubernetes-version: 1.29
# ami: ami-0faa3ede6ae0dc2f3
# version:
# kube-proxy: "v1.29.11-eksbuild.2"
# coredns: "v1.11.4-eksbuild.2"
# aws-ebs-csi-driver: "v1.39.0-eksbuild.1"

# Kubernetes-version: 1.30
# ami: ami-0308b0e27f09b0b25
# version:
# kube-proxy: v1.30.7-eksbuild.2
# coredns: "v1.11.4-eksbuild.2"
# aws-ebs-csi-driver: "v1.39.0-eksbuild.1"

# Kubernetes-version: 1.31
# ami: ami-0133d24dfaa24814a
# version:
# kube-proxy: v1.31.3-eksbuild.2
# coredns: "v1.11.4-eksbuild.2"
# aws-ebs-csi-driver: "v1.39.0-eksbuild.1"

# Kubernetes-version: 1.32
# ami:  ami-0f4a7f3d1231aaf54
# version:
# kube-proxy: v1.32.0-eksbuild.2
# coredns: "v1.11.4-eksbuild.2"
# aws-ebs-csi-driver: "v1.39.0-eksbuild.1"

# Kubernetes-version: 1.33
# ami:  ami-002d95654ddd4165b   #amazon-eks-node-al2023-x86_64-nvidia-1.33-v20250620
# #version:
# kube-proxy: v1.33.8-eksbuild.4
# coredns: "v1.13.2-eksbuild.1"
# aws-ebs-csi-driver: "v1.56.0-eksbuild.1"

# Kubernetes-version: 1.34
# ami:  ami-0f081bd4084790fb3   #amazon-eks-node-al2023-x86_64-standard-1.34-v20260224
# #version:
# kube-proxy: v1.34.3-eksbuild.5
# coredns: "v1.13.2-eksbuild.1"
# aws-ebs-csi-driver: "v1.56.0-eksbuild.1"

# Kubernetes-version: 1.35
# ami:  ami-0758de08253c90c00   #amazon-eks-node-al2023-x86_64-standard-1.35-v20260224
# #version:
# kube-proxy: v1.35.0-eksbuild.2
# coredns: "v1.13.2-eksbuild.1"
# aws-ebs-csi-driver: "v1.56.0-eksbuild.1"