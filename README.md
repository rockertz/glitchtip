# GlitchTip on AWS Lightsail with Terraform

Automated infrastructure and deployment for **GlitchTip** (an open-source, Sentry-compatible error tracking platform) on AWS Lightsail with Route 53 DNS and Let's Encrypt SSL.

---

## Architecture Overview

```
                      +──────────────────────────────────────────────+
                      |         AWS Lightsail: Ubuntu 22.04          |
                      |   (bundle: medium_2_0, 2GB RAM, 2 vCPUs)     |
                      +──────────────────────────────────────────────+
                                             │
Clients / SDKs                               ▼
      │                     ┌────────────────────────────────┐
      │ HTTPS (443)         │   Nginx SSL Reverse Proxy      │
      ├────────────────────►│  (/etc/letsencrypt / certbot)  │
      │                     └───────────────┬────────────────┘
      │                                     │ Proxy (8000)
Route 53 A Record                           ▼
glitchtip.adisoc.com        ┌────────────────────────────────┐
                            │    GlitchTip Web (Django)      │
                            └───────┬────────────────┬───────┘
                                    │                │
                      ┌─────────────▼──────┐   ┌─────▼───────────────┐
                      │ PostgreSQL 16      │   │ Redis 7 Alpine      │
                      │ (Persistent Data)  │   │ (Celery Broker)     │
                      └─────────────▲──────┘   └─────▲───────────────┘
                                    │                │
                            ┌───────┴────────────────┴───────┐
                            │  GlitchTip Celery Worker       │
                            │  (./bin/run-celery-with-beat)  │
                            └────────────────────────────────┘
```

---

## Technical Specifications

| Component | Specification |
| :--- | :--- |
| **Instance Blueprint** | `ubuntu_22_04` (Ubuntu 22.04 LTS) |
| **Bundle Size** | `medium_2_0` ($10/month: 2GB RAM, 2 vCPUs, 60GB SSD) |
| **Swap Space** | 2GB auto-created swap file (`/swapfile`) with swappiness=10 |
| **Firewall Ports** | 22 (SSH), 80 (HTTP/ACME), 443 (HTTPS) |
| **DNS Record** | Route 53 `A` record pointing `glitchtip.adisoc.com` to static Lightsail IP |
| **SSL Automation** | Certbot standalone on first boot; automatic cron renewal with Nginx reload |
| **Services** | Docker Compose: PostgreSQL 16, Redis 7, GlitchTip Web, Celery Worker, Nginx |

---

## Recommended 4-Step Development Approach

When developing and verifying this automated cloud-init deployment:

### Step 1: Deploy Minimal Infrastructure Scaffold
Test instance creation, static IP allocation, and Route 53 DNS routing first before relying on full userdata automation:
```bash
# Verify Route 53 hosted zone exists and SSH key is present
terraform init
terraform plan
terraform apply
```

### Step 2: Interactive SSH Prototyping
Connect to the server via SSH to inspect environment behavior in real time:
```bash
ssh -i ~/.ssh/id_rsa ubuntu@<GLITCHTIP_STATIC_IP>

# Check DNS resolution from the instance:
dig +short glitchtip.adisoc.com @8.8.8.8

# Watch the cloud-init bootstrap progress live:
tail -f /var/log/user-data.log
```

### Step 3: Codify and Tune `userdata.sh`
If any issues or container adjustments arise (e.g. database migration timing, Celery autoscale parameters), adjust `userdata.sh` so every fix is captured as code.

### Step 4: Full Teardown and Clean "Day-0" Rebuild
Destroy the testing stack and redeploy to guarantee zero-touch automation:
```bash
terraform destroy -auto-approve
terraform apply -auto-approve
```

---

## Quick Start / Deployment

### 1. Prerequisites
- AWS CLI configured with profile `adisoc` (or customize `aws_profile` in `terraform.tfvars`).
- Public SSH key available at `~/.ssh/id_rsa.pub`.
- Route 53 hosted zone `adisoc.com` already active in your AWS account.

### 2. Configure Variables
Review and adjust `terraform.tfvars` if needed:
```hcl
aws_region        = "ap-southeast-1"
aws_profile       = "adisoc"
route53_zone_name = "adisoc.com"
glitchtip_domain  = "glitchtip.adisoc.com"
letsencrypt_email = "admin@adisoc.com"
```

### 3. Initialize & Deploy
```bash
terraform init
terraform apply
```

Deployment takes approximately 3 to 4 minutes:
- Lightsail instance and static IP are provisioned.
- Route 53 A-record is created.
- Userdata runs system updates, installs Docker & Certbot.
- SSL certificate is requested and issued.
- Database migrations execute and the Docker Compose stack starts up.
- Terraform waits and performs an automated HTTPS connectivity test.

---

## Day-1 Operations

### 1. Create Initial Superuser (Admin)
Once the instance is online, run the superuser creation command (available in `terraform output create_superuser_command`):
```bash
ssh -i ~/.ssh/id_rsa ubuntu@<STATIC_IP> 'sudo docker compose -f /opt/glitchtip/docker-compose.yml run --rm web ./manage.py createsuperuser'
```
Follow the prompts to enter an admin email and password.

### 2. Log in to GlitchTip
Open `https://glitchtip.adisoc.com` in your browser and sign in with the credentials created above.

### 3. Verify Event Ingestion with Python Test Script
A test script [`test_glitchtip.py`](file:///c:/Users/Pradeep/Project/adisoc/glitchtip/test_glitchtip.py) is included in the repository. Run it to send a sample message and handled exception:
```bash
python test_glitchtip.py
```
Or specify a custom DSN:
```bash
python test_glitchtip.py --dsn "https://<key>@glitchtip.adisoc.com/<project_id>"
```
Check your GlitchTip project dashboard to see the captured issues immediately.

### 4. Retrieve Generated Credentials
To view the automatically generated database password or secret key:
```bash
terraform output db_password
terraform output glitchtip_secret_key
```

### 4. Check Running Services
```bash
ssh -i ~/.ssh/id_rsa ubuntu@<STATIC_IP>
cd /opt/glitchtip
sudo docker compose ps
```

Expected output:
```
NAME                 IMAGE                     STATUS
glitchtip-nginx-1    nginx:alpine              Up (healthy/running)
glitchtip-postgres-1 postgres:16-alpine        Up (healthy)
glitchtip-redis-1    redis:7-alpine            Up
glitchtip-web-1      glitchtip/glitchtip:latest Up
glitchtip-worker-1   glitchtip/glitchtip:latest Up
```

---

## Troubleshooting & Maintenance

### View Boot Logs
```bash
sudo cat /var/log/user-data.log
```

### View Application Logs
```bash
cd /opt/glitchtip
sudo docker compose logs -f web
sudo docker compose logs -f worker
```

### SSL Certificate Renewal
Certbot is automatically configured to renew certificates daily via cron. To test the renewal process manually:
```bash
sudo certbot renew --dry-run
```
Renewal hooks reload the Nginx container automatically upon certificate update.

