output "cloudfront_domain" {
  value       = aws_cloudfront_distribution.frontend.domain_name
  description = "CloudFront domain for frontend."
}

output "backend_ecr_repository" {
  value       = aws_ecr_repository.backend.repository_url
  description = "ECR repository for backend image."
}

output "centrifugo_ecr_repository" {
  value       = aws_ecr_repository.centrifugo.repository_url
  description = "ECR repository for Centrifugo image (optional)."
}

output "redis_endpoint" {
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
  description = "Redis endpoint."
}

output "eks_cluster_name" {
  value       = aws_eks_cluster.main.name
  description = "EKS cluster name."
}

output "frontend_bucket_name" {
  value       = aws_s3_bucket.frontend.bucket
  description = "Frontend S3 bucket."
}

output "cloudfront_distribution_id" {
  value       = aws_cloudfront_distribution.frontend.id
  description = "CloudFront distribution ID."
}

locals {
  backend_lb_hostname = coalesce(
    try(kubernetes_service_v1.backend.status[0].load_balancer[0].ingress[0].hostname, ""),
    try(kubernetes_service_v1.backend.status[0].load_balancer[0].ingress[0].ip, "")
  )
  centrifugo_lb_hostname = coalesce(
    try(kubernetes_service_v1.centrifugo.status[0].load_balancer[0].ingress[0].hostname, ""),
    try(kubernetes_service_v1.centrifugo.status[0].load_balancer[0].ingress[0].ip, "")
  )
}

output "backend_service_hostname" {
  value       = local.backend_lb_hostname
  description = "Kubernetes LoadBalancer hostname/IP for backend service."
}

output "centrifugo_service_hostname" {
  value       = local.centrifugo_lb_hostname
  description = "Kubernetes LoadBalancer hostname/IP for Centrifugo service."
}

output "vite_backend_url" {
  value       = local.backend_lb_hostname == "" ? "" : "http://${local.backend_lb_hostname}"
  description = "Frontend env value for VITE_BACKEND_URL."
}

output "vite_centrifugo_url" {
  value       = local.centrifugo_lb_hostname == "" ? "" : "ws://${local.centrifugo_lb_hostname}/connection/websocket"
  description = "Frontend env value for VITE_CENTRIFUGO_URL."
}
