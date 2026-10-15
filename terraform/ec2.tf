resource "aws_key_pair" "streamingapp" {
  key_name   = "streamingapp-key"
  public_key = file(var.ssh_public_key_path)
}

resource "aws_instance" "jenkins" {
  ami                         = var.jenkins_ami_id
  instance_type               = "t3.medium" # 4 GB RAM: npm ci + React build + Docker builds OOM on t3.small
  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.jenkins.id]
  key_name                    = aws_key_pair.streamingapp.key_name
  iam_instance_profile        = aws_iam_instance_profile.jenkins.name
  associate_public_ip_address = true

  root_block_device {
    volume_size = 30 # Docker images + node_modules fill the default 8 GB quickly
    volume_type = "gp3"
  }

  # Safety net: changing jenkins_ami_id must never replace the Jenkins server mid-pipeline
  # (rebuild deliberately from a laptop with -replace=aws_instance.jenkins)
  lifecycle {
    ignore_changes = [ami]
  }

  tags = {
    Name = "streamingapp-jenkins"
    Role = "jenkins"
  }
}

# Stable public IP so the GitHub webhook URL survives stop/start
resource "aws_eip" "jenkins" {
  instance = aws_instance.jenkins.id
  domain   = "vpc"

  tags = {
    Name = "streamingapp-jenkins-eip"
  }
}