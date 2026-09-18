output "glitchtip_static_ip" {
  description = "Static IP address assigned to the GlitchTip Lightsail instance"
  value       = aws_lightsail_static_ip.glitchtip_ip.ip_address
}

output "glitchtip_url" {
  description = "Public HTTPS URL for GlitchTip web interface and DSN endpoints"
  value       = "https://${var.glitchtip_domain}"
}

output "route53_record_fqdn" {
  description = "Fully qualified domain name configured in Route 53"
  value       = aws_route53_record.glitchtip_dns.fqdn
}

output "ssh_command" {
  description = "SSH connection command to manage the GlitchTip instance"
  value       = "ssh -i ${var.ssh_private_key_path} ubuntu@${aws_lightsail_static_ip.glitchtip_ip.ip_address}"
}

output "instance_details" {
  description = "Details of the provisioned Lightsail instance"
  value = {
    name              = aws_lightsail_instance.glitchtip_server.name
    blueprint_id      = aws_lightsail_instance.glitchtip_server.blueprint_id
    bundle_id         = aws_lightsail_instance.glitchtip_server.bundle_id
    availability_zone = aws_lightsail_instance.glitchtip_server.availability_zone
  }
}

output "create_superuser_command" {
  description = "Run this command via SSH to create the initial GlitchTip superuser"
  value       = "ssh -i ${var.ssh_private_key_path} ubuntu@${aws_lightsail_static_ip.glitchtip_ip.ip_address} 'sudo docker compose -f /opt/glitchtip/docker-compose.yml run --rm web ./manage.py createsuperuser'"
}

output "db_password" {
  description = "Generated PostgreSQL database password"
  value       = local.db_password
  sensitive   = true
}

output "glitchtip_secret_key" {
  description = "Generated GlitchTip Django SECRET_KEY"
  value       = local.glitchtip_secret_key
  sensitive   = true
}

