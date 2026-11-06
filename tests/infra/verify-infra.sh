#!/usr/bin/env bash
# Sprint 6: infrastructure integrity - checks that what Terraform and Ansible built is really there
# and still configured securely. Read-only (describe/get calls only).
# Runs in the Verify infrastructure stage of jenkins/Jenkinsfile.ansible; locally from WSL (tests/README.md).
set -uo pipefail
source "$(dirname "$0")/../lib.sh"

REGION="${AWS_DEFAULT_REGION:-us-east-1}"
CLUSTER="${EKS_CLUSTER:-streamingapp-cluster}"
VIDEO_BUCKET="${S3_BUCKET:-streamingapp-videos}"
STATE_BUCKET="streamingapp-tfstate"
LOCK_TABLE="streamingapp-tflock"
export AWS_DEFAULT_REGION="$REGION"

section "EKS control plane"
check "cluster status" ACTIVE "$(aws eks describe-cluster --name "$CLUSTER" --query cluster.status --output text)"
check "Kubernetes version" 1.35 "$(aws eks describe-cluster --name "$CLUSTER" --query cluster.version --output text)"
check "private API endpoint enabled" True "$(aws eks describe-cluster --name "$CLUSTER" --query cluster.resourcesVpcConfig.endpointPrivateAccess --output text)"
CIDRS=$(aws eks describe-cluster --name "$CLUSTER" --query 'cluster.resourcesVpcConfig.publicAccessCidrs' --output text)
if [[ "$CIDRS" == */32 && "$CIDRS" != *0.0.0.0/0* && $(wc -w <<< "$CIDRS") -eq 1 ]]; then
  pass "public API endpoint limited to one admin /32 ($CIDRS)"
else
  fail "public API endpoint must allow only the admin /32 (got '$CIDRS')"
fi
for addon in coredns kube-proxy vpc-cni aws-ebs-csi-driver; do
  check "add-on $addon" ACTIVE "$(aws eks describe-addon --cluster-name "$CLUSTER" --addon-name "$addon" --query addon.status --output text 2>/dev/null)"
done

section "Worker nodes"
NG=$(aws eks list-nodegroups --cluster-name "$CLUSTER" --query 'nodegroups[0]' --output text)
check "node group status" ACTIVE "$(aws eks describe-nodegroup --cluster-name "$CLUSTER" --nodegroup-name "$NG" --query nodegroup.status --output text)"
check "node capacity type (cost: Spot)" SPOT "$(aws eks describe-nodegroup --cluster-name "$CLUSTER" --nodegroup-name "$NG" --query nodegroup.capacityType --output text)"
DESIRED=$(aws eks describe-nodegroup --cluster-name "$CLUSTER" --nodegroup-name "$NG" --query nodegroup.scalingConfig.desiredSize --output text)
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" > /dev/null
READY=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2 == "Ready"' | wc -l)
check_ge "nodes Ready (desired $DESIRED)" "$DESIRED" "$READY"

section "Network"
VPC=$(aws eks describe-cluster --name "$CLUSTER" --query cluster.resourcesVpcConfig.vpcId --output text)
check_ge "subnets in the VPC (2 public + 2 private)" 4 "$(aws ec2 describe-subnets --filters Name=vpc-id,Values="$VPC" --query 'length(Subnets)' --output text)"
check_ge "NAT gateway available" 1 "$(aws ec2 describe-nat-gateways --filter Name=vpc-id,Values="$VPC" Name=state,Values=available --query 'length(NatGateways)' --output text)"
OPEN=$(aws ec2 describe-security-groups --filters Name=group-name,Values=streamingapp-jenkins-sg \
  --query 'SecurityGroups[0].IpPermissions[?IpRanges[?CidrIp==`0.0.0.0/0`]].FromPort' --output text)
check "Jenkins security group has no port open to 0.0.0.0/0" "" "$OPEN"

section "Jenkins server"
check "Jenkins instance running" running "$(aws ec2 describe-instances --filters Name=tag:Name,Values=streamingapp-jenkins \
  --query 'Reservations[0].Instances[0].State.Name' --output text)"
check "Jenkins uses an IAM instance profile (no static keys)" True "$(aws ec2 describe-instances --filters Name=tag:Name,Values=streamingapp-jenkins \
  --query 'Reservations[0].Instances[0].IamInstanceProfile != `null`' --output text)"

section "Storage and registries"
check "video bucket blocks public access" "True True True True" "$(aws s3api get-public-access-block --bucket "$VIDEO_BUCKET" \
  --query 'PublicAccessBlockConfiguration.[BlockPublicAcls,IgnorePublicAcls,BlockPublicPolicy,RestrictPublicBuckets]' --output text | tr '\t' ' ')"
check "video bucket encrypted" AES256 "$(aws s3api get-bucket-encryption --bucket "$VIDEO_BUCKET" \
  --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text)"
check "Terraform state bucket versioned" Enabled "$(aws s3api get-bucket-versioning --bucket "$STATE_BUCKET" --query Status --output text)"
check "Terraform lock table" ACTIVE "$(aws dynamodb describe-table --table-name "$LOCK_TABLE" --query Table.TableStatus --output text)"
for repo in frontend auth-service streaming-service admin-service chat-service; do
  check "ECR streamingapp/$repo immutable + scan on push" "IMMUTABLE True" "$(aws ecr describe-repositories --repository-names "streamingapp/$repo" \
    --query 'repositories[0].[imageTagMutability,imageScanningConfiguration.scanOnPush]' --output text | tr '\t' ' ')"
done

section "Cluster configuration (Ansible bootstrap)"
check "default StorageClass" gp3 "$(kubectl get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}')"
for d in aws-load-balancer-controller metrics-server; do
  check_ge "kube-system/$d available replicas" 1 "$(kubectl get deploy "$d" -n kube-system -o jsonpath='{.status.availableReplicas}')"
done
check "application namespace" Active "$(kubectl get namespace streamingapp -o jsonpath='{.status.phase}')"
check "application secret has 6 keys" 6 "$(kubectl get secret streamingapp-secrets -n streamingapp -o json | json 'len(d["data"])')"

finish
