locals {
  name_prefix = var.project_name
}

data "aws_availability_zones" "available" {}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-${count.index}"
  }
}

resource "aws_subnet" "private" {
  count                   = length(var.private_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-private-${count.index}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${local.name_prefix}-public-rt"
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  count  = 1
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id
  depends_on    = [aws_internet_gateway.igw]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${local.name_prefix}-private-rt"
  }
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "eks_cluster" {
  name        = "${local.name_prefix}-eks-cluster-sg"
  description = "EKS cluster security group"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "eks_nodes" {
  name        = "${local.name_prefix}-eks-nodes-sg"
  description = "EKS worker nodes security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "redis" {
  name        = "${local.name_prefix}-redis-sg"
  description = "Redis security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_eks_cluster.main.vpc_config[0].cluster_security_group_id]
  }
}

resource "aws_ecr_repository" "backend" {
  name = "${local.name_prefix}-backend"
}

resource "aws_ecr_repository" "centrifugo" {
  name = "${local.name_prefix}-centrifugo"
}

resource "aws_iam_role" "eks_cluster" {
  name = "${local.name_prefix}-eks-cluster"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cluster_vpc" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

resource "aws_iam_role" "eks_nodes" {
  name = "${local.name_prefix}-eks-nodes"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_nodes_worker" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_nodes_cni" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_nodes_ecr" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_eks_cluster" "main" {
  name     = "${local.name_prefix}-cluster"
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids         = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)
    security_group_ids = [aws_security_group.eks_cluster.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster,
    aws_iam_role_policy_attachment.eks_cluster_vpc
  ]
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.name_prefix}-nodes"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = aws_subnet.private[*].id

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = ["t3.medium"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_nodes_worker,
    aws_iam_role_policy_attachment.eks_nodes_cni,
    aws_iam_role_policy_attachment.eks_nodes_ecr
  ]
}

data "aws_eks_cluster" "main" {
  name = aws_eks_cluster.main.name
}

data "aws_eks_cluster_auth" "main" {
  name = aws_eks_cluster.main.name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main.token
}

locals {
  centrifugo_config = {
    token_hmac_secret_key                 = var.centrifugo_secret
    api_key                               = var.centrifugo_api_key
    admin                                 = true
    admin_password                        = "admin"
    admin_secret                          = "admin-secret"
    allowed_origins                       = ["*"]
    engine                                = "redis"
    redis_address                         = "redis://${aws_elasticache_cluster.redis.cache_nodes[0].address}:6379/0"
    redis_prefix                          = "centrifugo"
    proxy_rpc_endpoint                    = "http://pong-backend/v1/centrifugo/rpc"
    proxy_include_connection_meta         = true
    proxy_http_headers                    = ["X-Centrifugo-User-Id"]
    allow_anonymous_connect_without_token = true
    namespaces = [
      {
        name                          = "pong_public"
        history_size                  = 10
        history_ttl                   = "300s"
        force_recovery                = true
        presence                      = true
        join_leave                    = true
        force_push_join_leave         = true
        allow_subscribe_for_anonymous = true
        allow_subscribe_for_client    = true
        allow_history_for_anonymous   = true
        allow_history_for_client      = true
        allow_publish_for_anonymous   = false
        allow_presence_for_anonymous  = false
      },
      {
        name                          = "pong_private"
        history_size                  = 0
        history_ttl                   = "0s"
        force_recovery                = false
        presence                      = true
        join_leave                    = true
        force_push_join_leave         = true
        allow_subscribe_for_anonymous = false
        allow_publish_for_anonymous   = false
      }
    ]
  }
}

resource "kubernetes_config_map_v1_data" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = yamlencode([
      {
        rolearn  = aws_iam_role.eks_nodes.arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = ["system:bootstrappers", "system:nodes"]
      },
      {
        rolearn  = var.github_actions_role_arn
        username = "github-actions"
        groups   = ["system:masters"]
      }
    ])
  }

  force       = true
  depends_on  = [aws_eks_node_group.main]
}

resource "kubernetes_secret_v1" "pong_secrets" {
  metadata {
    name      = "pong-secrets"
    namespace = var.k8s_namespace
  }

  data = {
    CENTRIFUGO_SECRET  = base64encode(var.centrifugo_secret)
    CENTRIFUGO_API_KEY = base64encode(var.centrifugo_api_key)
  }
}

resource "kubernetes_deployment_v1" "backend" {
  metadata {
    name      = "pong-backend"
    namespace = var.k8s_namespace
    labels = {
      app = "pong-backend"
    }
  }

  spec {
    replicas = var.desired_count_backend

    selector {
      match_labels = {
        app = "pong-backend"
      }
    }

    template {
      metadata {
        labels = {
          app = "pong-backend"
        }
      }

      spec {
        container {
          name  = "backend"
          image = var.backend_image

          port {
            container_port = var.backend_port
          }

          env {
            name  = "PORT"
            value = tostring(var.backend_port)
          }

          env {
            name  = "CENTRIFUGO_API_URL"
            value = "http://pong-centrifugo"
          }

          env {
            name = "CENTRIFUGO_API_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.pong_secrets.metadata[0].name
                key  = "CENTRIFUGO_API_KEY"
              }
            }
          }

          env {
            name = "CENTRIFUGO_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.pong_secrets.metadata[0].name
                key  = "CENTRIFUGO_SECRET"
              }
            }
          }

          env {
            name  = "TOKEN_TTL"
            value = "15m"
          }

          env {
            name  = "REDIS_URL"
            value = "redis://${aws_elasticache_cluster.redis.cache_nodes[0].address}:6379/0"
          }

          env {
            name  = "REDIS_PUBSUB_PATTERN"
            value = "centrifugo.*"
          }

          env {
            name  = "REDIS_PREFIX"
            value = "centrifugo"
          }

          env {
            name  = "REDIS_PRESENCE_INTERVAL"
            value = "2s"
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "backend" {
  metadata {
    name      = "pong-backend"
    namespace = var.k8s_namespace
  }

  spec {
    selector = {
      app = "pong-backend"
    }

    port {
      name        = "http"
      port        = 80
      target_port = var.backend_port
    }

    type = "LoadBalancer"
  }
}

resource "kubernetes_deployment_v1" "centrifugo" {
  metadata {
    name      = "pong-centrifugo"
    namespace = var.k8s_namespace
    labels = {
      app = "pong-centrifugo"
    }
  }

  spec {
    replicas = var.desired_count_centrifugo

    selector {
      match_labels = {
        app = "pong-centrifugo"
      }
    }

    template {
      metadata {
        labels = {
          app = "pong-centrifugo"
        }
      }

      spec {
        container {
          name  = "centrifugo"
          image = var.centrifugo_image

          port {
            container_port = var.centrifugo_port
          }

          env {
            name  = "CENTRIFUGO_CONFIG_JSON"
            value = jsonencode(local.centrifugo_config)
          }

          command = ["/bin/sh", "-c", "echo \"$CENTRIFUGO_CONFIG_JSON\" > /centrifugo/config.json && centrifugo --config=/centrifugo/config.json"]
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "centrifugo" {
  metadata {
    name      = "pong-centrifugo"
    namespace = var.k8s_namespace
  }

  spec {
    selector = {
      app = "pong-centrifugo"
    }

    port {
      name        = "http"
      port        = 80
      target_port = var.centrifugo_port
    }

    type = "LoadBalancer"
  }
}

resource "kubernetes_deployment_v1" "cloudflared" {
  count = var.cloudflare_tunnel_token == "" ? 0 : 1

  metadata {
    name      = "cloudflared"
    namespace = var.k8s_namespace
    labels = {
      app = "cloudflared"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "cloudflared"
      }
    }

    template {
      metadata {
        labels = {
          app = "cloudflared"
        }
      }

      spec {
        container {
          name  = "cloudflared"
          image = "cloudflare/cloudflared:latest"

          env {
            name  = "TUNNEL_TOKEN"
            value = var.cloudflare_tunnel_token
          }

          args = ["tunnel", "--no-autoupdate", "run", "--token", var.cloudflare_tunnel_token]
        }
      }
    }
  }
}

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/${local.name_prefix}-backend"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "centrifugo" {
  name              = "/ecs/${local.name_prefix}-centrifugo"
  retention_in_days = 14
}

resource "aws_elasticache_subnet_group" "redis" {
  name       = "${local.name_prefix}-redis-subnets"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${local.name_prefix}-redis"
  engine               = "redis"
  node_type            = var.redis_node_type
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids   = [aws_security_group.redis.id]
}

resource "aws_s3_bucket" "frontend" {
  bucket        = var.frontend_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${local.name_prefix}-oac"
  description                       = "OAC for frontend S3"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  default_root_object = "index.html"

  origin {
    domain_name = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id   = "frontend-s3"

    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  default_cache_behavior {
    target_origin_id       = "frontend-s3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontServicePrincipalReadOnly"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = ["s3:GetObject"]
      Resource  = "${aws_s3_bucket.frontend.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.frontend.arn
        }
      }
    }]
  })
}
