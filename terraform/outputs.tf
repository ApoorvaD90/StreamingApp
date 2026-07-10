output "vpc_id" {
  value = module.vpc.vpc_id
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "ecr_repository_urls" {
  value = { for name, repo in aws_ecr_repository.services : name => repo.repository_url }
}

output "s3_bucket_name" {
  value = aws_s3_bucket.videos.bucket
}

output "jenkins_public_ip" {
  value = aws_instance.jenkins.public_ip
}