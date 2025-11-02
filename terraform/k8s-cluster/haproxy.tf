# HAProxy Configuration Template
# This file configures HAProxy on the bastion host via Terraform

# Template for HAProxy configuration
locals {
  haproxy_config = templatefile("${path.module}/templates/haproxy.cfg.tpl", {
    control_plane_ip = aws_instance.control_plane[0].private_ip
    worker_ips       = aws_instance.workers[*].private_ip
  })
}

# Configure HAProxy on bastion host
resource "null_resource" "configure_haproxy" {
  depends_on = [
    aws_instance.bastion,
    aws_instance.control_plane,
    aws_instance.workers,
    aws_ssm_parameter.control_plane_ip,
  ]

  triggers = {
    # Re-run if any worker IP changes
    worker_ips = join(",", aws_instance.workers[*].private_ip)
    # Re-run if control plane IP changes
    control_plane_ip = aws_instance.control_plane[0].private_ip
    # Re-run if HAProxy config template changes
    config_template = filemd5("${path.module}/templates/haproxy.cfg.tpl")
  }

  connection {
    type        = "ssh"
    host        = aws_instance.bastion.public_ip
    user        = "ubuntu"
    private_key = var.create_key_pair ? tls_private_key.k8s_key[0].private_key_pem : file("${path.module}/${var.cluster_name}-key.pem")
    timeout     = "5m"
  }

  # Copy HAProxy configuration to bastion
  provisioner "file" {
    content     = local.haproxy_config
    destination = "/tmp/haproxy.cfg"
  }

  # Validate and apply HAProxy configuration
  provisioner "remote-exec" {
    inline = [
      # Validate HAProxy configuration
      "sudo haproxy -f /tmp/haproxy.cfg -c",
      # Backup existing config
      "sudo cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.backup.$(date +%Y%m%d_%H%M%S) || true",
      # Install new config
      "sudo cp /tmp/haproxy.cfg /etc/haproxy/haproxy.cfg",
      # Reload HAProxy (graceful reload)
      "sudo systemctl reload haproxy || sudo systemctl restart haproxy",
      # Verify HAProxy is running
      "sudo systemctl status haproxy --no-pager || true",
      "echo 'HAProxy configuration updated successfully!'"
    ]
  }
}

