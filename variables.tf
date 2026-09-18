# AWS Configuration
variable "aws_region" {
  description = "AWS region for Lightsail instance"
  type        = string
  default     = "ap-southeast-1"
}

variable "aws_profile" {
  description = "AWS CLI profile to use"
  type        = string
  default     = "adisoc"
}

variable "instance_name" {
  description = "Name for the GlitchTip Lightsail instance"
  type        = string
  default     = "glitchtip-server"
}

variable "blueprint_id" {
  description = "Lightsail OS blueprint"
  type        = string
  default     = "ubuntu_22_04" # Ubuntu 22.04 LTS
}

variable "bundle_id" {
  description = "Lightsail instance bundle ($10/mo: 2GB RAM, 2 vCPUs, 60GB SSD)"
  type        = string
  default     = "medium_2_0"
}

# SSH Configuration
variable "ssh_private_key_path" {
  description = "Path to SSH private key (without .pub)"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed to SSH"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Restrict this to your IP for enhanced security
}

variable "web_allowed_cidrs" {
  description = "CIDR blocks allowed HTTP and HTTPS access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Route 53 & Domain Configuration
variable "route53_zone_name" {
  description = "Name of the existing Route 53 Hosted Zone"
  type        = string
  default     = "adisoc.com"
}

variable "glitchtip_domain" {
  description = "Fully qualified domain name for GlitchTip"
  type        = string
  default     = "glitchtip.adisoc.com"
}

variable "route53_record_ttl" {
  description = "TTL for Route 53 DNS record in seconds"
  type        = number
  default     = 300
}

# SSL & Let's Encrypt Configuration
variable "letsencrypt_email" {
  description = "Email address for Let's Encrypt SSL certificate registration and expiration notices"
  type        = string
  default     = "admin@adisoc.com"
}

# GlitchTip Application Configuration
variable "enable_open_user_registration" {
  description = "Allow users to freely create accounts on GlitchTip"
  type        = bool
  default     = false
}

variable "db_name" {
  description = "PostgreSQL database name for GlitchTip"
  type        = string
  default     = "glitchtip"
}

variable "db_user" {
  description = "PostgreSQL database user"
  type        = string
  default     = "glitchtip"
}

variable "db_password" {
  description = "PostgreSQL database password (leave empty to generate automatically)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "glitchtip_secret_key" {
  description = "Django SECRET_KEY for GlitchTip (leave empty to generate automatically)"
  type        = string
  default     = ""
  sensitive   = true
}

# Resource Tags
variable "tags" {
  description = "Tags to apply to Lightsail resources"
  type        = map(string)
  default = {
    Project     = "GlitchTip-Monitoring"
    Environment = "production"
    Owner       = "devops"
  }
}

