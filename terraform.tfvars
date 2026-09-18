# AWS Provider Configuration
aws_region    = "ap-southeast-1"
aws_profile   = "adisoc"
instance_name = "glitchtip-server"
blueprint_id  = "ubuntu_22_04"
bundle_id     = "medium_2_0" # $10/month: 2GB RAM, 2 vCPUs, 60GB SSD

# SSH Configuration - Ensure ~/.ssh/id_rsa.pub exists
ssh_private_key_path = "~/.ssh/id_rsa"
ssh_allowed_cidrs    = ["0.0.0.0/0"] # Restrict to your IP in production
web_allowed_cidrs    = ["0.0.0.0/0"]

# Route 53 & Domain
route53_zone_name    = "adisoc.com"
glitchtip_domain     = "glitchtip.adisoc.com"
route53_record_ttl   = 300

# SSL / Let's Encrypt
letsencrypt_email    = "admin@adisoc.com"

# GlitchTip Settings
enable_open_user_registration = false
db_name                       = "glitchtip"
db_user                       = "glitchtip"

# Resource Tags
tags = {
  Project     = "GlitchTip-Monitoring"
  Environment = "production"
  Owner       = "devops"
}

