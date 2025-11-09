# EFS File System
resource "aws_efs_file_system" "main" {
  creation_token   = "${var.cluster_name}-efs"
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  encrypted        = true

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = merge(
    var.tags,
    {
      Name                      = "${var.cluster_name}-efs"
      "efs.csi.aws.com/cluster" = "true"
    }
  )
}

# EFS Mount Target for Private Subnet (where worker nodes are located)
resource "aws_efs_mount_target" "private" {
  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = aws_subnet.private.id
  security_groups = [aws_security_group.efs.id]
}

# Security Group for EFS
resource "aws_security_group" "efs" {
  name        = "${var.cluster_name}-efs-sg"
  description = "Security group for EFS file system"
  vpc_id      = aws_vpc.main.id

  # NFS traffic from VPC
  ingress {
    description     = "NFS from VPC"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.k8s_workers.id]
  }

  # Allow all outbound traffic
  egress {
    description     = "All outbound traffic"
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.k8s_workers.id]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-efs-sg"
    }
  )
}

# Data source for current AWS account ID
data "aws_caller_identity" "current" {}

resource "aws_iam_policy" "aws_efs_csi_driver_policy" {
  count       = 1
  name        = "${var.cluster_name}-csi-driver-policy"
  path        = "/"
  description = "AWS EFS CSI driver policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:DescribeAccessPoints",
          "elasticfilesystem:DescribeFileSystems",
          "elasticfilesystem:DescribeMountTargets",
          "ec2:DescribeAvailabilityZones"
        ],
        Resource = [
          "*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:CreateAccessPoint"
        ],
        Resource = [
          "*"
        ],
        Condition = {
          StringLike = {
            "aws:RequestTag/efs.csi.aws.com/cluster" = "true"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:TagResource"
        ],
        Resource = [
          "*"
        ],
        Condition = {
          StringLike = {
            "aws:ResourceTag/efs.csi.aws.com/cluster" = "true"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:DeleteAccessPoint"
        ],
        Resource = [
          "*"
        ],
        Condition = {
          StringEquals = {
            "aws:ResourceTag/efs.csi.aws.com/cluster" = "true"
          }
        }
      },
    ]
  })

}

# # Attach AWS managed policy for full EFS access
# resource "aws_iam_role_policy_attachment" "efs_full_access" {
#   count = 1
#   role       = aws_iam_role.k8s_nodes.name
#   policy_arn = aws_iam_policy.aws_efs_csi_driver_policy[0].arn
# }

# resource "null_resource" "generate_efs_mount_script" {

#   provisioner "local-exec" {
#     command = templatefile("efs_mount.tpl", {
#       efs_mount_point = "/mnt/"
#       file_system_id  = aws_efs_file_system.main.id
#     })
#     interpreter = [
#       "bash",
#       "-c"
#     ]
#   }
# }

# resource "null_resource" "execute_script" {

#   count = 2

#   # Changes to any instance of the cluster requires re-provisioning
#   triggers = {
#     instance_id = aws_instance.workers[count.index].id
#   }

#   provisioner "file" {
#     source      = "efs_mount.sh"
#     destination = "efs_mount.sh"
#   }

#   connection {
#     host        = aws_instance.workers[count.index].private_ip
#     type        = "ssh"
#     user        = "ubuntu"
#     private_key = var.create_key_pair ? tls_private_key.k8s_key[0].private_key_pem : file("${path.module}/${var.cluster_name}-key.pem")

#     bastion_host        = aws_instance.bastion.public_ip
#     bastion_user        = "ubuntu"
#     bastion_private_key = var.create_key_pair ? tls_private_key.k8s_key[0].private_key_pem : file("${path.module}/${var.cluster_name}-key.pem")
#   }

#   provisioner "remote-exec" {
#     # Bootstrap script called for each node in the cluster
#     inline = [
#       "bash efs_mount.sh",
#     ]
#   }
# }

# EFS File System Policy - Allow IAM role to create/delete access points
# resource "aws_efs_file_system_policy" "main" {
#   file_system_id = aws_efs_file_system.main.id

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Sid    = "AllowEFSCSIDriver"
#         Effect = "Allow"
#         Principal = {
#           AWS = aws_iam_role.k8s_nodes.arn
#         }
#         Action = [
#           "elasticfilesystem:CreateAccessPoint",
#           "elasticfilesystem:DeleteAccessPoint",
#         ]
#         Resource = "*"
#         Condition = {
#           StringLike = {
#             "aws:RequestTag/efs.csi.aws.com/cluster" = "true"
#           }
#         }
#       }
#     ]
#   })
# }

# Tag added to EFS file system above for CSI driver identification
# The tag "efs.csi.aws.com/cluster" = "true" is included in the EFS file system tags

