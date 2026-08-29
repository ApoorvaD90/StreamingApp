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
  description = "Public IP address of the Jenkins CI/CD EC2 instance."
  value       = aws_instance.jenkins.public_ip
}
