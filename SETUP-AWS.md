# AWS Setup Checklist (IaC First)

This file lists **everything you must configure manually** before running Terraform and GitHub Actions.

---

## 1) AWS Account Prep (Manual)

1. **Create an AWS account** (if you don’t have one).
2. **Choose a region** (example: `us-east-1`).
3. **Create an IAM role for GitHub Actions (OIDC)**:
   - Trust policy for `token.actions.githubusercontent.com`
   - Allow repo(s): `PongCentrifugo/backend`, `PongCentrifugo/frontend`, `PongCentrifugo/IAC`
   - Attach policy permissions (minimum):
     - ECS: `UpdateService`, `DescribeServices`, `RegisterTaskDefinition`
     - ECR: `GetAuthorizationToken`, `PutImage`, `UploadLayerPart`, `CompleteLayerUpload`
     - S3: `PutObject`, `DeleteObject`, `ListBucket`
     - CloudFront: `CreateInvalidation`
     - ElastiCache, EC2, IAM, ALB, CloudWatch (for Terraform)
- EKS, ECR, EC2, VPC, CloudFormation (for Terraform + Kubernetes apply)

> You can also use access keys instead of OIDC, but OIDC is recommended.

---

## 2) Terraform (IaC) Prerequisites

Required variables:

- `centrifugo_secret` (JWT secret)
- `centrifugo_api_key` (Centrifugo HTTP API key)
- `frontend_bucket_name` (unique S3 bucket name)

Optional:
- `aws_region`
- `project_name`
- `redis_node_type`

---

## 3) GitHub Secrets (Per Repo)

### **IAC repo** (`PongCentrifugo/IAC`)
Required secrets:

- `AWS_ROLE_ARN`
- `AWS_REGION`
- `CENTRIFUGO_SECRET`
- `CENTRIFUGO_API_KEY`
- `FRONTEND_BUCKET_NAME`
- `ECR_BACKEND_IMAGE` (example: `123456789012.dkr.ecr.us-east-1.amazonaws.com/pong-backend:latest`)

---

### **Backend repo** (`PongCentrifugo/backend`)
Required secrets:

- `AWS_ROLE_ARN`
- `AWS_REGION`
- `ECR_BACKEND_REPOSITORY`  
  Example: `123456789012.dkr.ecr.us-east-1.amazonaws.com/pong-backend`
- `EKS_CLUSTER`  
  Example: `pong-cluster`
- `EKS_NAMESPACE`  
  Example: `default`

---

### **Frontend repo** (`PongCentrifugo/frontend`)
Required secrets:

- `AWS_ROLE_ARN`
- `AWS_REGION`
- `FRONTEND_BUCKET`
- `CLOUDFRONT_DISTRIBUTION_ID`

---

## 4) Manual Steps After Terraform Apply

1. **Get outputs from Terraform**:
   - `backend_ecr_repository`
   - `cloudfront_distribution_id`
   - `frontend_bucket_name`
  - `eks_cluster_name`

2. **Set GitHub Secrets** in each repo based on outputs.

3. **Push to `main`** to trigger pipelines:
   - Backend build & deploy
   - Frontend build & deploy
   - IaC apply

---

## 5) Local Developer Setup (Optional)

If running locally:

- Docker + Docker Compose
- Go 1.22+
- Node 18+

Start order:
1. `iac/redis`
2. `iac/centrifugo`
3. `pong-backend`
4. `pong-frontend`

---

## Quick Start (Terraform)

```bash
cd ../terraform

terraform init

terraform apply \
  -var="centrifugo_secret=YOUR_SECRET" \
  -var="centrifugo_api_key=YOUR_API_KEY" \
  -var="frontend_bucket_name=YOUR_BUCKET"
```

