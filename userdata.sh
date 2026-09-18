#!/bin/bash
# cloud-init can execute user data with /bin/sh on some images; keep flags POSIX-safe.
set -eu

# Redirect stdout and stderr to both console and log file
exec >> /var/log/user-data.log 2>&1
echo "=================================================="
echo "=== Starting GlitchTip Automated Deployment    ==="
echo "=== Timestamp: $(date) ==="
echo "=================================================="

##################################################
# 1. CONFIGURE SWAP (OOM PROTECTION)
##################################################
if [ ! -f /swapfile ]; then
  echo "[1/9] Creating 2GB swap space for Celery worker & build stability..."
  fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# Set swappiness to 10 to prefer RAM
sysctl -w vm.swappiness=10
grep -q '^vm.swappiness=' /etc/sysctl.conf && sed -i 's/^vm.swappiness=.*/vm.swappiness=10/' /etc/sysctl.conf || echo 'vm.swappiness=10' >> /etc/sysctl.conf

##################################################
# 2. SYSTEM UPDATES & PREREQUISITES
##################################################
echo "[2/9] Updating system packages and installing dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  ufw \
  cron \
  dnsutils \
  certbot

##################################################
# 3. INSTALL DOCKER & DOCKER COMPOSE PLUGIN
##################################################
echo "[3/9] Installing Docker Engine..."
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
  systemctl enable docker
  systemctl start docker
fi

echo "Docker version: $(docker --version)"
echo "Docker compose version: $(docker compose version)"

##################################################
# 4. VERIFY DNS PROPAGATION
##################################################
echo "[4/9] Checking Route 53 DNS propagation for ${glitchtip_domain}..."
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || curl -s https://api.ipify.org)
echo "Instance Public IP: $PUBLIC_IP"

MAX_RETRIES=30
for i in $(seq 1 $MAX_RETRIES); do
  RESOLVED_IP=$(dig +short "${glitchtip_domain}" @8.8.8.8 | tail -n1 || true)
  echo "DNS Check attempt $i/$MAX_RETRIES: resolved to '$RESOLVED_IP' (Target: $PUBLIC_IP)"
  if [ "$RESOLVED_IP" = "$PUBLIC_IP" ]; then
    echo "DNS propagation confirmed for ${glitchtip_domain}!"
    break
  fi
  sleep 10
done

##################################################
# 5. GENERATE SSL VIA CERTBOT STANDALONE
##################################################
echo "[5/9] Provisioning SSL certificate via Certbot standalone..."
mkdir -p /var/www/certbot

if [ ! -d "/etc/letsencrypt/live/${glitchtip_domain}" ]; then
  certbot certonly \
    --standalone \
    --non-interactive \
    --agree-tos \
    --email "${letsencrypt_email}" \
    -d "${glitchtip_domain}"
  echo "SSL certificate successfully obtained."
else
  echo "SSL certificate already exists."
fi

##################################################
# 6. SETUP GLITCHTIP WORKSPACE & DIRS
##################################################
echo "[6/9] Preparing directories and configurations..."
mkdir -p /opt/glitchtip/nginx
mkdir -p /opt/glitchtip/postgres-data
mkdir -p /opt/glitchtip/redis-data
mkdir -p /opt/glitchtip/uploads

# Nginx reverse proxy configuration
cat > /opt/glitchtip/nginx/nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    keepalive_timeout  65;

    map $http_upgrade $connection_upgrade {
        default upgrade;
        '' close;
    }

    upstream glitchtip_backend {
        server web:8000;
    }

    # HTTP: ACME renewal challenges and HTTPS redirection
    server {
        listen 80;
        server_name ${glitchtip_domain};

        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }

        location / {
            return 301 https://$host$request_uri;
        }
    }

    # HTTPS: SSL Reverse Proxy to GlitchTip Web
    server {
        listen 443 ssl;
        http2 on;
        server_name ${glitchtip_domain};

        ssl_certificate /etc/letsencrypt/live/${glitchtip_domain}/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/${glitchtip_domain}/privkey.pem;

        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_prefer_server_ciphers on;
        ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384";

        # Max payload size for Sentry/GlitchTip event payloads
        client_max_body_size 50M;

        location / {
            proxy_pass http://glitchtip_backend;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;
            proxy_redirect off;
            proxy_read_timeout 120s;
        }
    }
}
EOF

# GlitchTip Docker Compose configuration
cat > /opt/glitchtip/docker-compose.yml << 'EOF'
services:
  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${db_name}
      POSTGRES_USER: ${db_user}
      POSTGRES_PASSWORD: ${db_password}
    volumes:
      - /opt/glitchtip/postgres-data:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine
    restart: unless-stopped
    volumes:
      - /opt/glitchtip/redis-data:/data

  web:
    image: glitchtip/glitchtip:latest
    restart: unless-stopped
    depends_on:
      - postgres
      - redis
    environment:
      DATABASE_URL: postgres://${db_user}:${db_password}@postgres:5432/${db_name}
      REDIS_URL: redis://redis:6379/0
      SECRET_KEY: "${glitchtip_secret_key}"
      GLITCHTIP_DOMAIN: "https://${glitchtip_domain}"
      ENABLE_OPEN_USER_REGISTRATION: "${enable_open_user_registration}"
      CELERY_WORKER_AUTOSCALE: "1,4"
      CELERY_WORKER_MAX_TASKS_PER_CHILD: 10000
      PORT: 8000
    volumes:
      - /opt/glitchtip/uploads:/code/uploads
    expose:
      - "8000"

  worker:
    image: glitchtip/glitchtip:latest
    restart: unless-stopped
    command: ./bin/run-celery-with-beat.sh
    depends_on:
      - postgres
      - redis
    environment:
      DATABASE_URL: postgres://${db_user}:${db_password}@postgres:5432/${db_name}
      REDIS_URL: redis://redis:6379/0
      SECRET_KEY: "${glitchtip_secret_key}"
      GLITCHTIP_DOMAIN: "https://${glitchtip_domain}"
      ENABLE_OPEN_USER_REGISTRATION: "${enable_open_user_registration}"
      CELERY_WORKER_AUTOSCALE: "1,4"
      CELERY_WORKER_MAX_TASKS_PER_CHILD: 10000
    volumes:
      - /opt/glitchtip/uploads:/code/uploads

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    depends_on:
      - web
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /opt/glitchtip/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
      - /var/www/certbot:/var/www/certbot:ro
EOF

##################################################
# 7. INITIALIZE DATABASE & START STACK
##################################################
echo "[7/9] Running initial database migrations..."
cd /opt/glitchtip

# Start database first
docker compose up -d postgres redis

# Wait for PostgreSQL to accept connections
echo "Waiting for postgres to accept connections..."
for attempt in $(seq 1 30); do
  if docker compose exec -T postgres pg_isready -U ${db_user} -d ${db_name} >/dev/null 2>&1; then
    echo "PostgreSQL is ready!"
    break
  fi
  echo "PostgreSQL not ready yet, waiting 2s... ($attempt/30)"
  sleep 2
done

# Run Django database migrations
echo "Executing ./manage.py migrate..."
docker compose run --rm web ./manage.py migrate

# Start all services
echo "Starting full GlitchTip stack..."
docker compose up -d

##################################################
# 8. SYSTEMD SERVICE & SSL AUTO-RENEWAL CRON
##################################################
echo "[8/9] Configuring systemd persistence and SSL auto-renewal..."

# Systemd service for GlitchTip
cat > /etc/systemd/system/glitchtip.service << 'EOF'
[Unit]
Description=GlitchTip Docker Compose Application
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/glitchtip
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable glitchtip.service

# Daily Certbot renewal cron with Nginx reload
(crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --webroot -w /var/www/certbot --post-hook 'docker compose -f /opt/glitchtip/docker-compose.yml exec -T nginx nginx -s reload' >> /var/log/certbot-renew.log 2>&1") | crontab -

# Health check script and cron (every 5 minutes)
cat > /opt/glitchtip/health-check.sh << 'EOF'
#!/bin/bash
if curl -k -f -s https://127.0.0.1/ > /dev/null 2>&1; then
    echo "$(date): GlitchTip is healthy"
else
    echo "$(date): GlitchTip health check failed. Restarting containers..."
    docker compose -f /opt/glitchtip/docker-compose.yml restart
fi
EOF
chmod +x /opt/glitchtip/health-check.sh
(crontab -l 2>/dev/null; echo "*/5 * * * * /opt/glitchtip/health-check.sh >> /var/log/glitchtip-health.log 2>&1") | crontab -

##################################################
# 9. FIREWALL CONFIGURATION
##################################################
echo "[9/9] Configuring UFW host firewall..."
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "=================================================="
echo "=== GlitchTip Installation Complete!          ==="
echo "=== URL: https://${glitchtip_domain}         ==="
echo "=================================================="
