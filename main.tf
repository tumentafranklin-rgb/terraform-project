terraform {
  required_version = ">= 1.2"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.92"
    }
  }
}

provider "aws" {
  region              = "us-east-2"
  
}

variable "allowed_public_ipv4" {
  description = "Public IPv4 address you connect from, without /32."
  type        = string

  validation {
    condition     = can(cidrnetmask("${var.allowed_public_ipv4}/32"))
    error_message = "Enter one IPv4 address without a CIDR suffix."
  }
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "vpc"
  }
}

resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "Public-Subnet"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "IGW"
  }
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "route_table"
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.rt.id
}

resource "aws_security_group" "web_sg" {
  name        = "web-server-sg"
  description = "Allow SSH and Taskboard access from the approved IPv4 address"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.allowed_public_ipv4}/32"]
  }

  ingress {
    description = "Taskboard"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["${var.allowed_public_ipv4}/32"]
  }

  egress {
    description = "Allow outbound traffic for updates and Docker pulls"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "web-server-sg"
  }
}

resource "aws_key_pair" "taskboard" {
  key_name_prefix = "taskboard-devops-"
  public_key      = trimspace(file(pathexpand("~/.ssh/taskboard-devops.pub")))
}

resource "aws_instance" "example" {
  ami                    = "ami-0b064c912c726f739"
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.taskboard.key_name
  subnet_id              = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  depends_on = [aws_route_table_association.a]

  user_data = <<-EOF
    #!/bin/bash
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive

    apt-get -o Acquire::Retries=5 update
    apt-get -o DPkg::Lock::Timeout=120 install -y docker.io
    systemctl enable --now docker

    docker run -d \
      --name taskboard \
      --restart unless-stopped \
      -p 80:80 \
     tumenta3322/student-management:jenkins-7
  EOF

  user_data_replace_on_change = true

  tags = {
    Name = "shiloh"
  }
}

output "taskboard_url" {
  description = "Open this URL after the startup script finishes."
  value       = "http://${aws_instance.example.public_ip}:5000"
}

output "ssh_command" {
  description = "Run this command from the Ubuntu VM that holds the private key."
  value       = "ssh -i ~/.ssh/taskboard-devops ubuntu@${aws_instance.example.public_ip}"
}