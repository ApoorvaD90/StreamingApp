output "vpc_id" {
  description = "ID of the VPC created for this project."
  value       = module.vpc.vpc_id
}

output "eks_cluster_endpoint" {
  description = "API server endpoint for the EKS cluster."
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "ecr_repository_urls" {
  description = "Map of service name to its ECR repository URL, used as the Docker push/pull target."
  value       = { for name, repo in aws_ecr_repository.services : name => repo.repository_url }
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket used for video storage."
  value       = aws_s3_bucket.videos.bucket
}

output "jenkins_public_ip" {
  description = "Elastic IP of the Jenkins CI/CD EC2 instance."
  value       = aws_eip.jenkins.public_ip
}

output "jenkins_private_ip" {
  description = "Private IP of the Jenkins EC2 instance, scraped by Prometheus inside the VPC."
  value       = aws_instance.jenkins.private_ip
}

output "jenkins_role_arn" {
  description = "IAM role attached to the Jenkins EC2 instance."
  value       = aws_iam_role.jenkins.arn
}

output "lb_controller_role_arn" {
  description = "IRSA role ARN for the AWS Load Balancer Controller service account."
  value       = module.lb_controller_irsa.iam_role_arn
}
