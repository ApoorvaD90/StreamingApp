module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "~> 20.0"
  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets

  # Public API endpoint only for the admin IP; Jenkins (inside the VPC) uses the private endpoint
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = [var.admin_cidr]
  cluster_endpoint_private_access      = true

  # The IAM user that runs the first apply gets cluster-admin (kubectl from the laptop)
  enable_cluster_creator_admin_permissions = true

  cluster_security_group_additional_rules = {
    jenkins_to_api = {
      description              = "Jenkins to EKS private API endpoint (kubectl/helm)"
      type                     = "ingress"
      protocol                 = "tcp"
      from_port                = 443
      to_port                  = 443
      source_security_group_id = aws_security_group.jenkins.id
    }
  }

  eks_managed_node_groups = {
    default = {
      name           = "streamingapp-ng"
      ami_type       = "AL2023_x86_64_STANDARD" # AL2 is not available for EKS 1.33+
      instance_types = [var.node_instance]
      min_size       = var.node_min
      max_size       = var.node_max
      desired_size   = var.node_desired
      disk_size      = 20
      labels         = { Environment = var.environment }
      tags           = { AutoScaling = "enabled" }
      capacity_type  = "SPOT"
    }
  }

  # Exact versions (see var.eks_addon_versions) so every apply is reproducible
  cluster_addons = {
    coredns    = { addon_version = var.eks_addon_versions["coredns"] }
    kube-proxy = { addon_version = var.eks_addon_versions["kube-proxy"] }
    vpc-cni    = { addon_version = var.eks_addon_versions["vpc-cni"] }
    aws-ebs-csi-driver = {
      addon_version            = var.eks_addon_versions["aws-ebs-csi-driver"]
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
    }
  }

  # Lets the Jenkins EC2 role run kubectl/helm against the cluster
  access_entries = {
    jenkins = {
      principal_arn = aws_iam_role.jenkins.arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }
}
