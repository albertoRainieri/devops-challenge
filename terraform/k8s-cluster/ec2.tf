# Data source for latest Ubuntu 22.04 AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# IAM Role for EC2 instances (for SSM access and token sharing)
resource "aws_iam_role" "k8s_nodes" {
  name = "${var.cluster_name}-nodes-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# IAM Policy for nodes
resource "aws_iam_role_policy" "k8s_nodes" {
  name = "${var.cluster_name}-nodes-policy"
  role = aws_iam_role.k8s_nodes.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:PutParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = [
          "arn:aws:ssm:${var.aws_region}:*:parameter/${var.cluster_name}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus"
        ]
        Resource = "*"
      }
    ]
  })
}

# Instance Profile
resource "aws_iam_instance_profile" "k8s_nodes" {
  name = "${var.cluster_name}-nodes-profile"
  role = aws_iam_role.k8s_nodes.name
}

# IAM Role for Bastion Host (to read SSM parameters)
resource "aws_iam_role" "bastion" {
  name = "${var.cluster_name}-bastion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# IAM Policy for Bastion (read-only SSM access)
resource "aws_iam_role_policy" "bastion" {
  name = "${var.cluster_name}-bastion-policy"
  role = aws_iam_role.bastion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = [
          "arn:aws:ssm:${var.aws_region}:*:parameter/${var.cluster_name}/*"
        ]
      }
    ]
  })
}

# Instance Profile for Bastion
resource "aws_iam_instance_profile" "bastion" {
  name = "${var.cluster_name}-bastion-profile"
  role = aws_iam_role.bastion.name
}

# Control Plane Node(s)
resource "aws_instance" "control_plane" {
  count                  = var.control_plane_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = local.key_name
  vpc_security_group_ids = [aws_security_group.k8s_control_plane.id]
  subnet_id              = aws_subnet.private.id
  iam_instance_profile   = aws_iam_instance_profile.k8s_nodes.name

  user_data = local.control_plane_user_data

  lifecycle {
    prevent_destroy = true
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-control-plane-${count.index + 1}"
      Role = "control-plane"
      Type = "k8s-control-plane"
    }
  )
}

# Worker Nodes
resource "aws_instance" "workers" {
  count                  = var.worker_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = local.key_name
  vpc_security_group_ids = [aws_security_group.k8s_workers.id]
  subnet_id              = aws_subnet.private.id
  iam_instance_profile   = aws_iam_instance_profile.k8s_nodes.name

  user_data = local.worker_user_data

  lifecycle {
    prevent_destroy = true
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-worker-${count.index + 1}"
      Role = "worker"
      Type = "k8s-worker"
    }
  )

  depends_on = [aws_instance.control_plane]
}

# Bastion Host
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.bastion_instance_type
  key_name                    = local.key_name
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  subnet_id                   = aws_subnet.public.id
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.bastion.name
  user_data                   = local.bastion_user_data

    lifecycle {
      prevent_destroy = true
    }

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-bastion"
      Role = "bastion"
      Type = "bastion-host"
    }
  )
}

# SSM Parameters will be created by the control plane user_data script
# These resources are here as placeholders and will be overwritten by the control plane
resource "aws_ssm_parameter" "kubeadm_join_command" {
  name  = "/${var.cluster_name}/kubeadm-join-command"
  type  = "SecureString"
  value = "placeholder" # Will be updated by control plane user_data

  tags = var.tags

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "kubeadm_token" {
  name  = "/${var.cluster_name}/kubeadm-token"
  type  = "SecureString"
  value = "placeholder" # Will be updated by control plane user_data

  tags = var.tags

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "ca_cert_hash" {
  name  = "/${var.cluster_name}/ca-cert-hash"
  type  = "String"
  value = "placeholder" # Will be updated by control plane user_data

  tags = var.tags

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "control_plane_ip" {
  name  = "/${var.cluster_name}/control-plane-ip"
  type  = "String"
  value = "placeholder" # Will be updated by control plane user_data

  tags = var.tags

  lifecycle {
    ignore_changes = [value]
  }
}

