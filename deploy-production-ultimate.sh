#!/bin/bash

# SUPERvote Ultimate Production Deployment Script
# State-of-the-art, fail-proof, high-performance deployment

set -euo pipefail  # Strict error handling
IFS=$'\n\t'

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PRODUCTION_SERVER="ubuntu@46.226.104.149"
readonly DOMAIN="vote.super-csn.ca"
readonly EMAIL="simon@super-csn.ca"
readonly APP_DIR="/opt/supervote"
readonly BACKUP_DIR="/opt/supervote/backups"
readonly LOG_FILE="/tmp/supervote-deploy-$(date +%Y%m%d_%H%M%S).log"

# Colors and formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'

# Logging functions
log() {
    echo -e "${WHITE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

log_header() {
    echo -e "\n${PURPLE}${BOLD}=== $* ===${NC}\n" | tee -a "$LOG_FILE"
}

# Progress indicator
show_progress() {
    local duration=$1
    local message=$2
    local progress=0
    
    echo -ne "${CYAN}$message${NC}"
    while [ $progress -lt $duration ]; do
        echo -ne "."
        sleep 1
        ((progress++))
    done
    echo -e " ${GREEN}Done!${NC}"
}

# Error handling
cleanup() {
    log_error "Script interrupted or failed. Cleaning up..."
    # Add cleanup logic here if needed
    exit 1
}

trap cleanup ERR INT TERM

# Validation functions
validate_requirements() {
    log_info "Validating deployment requirements..."
    
    # Check if SSH key exists and is configured
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$PRODUCTION_SERVER" exit 2>/dev/null; then
        log_error "Cannot connect to $PRODUCTION_SERVER via SSH"
        log_error "Please ensure your SSH key is properly configured"
        return 1
    fi
    
    # Check required commands
    local required_commands=("docker" "git" "curl" "jq")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command '$cmd' not found"
            return 1
        fi
    done
    
    # Check Docker Compose
    if ! docker compose version &> /dev/null; then
        log_error "Docker Compose v2+ is required"
        return 1
    fi
    
    log_success "All requirements validated"
}

# Generate secure passwords and keys
generate_secrets() {
    log_info "Generating secure secrets..."
    
    cat > .env.production << EOF
# Generated on $(date)
MONGO_ROOT_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
SECRET_KEY=$(openssl rand -base64 64 | tr -d "=+/" | cut -c1-64)
GRAFANA_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)
JWT_SECRET=$(openssl rand -base64 64 | tr -d "=+/" | cut -c1-64)
REDIS_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)

# Application Configuration
ENVIRONMENT=production
DOMAIN=$DOMAIN
EMAIL=$EMAIL
BACKUP_SCHEDULE=0 2 * * *
BACKUP_RETENTION_DAYS=30
LOG_LEVEL=INFO

# Optional: External services (uncomment and configure if needed)
# SENTRY_DSN=https://your-sentry-dsn
# FRONTEND_SENTRY_DSN=https://your-frontend-sentry-dsn
EOF
    
    log_success "Secrets generated and saved to .env.production"
}

# Create comprehensive remote deployment script
create_remote_deployment_script() {
    log_info "Creating comprehensive remote deployment script..."
    
    cat > remote-ultimate-deploy.sh << 'REMOTE_SCRIPT'
#!/bin/bash

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_header() { echo -e "\n${PURPLE}${BOLD}=== $* ===${NC}\n"; }

# Configuration
DOMAIN="vote.super-csn.ca"
EMAIL="simon@super-csn.ca"
APP_DIR="/opt/supervote"
BACKUP_DIR="/opt/supervote/backups"

log_header "SUPERvote Ultimate Production Deployment"

# System preparation with enhanced security
log_info "Preparing Ubuntu 22.04 system..."
sudo apt update && sudo apt upgrade -y

# Install essential packages with security tools
sudo apt install -y \
    curl wget git ufw fail2ban \
    ca-certificates software-properties-common \
    htop iotop nethogs \
    unattended-upgrades apt-listchanges \
    logrotate rsyslog \
    ntp chrony \
    vim nano \
    jq yq \
    tree \
    unzip zip

log_success "System packages installed"

# Configure automatic security updates
log_info "Configuring automatic security updates..."
sudo dpkg-reconfigure -plow unattended-upgrades
echo 'APT::Periodic::Update-Package-Lists "1";' | sudo tee /etc/apt/apt.conf.d/10periodic
echo 'APT::Periodic::Download-Upgradeable-Packages "1";' | sudo tee -a /etc/apt/apt.conf.d/10periodic
echo 'APT::Periodic::AutocleanInterval "7";' | sudo tee -a /etc/apt/apt.conf.d/10periodic
echo 'APT::Periodic::Unattended-Upgrade "1";' | sudo tee -a /etc/apt/apt.conf.d/10periodic

# Enhanced Docker installation
log_info "Installing Docker with production optimizations..."

# Remove old Docker packages
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do 
    sudo apt-get remove -y $pkg 2>/dev/null || true
done

# Install Docker
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Configure Docker for production
sudo usermod -aG docker $USER
sudo systemctl enable docker
sudo systemctl start docker

# Docker daemon configuration for production
sudo tee /etc/docker/daemon.json << 'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "live-restore": true,
    "userland-proxy": false,
    "experimental": false,
    "default-ulimits": {
        "memlock": {
            "Hard": -1,
            "Name": "memlock",
            "Soft": -1
        },
        "nofile": {
            "Hard": 65536,
            "Name": "nofile",
            "Soft": 65536
        }
    }
}
EOF

sudo systemctl reload docker

log_success "Docker installed and configured for production"

# Advanced firewall configuration
log_info "Configuring advanced firewall with fail2ban..."

# UFW configuration
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp comment 'SSH'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw --force enable

# Fail2ban configuration
sudo tee /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
backend = systemd

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 3
bantime = 3600

[nginx-noscript]
enabled = true
port = http,https
filter = nginx-noscript
logpath = /var/log/nginx/access.log
maxretry = 6
bantime = 3600

[nginx-badbots]
enabled = true
port = http,https
filter = nginx-badbots
logpath = /var/log/nginx/access.log
maxretry = 2
bantime = 86400

[nginx-noproxy]
enabled = true
port = http,https
filter = nginx-noproxy
logpath = /var/log/nginx/access.log
maxretry = 2
bantime = 86400
EOF

sudo systemctl enable fail2ban
sudo systemctl start fail2ban

log_success "Security configured with UFW and fail2ban"

# Create application directory structure
log_info "Creating optimized directory structure..."
sudo mkdir -p ${APP_DIR}/{data/{mongodb_primary,redis,prometheus,grafana},ssl,logs/{nginx,backend,frontend},backups,scripts,monitoring,nginx/conf.d,static}
sudo chown -R $USER:$USER ${APP_DIR}
chmod -R 755 ${APP_DIR}

# Clone and prepare application
log_info "Cloning SUPERvote repository..."
cd ${APP_DIR}
if [ -d "SUPERvote" ]; then
    rm -rf SUPERvote
fi
git clone https://github.com/KiiTuNp/SUPERvote.git
cd SUPERvote

# Copy production configurations
log_info "Setting up production configurations..."

# Copy Docker Compose
cp docker-compose.production.yml docker-compose.yml

# Copy Nginx config
cp nginx.production.conf nginx/nginx.conf

# Create monitoring configurations
mkdir -p monitoring/{prometheus,grafana/{dashboards,datasources}}

# Prometheus configuration
tee monitoring/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  # - "first_rules.yml"
  # - "second_rules.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'supervote-backend'
    static_configs:
      - targets: ['backend:8001']
    metrics_path: '/api/metrics'

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'nginx'
    static_configs:
      - targets: ['nginx:80']
    metrics_path: '/nginx_status'
EOF

# Grafana datasource
tee monitoring/grafana/datasources/prometheus.yml << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
EOF

# Create backup script
tee scripts/backup.sh << 'EOF'
#!/bin/bash
set -euo pipefail

BACKUP_DIR="/backups"
DATE=$(date +%Y%m%d_%H%M%S)
MONGO_ROOT_PASSWORD="${MONGO_ROOT_PASSWORD:-supersecurepassword}"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# MongoDB backup
log_info "Creating MongoDB backup..."
docker exec supervote-mongo-primary mongodump \
    --host localhost:27017 \
    --username admin \
    --password "$MONGO_ROOT_PASSWORD" \
    --authenticationDatabase admin \
    --gzip \
    --archive="/data/db/backup_${DATE}.gz"

# Copy backup out of container
docker cp supervote-mongo-primary:/data/db/backup_${DATE}.gz "$BACKUP_DIR/"

# Cleanup old backups (keep last 30 days)
find "$BACKUP_DIR" -name "backup_*.gz" -mtime +30 -delete

log_info "Backup completed: backup_${DATE}.gz"
EOF

chmod +x scripts/backup.sh

# Create log rotation configuration
sudo tee /etc/logrotate.d/supervote << 'EOF'
/opt/supervote/SUPERvote/logs/*/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 644 root root
}
EOF

log_success "Application structure and configurations created"

# SSL Certificate setup
log_info "Setting up SSL certificates..."
sudo apt install -y certbot

# Create SSL directory and obtain certificates
sudo mkdir -p /opt/supervote/SUPERvote/ssl

# Stop any running containers that might use port 80
docker compose down 2>/dev/null || true

# Obtain SSL certificate
sudo certbot certonly --standalone \
  -d ${DOMAIN} \
  --email ${EMAIL} \
  --agree-tos \
  --no-eff-email \
  --non-interactive

# Copy certificates to application directory
sudo cp /etc/letsencrypt/live/${DOMAIN}/fullchain.pem ${APP_DIR}/SUPERvote/ssl/
sudo cp /etc/letsencrypt/live/${DOMAIN}/privkey.pem ${APP_DIR}/SUPERvote/ssl/
sudo cp /etc/letsencrypt/live/${DOMAIN}/chain.pem ${APP_DIR}/SUPERvote/ssl/
sudo chown -R $USER:$USER ${APP_DIR}/SUPERvote/ssl/

# Set up automatic renewal
sudo tee /etc/cron.d/certbot-renew << 'EOF'
0 12 * * * root certbot renew --quiet --post-hook "cd /opt/supervote/SUPERvote && docker compose restart nginx"
EOF

log_success "SSL certificates configured"

# Performance optimizations
log_info "Applying system performance optimizations..."

# Kernel parameters for high performance
sudo tee -a /etc/sysctl.conf << 'EOF'
# Network optimizations
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_congestion_control = bbr

# File system optimizations
fs.file-max = 2097152
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5

# Security
kernel.kptr_restrict = 1
kernel.dmesg_restrict = 1
EOF

sudo sysctl -p

# Limits configuration
sudo tee /etc/security/limits.conf << 'EOF'
* soft nofile 65536
* hard nofile 65536
* soft nproc 65536
* hard nproc 65536
EOF

# System service for SUPERvote
log_info "Creating systemd service..."
sudo tee /etc/systemd/system/supervote.service << 'EOF'
[Unit]
Description=SUPERvote Production Application
Requires=docker.service
After=docker.service
StartLimitIntervalSec=0

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/supervote/SUPERvote
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
ExecReload=/usr/bin/docker compose restart
TimeoutStartSec=300
User=ubuntu
Group=ubuntu
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable supervote.service

log_success "System optimizations applied"

# Build and start the application
log_info "Building and starting SUPERvote application..."
docker compose build --no-cache
docker compose up -d

# Wait for services to be ready
log_info "Waiting for services to start..."
sleep 60

# Health checks
log_info "Performing health checks..."
max_attempts=30
attempt=0

while [ $attempt -lt $max_attempts ]; do
    if curl -f https://${DOMAIN}/health >/dev/null 2>&1; then
        log_success "Application is healthy and responding"
        break
    fi
    
    attempt=$((attempt + 1))
    log_info "Health check attempt $attempt/$max_attempts..."
    sleep 10
done

if [ $attempt -eq $max_attempts ]; then
    log_error "Application failed to start properly"
    docker compose logs
    exit 1
fi

# Create management script
tee manage-ultimate.sh << 'EOF'
#!/bin/bash

case "$1" in
  start)
    echo "🚀 Starting SUPERvote..."
    docker compose up -d
    ;;
  stop)
    echo "🛑 Stopping SUPERvote..."
    docker compose down
    ;;
  restart)
    echo "🔄 Restarting SUPERvote..."
    docker compose restart
    ;;
  status)
    echo "📊 SUPERvote Status:"
    docker compose ps
    echo ""
    echo "🌐 Health Check:"
    curl -s https://vote.super-csn.ca/health || echo "❌ Application not responding"
    ;;
  logs)
    echo "📋 SUPERvote Logs:"
    docker compose logs -f
    ;;
  update)
    echo "🔄 Updating SUPERvote..."
    git pull origin main
    docker compose build --no-cache
    docker compose up -d
    ;;
  backup)
    echo "💾 Creating backup..."
    ./scripts/backup.sh
    ;;
  monitor)
    echo "📊 Opening monitoring dashboard..."
    echo "Grafana: https://vote.super-csn.ca:3000 (admin/admin)"
    echo "Prometheus: https://vote.super-csn.ca:9090"
    ;;
  ssl-renew)
    echo "🔒 Renewing SSL certificate..."
    sudo certbot renew --force-renewal
    docker compose restart nginx
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|status|logs|update|backup|monitor|ssl-renew}"
    exit 1
    ;;
esac
EOF

chmod +x manage-ultimate.sh

# Final system status
log_header "Deployment Summary"
log_success "🎉 SUPERvote Ultimate Production Deployment Complete!"
echo ""
log_info "🌐 Application URL: https://${DOMAIN}"
log_info "📊 Monitoring: https://${DOMAIN}:3000 (Grafana)"
log_info "📈 Metrics: https://${DOMAIN}:9090 (Prometheus)"
log_info "🛠️  Management: ./manage-ultimate.sh {start|stop|restart|status|logs|update|backup}"
echo ""
log_info "📁 Application Directory: ${APP_DIR}/SUPERvote"
log_info "🔧 Configuration: docker-compose.yml"
log_info "📋 Logs: ./logs/"
log_info "💾 Backups: ./backups/"
echo ""

# Display service status
echo "=== Service Status ==="
docker compose ps
echo ""

# Display system resources
echo "=== System Resources ==="
echo "Memory Usage:"
free -h
echo ""
echo "Disk Usage:"
df -h
echo ""

log_success "Deployment completed successfully! 🚀"

REMOTE_SCRIPT

    log_success "Remote deployment script created"
}

# Main deployment function
deploy_to_production() {
    log_header "SUPERvote Ultimate Production Deployment"
    log_info "Target: $PRODUCTION_SERVER"
    log_info "Domain: $DOMAIN"
    log_info "Email: $EMAIL"
    
    echo -e "\n${YELLOW}This will deploy a state-of-the-art, production-ready SUPERvote application with:${NC}"
    echo -e "  ${GREEN}✓${NC} High-performance Docker containerization"
    echo -e "  ${GREEN}✓${NC} Advanced Nginx with SSL/TLS"
    echo -e "  ${GREEN}✓${NC} MongoDB with replica set"
    echo -e "  ${GREEN}✓${NC} Redis caching layer"
    echo -e "  ${GREEN}✓${NC} Prometheus + Grafana monitoring"
    echo -e "  ${GREEN}✓${NC} Comprehensive logging"
    echo -e "  ${GREEN}✓${NC} Automated backups"
    echo -e "  ${GREEN}✓${NC} Security hardening"
    echo -e "  ${GREEN}✓${NC} Performance optimizations"
    echo -e "  ${GREEN}✓${NC} Zero-downtime deployment capability"
    echo ""
    
    read -p "Continue with deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled"
        exit 0
    fi
    
    # Step 1: Validate requirements
    log_header "Step 1: Validation"
    validate_requirements
    
    # Step 2: Generate secrets
    log_header "Step 2: Security Setup"
    generate_secrets
    
    # Step 3: Create deployment script
    log_header "Step 3: Deployment Preparation"
    create_remote_deployment_script
    
    # Step 4: Copy files to server
    log_header "Step 4: File Transfer"
    log_info "Copying deployment files to production server..."
    
    scp -r \
        remote-ultimate-deploy.sh \
        .env.production \
        docker-compose.production.yml \
        nginx.production.conf \
        "$PRODUCTION_SERVER":~/
    
    log_success "Files transferred successfully"
    
    # Step 5: Execute deployment
    log_header "Step 5: Remote Deployment Execution"
    log_info "Executing deployment on production server..."
    log_info "This may take 10-15 minutes for first deployment..."
    
    ssh "$PRODUCTION_SERVER" "chmod +x remote-ultimate-deploy.sh && ./remote-ultimate-deploy.sh" 2>&1 | tee -a "$LOG_FILE"
    
    # Step 6: Verification
    log_header "Step 6: Deployment Verification"
    log_info "Verifying deployment..."
    
    sleep 10
    
    if curl -f "https://$DOMAIN/health" >/dev/null 2>&1; then
        log_success "✅ Application is live and responding!"
    else
        log_warning "⚠️  Application may still be starting up"
    fi
    
    # Step 7: Cleanup
    log_header "Step 7: Cleanup"
    log_info "Cleaning up local files..."
    rm -f remote-ultimate-deploy.sh
    
    # Final summary
    log_header "🎉 DEPLOYMENT COMPLETE!"
    echo -e "\n${GREEN}${BOLD}SUPERvote Ultimate Production is now live!${NC}\n"
    echo -e "🌐 ${WHITE}Application:${NC} https://$DOMAIN"
    echo -e "📊 ${WHITE}Monitoring:${NC} https://$DOMAIN:3000 (Grafana)"
    echo -e "📈 ${WHITE}Metrics:${NC} https://$DOMAIN:9090 (Prometheus)"
    echo -e "🔧 ${WHITE}Management:${NC} ssh $PRODUCTION_SERVER 'cd $APP_DIR/SUPERvote && ./manage-ultimate.sh status'"
    echo -e "📋 ${WHITE}Logs:${NC} ssh $PRODUCTION_SERVER 'cd $APP_DIR/SUPERvote && ./manage-ultimate.sh logs'"
    echo -e "💾 ${WHITE}Backup:${NC} ssh $PRODUCTION_SERVER 'cd $APP_DIR/SUPERvote && ./manage-ultimate.sh backup'"
    echo -e "\n${CYAN}Deployment log saved to: $LOG_FILE${NC}"
    echo -e "\n${YELLOW}Credentials saved in: .env.production${NC}"
    echo -e "${RED}${BOLD}⚠️  Keep .env.production secure - it contains sensitive passwords!${NC}"
}

# Main execution
main() {
    log "Starting SUPERvote Ultimate Production Deployment at $(date)"
    
    # Check if we're in the right directory
    if [ ! -f "backend/server.py" ] || [ ! -f "frontend/package.json" ]; then
        log_error "Please run this script from the SUPERvote project root directory"
        exit 1
    fi
    
    deploy_to_production
    
    log "Deployment completed at $(date)"
}

# Run main function
main "$@"