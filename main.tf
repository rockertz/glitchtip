# GlitchTip Infrastructure on AWS Lightsail
# Complete automated deployment with Route 53 DNS, Let's Encrypt SSL, and Docker Compose

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

# -----------------------------------------------------------------------------
# DYNAMIC SECRETS GENERATION
# -----------------------------------------------------------------------------
resource "random_password" "db_password" {
  length  = 24
  special = false
}

resource "random_password" "glitchtip_secret_key" {
  length  = 50
  special = false
}

locals {
  db_password          = var.db_password != "" ? var.db_password : random_password.db_password.result
  glitchtip_secret_key = var.glitchtip_secret_key != "" ? var.glitchtip_secret_key : random_password.glitchtip_secret_key.result
}

# -----------------------------------------------------------------------------
# ROUTE 53 HOSTED ZONE LOOKUP
# -----------------------------------------------------------------------------
data "aws_route53_zone" "primary" {
  name         = "${trim(var.route53_zone_name, ".")}."
  private_zone = false
}

# -----------------------------------------------------------------------------
# LIGHTSAIL KEY PAIR
# -----------------------------------------------------------------------------
resource "aws_lightsail_key_pair" "glitchtip_key" {
  name       = "${var.instance_name}-key"
  public_key = file("${var.ssh_private_key_path}.pub")
}

# -----------------------------------------------------------------------------
# LIGHTSAIL INSTANCE
# -----------------------------------------------------------------------------
resource "aws_lightsail_instance" "glitchtip_server" {
  name              = var.instance_name
  availability_zone = "${var.aws_region}a"
  blueprint_id      = var.blueprint_id
  bundle_id         = var.bundle_id
  key_pair_name     = aws_lightsail_key_pair.glitchtip_key.name

  user_data = templatefile("${path.module}/userdata.sh", {
    glitchtip_domain              = var.glitchtip_domain
    letsencrypt_email             = var.letsencrypt_email
    db_name                       = var.db_name
    db_user                       = var.db_user
    db_password                   = local.db_password
    glitchtip_secret_key          = local.glitchtip_secret_key
    enable_open_user_registration = var.enable_open_user_registration
  })

  tags = var.tags
}

# -----------------------------------------------------------------------------
# STATIC IP & ATTACHMENT
# -----------------------------------------------------------------------------
resource "aws_lightsail_static_ip" "glitchtip_ip" {
  name = "${var.instance_name}-static-ip"
}

resource "aws_lightsail_static_ip_attachment" "glitchtip_ip_attachment" {
  static_ip_name = aws_lightsail_static_ip.glitchtip_ip.name
  instance_name  = aws_lightsail_instance.glitchtip_server.name

  lifecycle {
    replace_triggered_by = [aws_lightsail_instance.glitchtip_server.id]
  }
}

# -----------------------------------------------------------------------------
# ROUTE 53 DNS RECORD
# -----------------------------------------------------------------------------
resource "aws_route53_record" "glitchtip_dns" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = var.glitchtip_domain
  type    = "A"
  ttl     = var.route53_record_ttl
  records = [aws_lightsail_static_ip.glitchtip_ip.ip_address]

  depends_on = [aws_lightsail_static_ip_attachment.glitchtip_ip_attachment]
}

# -----------------------------------------------------------------------------
# LIGHTSAIL FIREWALL / PUBLIC PORTS
# -----------------------------------------------------------------------------
resource "aws_lightsail_instance_public_ports" "glitchtip_ports" {
  instance_name = aws_lightsail_instance.glitchtip_server.name

  lifecycle {
    replace_triggered_by = [aws_lightsail_instance.glitchtip_server.id]
  }

  # SSH access
  port_info {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
    cidrs     = var.ssh_allowed_cidrs
  }

  # HTTP - Let's Encrypt ACME verification & HTTPS redirect
  port_info {
    protocol  = "tcp"
    from_port = 80
    to_port   = 80
    cidrs     = var.web_allowed_cidrs
  }

  # HTTPS - GlitchTip Web UI and Sentry SDK ingestion
  port_info {
    protocol  = "tcp"
    from_port = 443
    to_port   = 443
    cidrs     = var.web_allowed_cidrs
  }
}

# -----------------------------------------------------------------------------
# POST-PROVISIONING HEALTH VERIFICATION
# -----------------------------------------------------------------------------
resource "terraform_data" "test_glitchtip_server" {
  depends_on = [
    aws_lightsail_static_ip_attachment.glitchtip_ip_attachment,
    aws_route53_record.glitchtip_dns
  ]

  provisioner "local-exec" {
    command     = "Start-Sleep -Seconds 180; Write-Host 'Waiting for GlitchTip cloud-init, SSL issuance, and Docker startup...'"
    interpreter = ["powershell", "-Command"]
  }

  provisioner "local-exec" {
    command = join("; ", [
      "Write-Host 'Testing GlitchTip HTTPS endpoint connectivity...'",
      "$response = try { Invoke-WebRequest -Uri 'https://${var.glitchtip_domain}' -TimeoutSec 15 -UseBasicParsing } catch { $null }",
      "if ($response -and ($response.StatusCode -eq 200 -or $response.StatusCode -eq 302)) { Write-Host 'GlitchTip server is online and serving HTTPS successfully!' } else { Write-Host 'GlitchTip is still starting up or initializing database. Check status via SSH: tail -f /var/log/user-data.log' }"
    ])
    interpreter = ["powershell", "-Command"]
  }
}

