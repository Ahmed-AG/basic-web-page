provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

# Variables
variable "aws_profile" {
  description = "AWS profile to use"
  type        = string
  default     = "lw-cs1-admin-role-271985591511"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "users" {
  description = "List of user emails"
  type        = list(string)
  default     = [
    "user1@example.com", "user2@example.com"
    ]
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "ami_id" {
  description = "AMI ID for EC2 instances"
  type        = string
  default     = "ami-01034f11c291816b6"
}

# Convert email addresses into valid key names (replace @ and .)
locals {
  sanitized_users = [for user in var.users : replace(replace(user, "@", "-at-"), ".", "-dot-")]
}


# Create VPC
resource "aws_vpc" "FortiCNAPP_Training_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "FortiCNAPP-Training-VPC"
  }
}

# Create Subnet
resource "aws_subnet" "FortiCNAPP_Training_subnet" {
  vpc_id                  = aws_vpc.FortiCNAPP_Training_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "FortiCNAPP-Training-Subnet"
  }
}

# Get Availability Zones
data "aws_availability_zones" "available" {}

# Create Internet Gateway
resource "aws_internet_gateway" "FortiCNAPP_Training_gw" {
  vpc_id = aws_vpc.FortiCNAPP_Training_vpc.id

  tags = {
    Name = "FortiCNAPP-Training-InternetGateway"
  }
}

# Route Table
resource "aws_route_table" "FortiCNAPP_Training_rt" {
  vpc_id = aws_vpc.FortiCNAPP_Training_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.FortiCNAPP_Training_gw.id
  }

  tags = {
    Name = "FortiCNAPP-Training-RouteTable"
  }
}

# Associate Route Table with Subnet
resource "aws_route_table_association" "FortiCNAPP_Training_rta" {
  subnet_id      = aws_subnet.FortiCNAPP_Training_subnet.id
  route_table_id = aws_route_table.FortiCNAPP_Training_rt.id
}

# Security Group (Allow SSH & HTTP)
resource "aws_security_group" "FortiCNAPP_Training_sg" {
  vpc_id = aws_vpc.FortiCNAPP_Training_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allow SSH from anywhere (CHANGE for security)
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allow HTTP access from anywhere
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "FortiCNAPP-Training-SecurityGroup"
  }
}

# Create a unique SSH Key Pair for each user (Key names match email identifiers)
resource "tls_private_key" "FortiCNAPP_Training_key" {
  count      = length(var.users)
  algorithm  = "RSA"
  rsa_bits   = 4096
}

resource "aws_key_pair" "FortiCNAPP_Training_keypair" {
  count      = length(var.users)
  key_name   = "FortiCNAPP-Key-${local.sanitized_users[count.index]}"
  public_key = tls_private_key.FortiCNAPP_Training_key[count.index].public_key_openssh
}

# 🔹 Save the Private Key Locally (Named After the User)
resource "local_file" "FortiCNAPP_Training_private_key" {
  count    = length(var.users)
  content  = tls_private_key.FortiCNAPP_Training_key[count.index].private_key_pem
  filename = "${path.module}/FortiCNAPP-Key-${local.sanitized_users[count.index]}.pem"
  file_permission = "0600"
}

# Create Multiple EC2 Instances (One per User)
resource "aws_instance" "FortiCNAPP_Training_instances" {
  count                  = length(var.users)
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.FortiCNAPP_Training_subnet.id
  vpc_security_group_ids = [aws_security_group.FortiCNAPP_Training_sg.id]
  key_name               = aws_key_pair.FortiCNAPP_Training_keypair[count.index].key_name
  associate_public_ip_address = true

  tags = {
    Name  = "FortiCNAPP-Instance-${local.sanitized_users[count.index]}"
    Owner = var.users[count.index] # Assign the user email to the instance tag
  }
}

# Output Public IP Addresses of Instances
output "FortiCNAPP_Training_instance_public_ips" {
  description = "Public IPs of the instances"
  value       = aws_instance.FortiCNAPP_Training_instances[*].public_ip
}

# Output SSH Key Paths (Names Correspond to User Emails)
output "FortiCNAPP_Training_private_key_paths" {
  description = "Paths to the SSH private keys for each instance"
  value       = local_file.FortiCNAPP_Training_private_key[*].filename
}

# 🔹 Output SSH Commands for Each User
output "FortiCNAPP_Training_ssh_instructions" {
  description = "Instructions to SSH into the instances"
  value = [
    for idx, ip in aws_instance.FortiCNAPP_Training_instances[*].public_ip :
    "ssh -i FortiCNAPP-Key-${local.sanitized_users[idx]}.pem ubuntu@${ip}"
  ]
}
