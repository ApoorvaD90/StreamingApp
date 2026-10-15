resource "aws_security_group" "jenkins" {
  name        = "streamingapp-jenkins-sg"
  description = "Security group for the Jenkins CI/CD EC2 instance"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "Jenkins web UI"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "GitHub webhooks to Jenkins"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = var.github_webhook_cidrs
  }

  ingress {
    description = "SSH from inside the VPC (Ansible run by Jenkins)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Outbound only (no inbound exposure): Jenkins must reach apt, ECR, GitHub, npm and Docker Hub
  egress {
    description = "Outbound internet access for package, image and source downloads"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "streamingapp-jenkins-sg"
  }
}
