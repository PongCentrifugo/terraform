## Terraform (AWS)

This folder provisions AWS infrastructure for the Pong application (EKS + Kubernetes resources):

- VPC, public/private subnets, NAT
- EKS cluster with node group
- Kubernetes resources for backend + Centrifugo (managed by Terraform)
- ElastiCache Redis
- S3 + CloudFront for frontend hosting
- ECR repositories for images

### Prerequisites

- Terraform 1.6+
- AWS credentials (OIDC or access keys)

### Usage

```bash
cd iac/terraform

terraform init
terraform plan \
  -var="centrifugo_secret=YOUR_SECRET" \
  -var="centrifugo_api_key=YOUR_API_KEY" \
  -var="frontend_bucket_name=YOUR_UNIQUE_BUCKET" \
  -var="github_actions_role_arn=arn:aws:iam::<account_id>:role/gha-pong-deploy-role"

terraform apply \
  -var="centrifugo_secret=YOUR_SECRET" \
  -var="centrifugo_api_key=YOUR_API_KEY" \
  -var="frontend_bucket_name=YOUR_UNIQUE_BUCKET" \
  -var="github_actions_role_arn=arn:aws:iam::<account_id>:role/gha-pong-deploy-role"
```

### Outputs

After apply, Terraform outputs:

- `cloudfront_domain` → Frontend URL
- `backend_ecr_repository` → Push backend images here (used by `backend_image` variable)
- `cloudfront_distribution_id` → For cache invalidations
- `eks_cluster_name` → EKS cluster name

### Notes

- Kubernetes manifests are in `terraform/k8s/` and expect env substitution.
- Centrifugo and backend are exposed via separate LoadBalancer services.
