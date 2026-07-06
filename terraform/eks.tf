module "eks" {
source = "terraform-aws-modules/eks/aws"
version = "~> 20.0"
cluster_name = var.cluster_name
cluster_version = var.cluster_version
vpc_id = module.vpc.vpc_id
subnet_ids = module.vpc.private_subnets
cluster_endpoint_public_access = true
eks_managed_node_groups = {
default = {
name = "streamingapp-ng"
instance_types = [var.node_instance]
min_size = var.node_min
max_size = var.node_max
desired_size = var.node_desired
disk_size = 20
labels = { Environment = var.environment }
tags = { AutoScaling = "enabled" }
}
}
cluster_addons = {
coredns = { most_recent = true }
kube-proxy = { most_recent = true }
vpc-cni = { most_recent = true }
}
}
