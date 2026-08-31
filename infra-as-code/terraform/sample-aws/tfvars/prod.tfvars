# ============================================
# BACKEND CONFIGURATION
# ============================================
# S3 bucket for storing Terraform state files
bucket = "selco-prod-livelihood-statefile"
key    = "terraform/terraform.tfstate"
region = "ap-south-2"
dynamodb_table = "selco-prod-livelihood-statefile"
encrypt = true


# ============================================
# AWS REGION CONFIGURATION
# ============================================
# AWS region where all resources will be created
aws_region = "ap-south-2"


# ============================================
# EKS DEPLOYMENT CONTROL
# ============================================
# Set to true to create EKS cluster and all related resources, false to skip
create_eks = true


# ============================================
# NETWORK CONFIGURATION
# ============================================
# VPC CIDR block for the entire network
vpc_cidr_block = "172.16.0.0/16"

# Network availability zones for VPC subnets (for high availability)
# Must match the aws_region selected above
network_availability_zones = ["ap-south-2a", "ap-south-2b"]

# Availability zones for EKS cluster (control plane)
# Must match the aws_region selected above
availability_zones = ["ap-south-2a"]


# ============================================
# DATABASE (RDS) CONFIGURATION
# ============================================
# Set to true to create RDS instance, false to skip RDS deployment
create_rds = true

# PostgreSQL database name (no hyphens or special characters)
db_name = "livelihooddb"

# Database admin username
db_username = "livelihood_prod_admin"

# PostgreSQL version
db_version = "15"

# RDS instance type/class
db_instance_class = "db.m5.large"

# Note: db_password should NOT be set here - it will be prompted at runtime


# ============================================
# EKS CLUSTER CONFIGURATION
# ============================================
# Cluster name (used for tagging and identification)
cluster_name = "livelihood-prod"

# Kubernetes version to deploy
kubernetes_version = "1.35"

# Architecture for worker nodes (x86_64 or arm64)
architecture = "x86_64"

# Instance types for worker nodes (leave empty to use architecture defaults)
# For x86_64: ["m5a.xlarge"] (default)
# For arm64: ["t4g.xlarge"] (default)
instance_types = ["r6a.xlarge"]

# Or specify custom instance types:
# instance_types = ["r5ad.large", "m5a.xlarge"]


# ============================================
# EKS NODE GROUP CONFIGURATION
# ============================================
# Minimum number of worker nodes
min_worker_nodes = "0"

# Desired number of worker nodes
desired_worker_nodes = 4

# Maximum number of worker nodes (for autoscaling)
max_worker_nodes = "4"

# Maximum pods per node
# Default is based on instance type (typically 29-110 depending on ENIs)
# With prefix delegation enabled, you can set this higher (up to 110-250)
# Setting to 120 allows more pod density per node
max_pods_per_node = 120


# ============================================
# EKS ADDONS VERSIONS
# ============================================
# These must match your Kubernetes version
# Kubernetes 1.32 compatible versions:
coredns-version = "v1.13.2-eksbuild.1"
kube-proxy-version = "v1.35.0-eksbuild.2"
aws_ebs_csi_driver = "v1.56.0-eksbuild.1"


# ============================================
# S3 FILESTORE CONFIGURATION
# ============================================
# Kubernetes namespace for filestore secret
filestore_namespace = "core"


# ============================================
# VERSION COMPATIBILITY REFERENCE
# ============================================
# Kubernetes version: 1.29
# ami: ami-0faa3ede6ae0dc2f3
# kube-proxy: "v1.29.11-eksbuild.2"
# coredns: "v1.11.4-eksbuild.2"
# aws-ebs-csi-driver: "v1.39.0-eksbuild.1"

# Kubernetes version: 1.30
# ami: ami-0308b0e27f09b0b25
# kube-proxy: v1.30.7-eksbuild.2
# coredns: "v1.11.4-eksbuild.2"
# aws-ebs-csi-driver: "v1.39.0-eksbuild.1"

# Kubernetes version: 1.31
# ami: ami-0133d24dfaa24814a
# kube-proxy: v1.31.3-eksbuild.2
# coredns: "v1.11.4-eksbuild.2"
# aws-ebs-csi-driver: "v1.39.0-eksbuild.1"

# Kubernetes version: 1.32
# ami: ami-0f4a7f3d1231aaf54
# kube-proxy: v1.32.0-eksbuild.2
# coredns: "v1.11.4-eksbuild.2"
# aws-ebs-csi-driver: "v1.39.0-eksbuild.1"