# Generate a private key if creating a new key pair
resource "tls_private_key" "k8s_key" {
  count     = var.create_key_pair ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Upload the public key to AWS
resource "aws_key_pair" "k8s_key" {
  count      = var.create_key_pair ? 1 : 0
  key_name   = "${var.cluster_name}-key"
  public_key = tls_private_key.k8s_key[0].public_key_openssh

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-key"
    }
  )
}

# Save private key to local file
resource "local_file" "private_key" {
  count           = var.create_key_pair ? 1 : 0
  content         = tls_private_key.k8s_key[0].private_key_pem
  filename        = "${path.module}/${var.cluster_name}-key.pem"
  file_permission = "0600"
}

locals {
  key_name = var.create_key_pair ? aws_key_pair.k8s_key[0].key_name : var.key_name
}

