# ============================================
# BACKEND CONFIGURATION (for `terraform init -backend-config=tfvars/prod-backend.tfvars`)
# ============================================
bucket         = "selco-prod-livelihood-statefile"
key            = "terraform/terraform.tfstate"
region         = "ap-south-2"
dynamodb_table = "selco-prod-livelihood-statefile"
encrypt        = true
