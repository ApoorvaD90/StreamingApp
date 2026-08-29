variable "aws_region" {
  type        = string
  description = "AWS region to deploy all resources into."
  default     = "us-east-1"
}

variable "environment" {
  type        = string
  description = "Environment name, applied as a tag to every resource."
  default     = "production"
}

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster."
  default     = "streamingapp-cluster"
}

variable "cluster_version" {
  type        = string
  description = "Kubernetes version for the EKS cluster. Must be a version currently supported by AWS EKS."
  default     = "1.33"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC."
  default     = "10.0.0.0/16"
}

variable "private_subnets" {
  type        = list(string)
  description = "CIDR blocks for private subnets (EKS worker nodes)."
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "public_subnets" {
  type        = list(string)
  description = "CIDR blocks for public subnets (NAT gateway, ALB, Jenkins EC2 instance)."
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "node_instance" {
  type        = string
  description = "EC2 instance type for EKS managed node group workers. Kept to a Free-Tier-eligible size."
  default     = "t3.small"
}

variable "node_min" {
  type        = number
  description = "Minimum number of EKS worker nodes."
  default     = 2
}

variable "node_max" {
  type        = number
  description = "Maximum number of EKS worker nodes the autoscaler can scale up to."
  default     = 6
}

variable "node_desired" {
  type        = number
  description = "Desired number of EKS worker nodes at creation time."
  default     = 2
}

variable "s3_bucket_name" {
  type        = string
  description = "Name of the S3 bucket used for storing video content."
  default     = "streamingapp-videos"
}

variable "admin_cidr" {
  type        = string
  description = "Single admin IP (CIDR /32) allowed SSH and Jenkins UI access. Must be updated whenever the admin's public IP changes."
  default     = "103.197.75.231/32"
}

variable "ssh_public_key_path" {
  type        = string
  description = "Local filesystem path to the SSH public key used for the Jenkins EC2 key pair."
  default     = "C:/Users/Apoorva/.ssh/streamingapp-key.pub"
}
