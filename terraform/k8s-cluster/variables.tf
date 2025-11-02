variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "eu-north-1"
}

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
  default     = "devops-challenge-k8s"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for private subnet"
  type        = string
  default     = "10.0.11.0/24"
}

variable "availability_zone" {
  description = "Availability zone for subnets"
  type        = string
  default     = ""
}

variable "instance_type" {
  description = "EC2 instance type for Kubernetes nodes"
  type        = string
  default     = "t3.small"
}

variable "bastion_instance_type" {
  description = "EC2 instance type for bastion host (1 CPU, 1GB RAM)"
  type        = string
  default     = "t3.micro" # 2 vCPU, 1GB RAM (closest to 1 CPU, 1GB RAM)
}

variable "control_plane_count" {
  description = "Number of control plane nodes"
  type        = number
  default     = 1
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}

variable "key_name" {
  description = "Name of the AWS key pair for SSH access"
  type        = string
  default     = ""
}

variable "create_key_pair" {
  description = "Whether to create a new key pair"
  type        = bool
  default     = true
}

variable "k8s_version" {
  description = "Kubernetes version to install (e.g., 1.28.0)"
  type        = string
  default     = "1.28"
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project     = "DevOpsChallenge"
    ManagedBy   = "Terraform"
    Environment = "dev"
  }
}

