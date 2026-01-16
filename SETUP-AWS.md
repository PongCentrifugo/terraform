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

### Terraform Cloud credentials (required)

Because you run from **terraform.io**, you must set AWS credentials in the **Terraform Cloud workspace**:

**Option A — Static AWS keys**
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION`
- `AWS_SESSION_TOKEN` (only if using temporary credentials)

**Option B — Terraform Cloud OIDC (recommended)**
- `TFC_AWS_PROVIDER_AUTH = true`
- `TFC_AWS_RUN_ROLE_ARN = arn:aws:iam::<account_id>:role/<role_name>`
- `AWS_REGION`

**Full setup (Terraform Cloud OIDC → AWS):**

1. **Create OIDC provider in AWS**  
   AWS Console → IAM → Identity providers → Add provider  
   - Type: `OpenID Connect`  
   - Provider URL: `https://app.terraform.io`  
   - Audience: `aws.workload.identity`  

2. **Create an IAM role for Terraform Cloud**  
   IAM → Roles → Create role → Web identity  
   - **Workload type:** `Workspace run`  
   - Identity provider: `app.terraform.io`  
   - Audience: `aws.workload.identity`
   - Organization → your TFC org name
   - Project Name → the TFC project that contains the workspace
   - Workspace Name → the exact workspace name for this repo
   - Run Phase → plan and/or apply
    If you want both, set it to * (or leave blank if AWS allows) to allow all phases.

3. **Set trust policy conditions** (restrict to your org/workspace):  
   Replace `<ORG_NAME>` and `<WORKSPACE_NAME>` with your Terraform Cloud values.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<account_id>:oidc-provider/app.terraform.io"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "app.terraform.io:aud": "aws.workload.identity"
        },
        "StringLike": {
          "app.terraform.io:sub": "organization:<ORG_NAME>:project:*:workspace:<WORKSPACE_NAME>:run_phase:*"
        }
      }
    }
  ]
}
```

4. **Attach IAM permissions** to the role  
   **Role name:** `tfc-pong-eks-role`  
   **Description:** `Terraform Cloud role for Pong EKS, networking, Redis, S3, CloudFront, and ECR deployments.`

   **Use this reduced policy set (stays under AWS 10-policy limit):**
   - `PowerUserAccess`
   - `IAMFullAccess` (or a limited IAM policy for role creation)

5. **Configure Terraform Cloud workspace variables**  
   Workspace → Variables → Add **Environment variables**:
   - `TFC_AWS_PROVIDER_AUTH = true`  
   - `TFC_AWS_RUN_ROLE_ARN = arn:aws:iam::<account_id>:role/<role_name>`  
   - `AWS_REGION = us-east-1` (or your region)

6. **Trigger a run**  
   Push to `main` or run `Plan/Apply` in Terraform Cloud UI.

Required variables (and where to get them):

- `centrifugo_secret` (JWT secret)
  - **Where to get it:** Generate a strong random string (32+ chars). Example:
    - `openssl rand -hex 32`
- `centrifugo_api_key` (Centrifugo HTTP API key)
  - **Where to get it:** Generate a random key (can be the same method as above).
- `frontend_bucket_name` (unique S3 bucket name)
  - **Where to get it:** Choose a globally unique name (S3 is global).
  - Example: `pong-frontend-<yourname>-<env>`
- `github_actions_role_arn` (GitHub Actions role ARN)
  - **Where to get it:** IAM role for GitHub Actions (e.g. `gha-pong-deploy-role`).
  - This is used by Terraform to add the role into EKS `aws-auth` so kubectl can deploy.

Other required values for cluster deployment:
- **AWS Region** (`aws_region`)
  - **Where to get it:** Choose a region near your users (example: `us-east-1`).
- **ECR backend image** (`ECR_BACKEND_IMAGE`)
  - **Where to get it:** Terraform output `backend_ecr_repository` + tag.
  - Example: `123456789012.dkr.ecr.us-east-1.amazonaws.com/pong-backend:latest`

Optional:
- `aws_region`
- `project_name`
- `redis_node_type`

---

## 3) GitHub Actions + Terraform Cloud Setup (Current Folder Layout)

**Terraform code location:** `/<repo-root>/terraform`  
**Kubernetes manifests:** `/<repo-root>/terraform/k8s`

### Terraform Cloud workspace (for `/terraform`)
Set these **Environment variables** in the Terraform Cloud workspace:
- `TFC_AWS_PROVIDER_AUTH = true`
- `TFC_AWS_RUN_ROLE_ARN = arn:aws:iam::<account_id>:role/tfc-pong-eks-role`
- `AWS_REGION = <your-region>`

Set these **Terraform variables** in the workspace:
- `centrifugo_secret`
- `centrifugo_api_key`
- `frontend_bucket_name`
- `github_actions_role_arn`

### GitHub Actions secrets

#### **Backend repo** (`PongCentrifugo/backend`)
- `AWS_ROLE_ARN`  
  **Where to get it:** Create a **GitHub Actions OIDC role** in AWS (separate from Terraform Cloud).  
  - **Auth type:** OpenID Connect (not SAML)  
  - **Provider URL:** `https://token.actions.githubusercontent.com`  
  - **Audience:** `sts.amazonaws.com`  
  - Trust policy must restrict to the `PongCentrifugo/backend` repo  
  - Use the Role ARN from IAM as the value.
  - **Role Name** `gha-pong-deploy-role`
- `AWS_REGION` 
- `ECR_BACKEND_REPOSITORY`  
  Example: `123456789012.dkr.ecr.us-east-1.amazonaws.com/pong-backend`
- `EKS_CLUSTER`  
  Example: `pong-cluster`
- `EKS_NAMESPACE`  
  Example: `default`

  **Required IAM permissions for `gha-pong-deploy-role`:**
  - `AmazonEC2ContainerRegistryPowerUser` (or `AmazonEC2ContainerRegistryFullAccess`)
  - `AmazonEKSClusterPolicy` (for `eks:DescribeCluster`)

#### **Frontend repo** (`PongCentrifugo/frontend`)
- `AWS_ROLE_ARN`
- `AWS_REGION`
- `FRONTEND_BUCKET`
- `CLOUDFRONT_DISTRIBUTION_ID`

### Terraform outputs you will need
After the first successful Terraform apply, capture:
- `backend_ecr_repository`
- `cloudfront_distribution_id`
- `frontend_bucket_name`
- `eks_cluster_name`
- `redis_endpoint`

Use those outputs to set GitHub Secrets in backend/frontend repos.

---

## 4) How the Backend Deploys to EKS

1. **GitHub Actions (backend repo)** builds a Docker image and pushes it to ECR.  
2. The workflow updates the EKS deployment:
   - `kubectl set image deployment/pong-backend backend=<ECR_REPO>:<SHA>`
3. Pods restart and pull the new image from ECR.  
4. Service remains stable while pods roll (default rolling update).

The EKS deployment and service are created by Terraform Cloud when it applies
the Kubernetes manifests from `/terraform/k8s`.

