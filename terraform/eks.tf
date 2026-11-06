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

  # Cluster admins are listed explicitly (see access_entries below). The module's
  # 'creator' option follows whoever runs Terraform (laptop user vs Jenkins role)
  # and would flip the admin entry back and forth between them.
  enable_cluster_creator_admin_permissions = false

  # Same reason: fixed key administrators instead of 'current caller'
  kms_key_administrators = [local.admin_user_arn, aws_iam_role.jenkins.arn]

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

  # Sprint 5/6: the monitoring tests reach Prometheus, Alertmanager and Grafana through the API server's
  # service proxy (kubectl get --raw .../services/<svc>/proxy). The control plane may only reach the
  # pods' own ports when the node security group allows it; by default it allows webhook ports only.
  node_security_group_additional_rules = {
    api_to_prometheus = {
      description                   = "Cluster API to Prometheus (service proxy)"
      type                          = "ingress"
      protocol                      = "tcp"
      from_port                     = 9090
      to_port                       = 9090
      source_cluster_security_group = true
    }
    api_to_alertmanager = {
      description                   = "Cluster API to Alertmanager (service proxy)"
      type                          = "ingress"
      protocol                      = "tcp"
      from_port                     = 9093
      to_port                       = 9093
      source_cluster_security_group = true
    }
    api_to_grafana = {
      description                   = "Cluster API to Grafana (service proxy)"
      type                          = "ingress"
      protocol                      = "tcp"
      from_port                     = 3000
      to_port                       = 3000
      source_cluster_security_group = true
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

  access_entries = {
    # The admin IAM user: kubectl/helm from the laptop
    admin_user = {
      principal_arn = local.admin_user_arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }

    # The Jenkins EC2 role: kubectl/helm from the pipelines
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

data "aws_caller_identity" "current" {}

locals {
  # Account ID resolved at runtime - never hard-coded
  admin_user_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${var.admin_iam_user}"
}

# The first apply created the admin entry under the module's 'cluster_creator' key.
# Rename it in state instead of destroying and recreating it.
moved {
  from = module.eks.aws_eks_access_entry.this["cluster_creator"]
  to   = module.eks.aws_eks_access_entry.this["admin_user"]
}

moved {
  from = module.eks.aws_eks_access_policy_association.this["cluster_creator_admin"]
  to   = module.eks.aws_eks_access_policy_association.this["admin_user_admin"]
}
