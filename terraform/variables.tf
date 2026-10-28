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
  default     = "1.35" # standard support until 2027-03; versions in extended support cost 6x
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
  default     = 4 # t3.small fits only 11 pods: add-ons + app + monitoring stack need ~34 pods (Sprint 5)
}

variable "node_max" {
  type        = number
  description = "Maximum number of EKS worker nodes the autoscaler can scale up to."
  default     = 6
}

variable "node_desired" {
  type        = number
  description = "Desired number of EKS worker nodes at creation time."
  default     = 4 # applied at creation only (the EKS module ignores later changes; scale with aws eks update-nodegroup-config)
}

variable "s3_bucket_name" {
  type        = string
  description = "Name of the S3 bucket used for storing video content."
  default     = "streamingapp-videos"
}

# No default on purpose: must be supplied explicitly (TF_VAR_admin_cidr locally,
# the 'admin-cidr' credential in Jenkins) so access is never silently opened up.
variable "admin_cidr" {
  type        = string
  description = "Single admin IP as a /32 CIDR, allowed SSH, Jenkins UI and EKS API access. Update whenever the admin's public IP changes."

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0)) && endswith(var.admin_cidr, "/32")
    error_message = "admin_cidr must be a single host CIDR like 203.0.113.10/32 (0.0.0.0/0 and wider ranges are rejected)."
  }
}

# Pinned Ubuntu 22.04 AMI for Jenkins (no most_recent lookup), so every apply uses the same image.
# To move to a newer image deliberately, look up Canonical's current one:
#   aws ssm get-parameter --name /aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id --query Parameter.Value --output text
variable "jenkins_ami_id" {
  type        = string
  description = "Exact AMI ID for the Jenkins EC2 instance (Ubuntu 22.04, us-east-1)."
  default     = "ami-062944a84867f2386" # Ubuntu 22.04 LTS, us-east-1 (Canonical SSM parameter, Oct 2026)

  validation {
    condition     = can(regex("^ami-[0-9a-f]{8,17}$", var.jenkins_ami_id))
    error_message = "jenkins_ami_id must be pinned to an exact AMI ID like ami-0abcdef1234567890 (see the aws ssm get-parameter command above)."
  }
}

# Pinned add-on versions so every apply installs exactly the same build (no most_recent drift).
# Values are the EKS defaults for cluster_version. When changing cluster_version, look them up with:
#   aws eks describe-addon-versions --addon-name <name> --kubernetes-version <version> --query "addons[0].addonVersions[?compatibilities[0].defaultVersion==`true`].addonVersion | [0]"
variable "eks_addon_versions" {
  type        = map(string)
  description = "Pinned EKS add-on versions keyed by add-on name."
  default = {
    "coredns"            = "v1.13.2-eksbuild.50"
    "kube-proxy"         = "v1.35.3-eksbuild.29"
    "vpc-cni"            = "v1.22.4-eksbuild.3"
    "aws-ebs-csi-driver" = "v1.67.0-eksbuild.1"
  }

  validation {
    condition     = alltrue([for v in values(var.eks_addon_versions) : can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+-eksbuild\\.[0-9]+$", v))])
    error_message = "Every add-on version must be pinned to an exact version like v1.19.2-eksbuild.1 (see the aws eks describe-addon-versions command above)."
  }
}

variable "admin_iam_user" {
  type        = string
  description = "Name of the IAM user that administers the project (EKS cluster admin, KMS key admin)."
  default     = "streamingapp-admin"
}

variable "ssh_public_key_path" {
  type        = string
  description = "Path (relative to this folder) to the SSH public key used for the Jenkins EC2 key pair. Committed so Jenkins can run Terraform too."
  default     = "keys/streamingapp-key.pub"
}

variable "github_webhook_cidrs" {
  type        = list(string)
  description = "GitHub webhook source IP ranges (from https://api.github.com/meta -> hooks), allowed to reach Jenkins on 8080."
  default     = ["192.30.252.0/22", "185.199.108.0/22", "140.82.112.0/20", "143.55.64.0/20"]
}
