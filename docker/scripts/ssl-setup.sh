#!/bin/bash

# SSL Certificate Setup for vote.super-csn.ca
# Automated Let's Encrypt certificate management

set -euo pipefail

# Configuration
DOMAIN="vote.super-csn.ca"
EMAIL="simon@super-csn.ca"
SSL_DIR="./ssl"
CERTBOT_DIR="./certbot"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Check if domain resolves to current server
check_domain_dns() {
    log_info "Checking DNS resolution for $DOMAIN..."
    
    local domain_ip
    domain_ip=$(dig +short "$DOMAIN" @8.8.8.8 | tail -n1)
    
    if [ -z "$domain_ip" ]; then
        log_error "Domain $DOMAIN does not resolve to any IP"
        return 1
    fi
    
    local server_ip
    server_ip=$(curl -s -4 ifconfig.me 2>/dev/null || curl -s -4 icanhazip.com 2>/dev/null || echo "unknown")
    
    if [ "$domain_ip" = "$server_ip" ]; then
        log_success "Domain $DOMAIN correctly resolves to this server ($server_ip)"
    else
        log_warning "Domain $DOMAIN resolves to $domain_ip, but server IP is $server_ip"
        log_warning "SSL certificate generation may fail if domain doesn't point to this server"
    fi
}

# Setup directories
setup_directories() {
    log_info "Setting up SSL directories..."
    
    mkdir -p "$SSL_DIR" "$CERTBOT_DIR/www" "$CERTBOT_DIR/conf"
    chmod 755 "$SSL_DIR" "$CERTBOT_DIR"
    chmod 755 "$CERTBOT_DIR/www" "$CERTBOT_DIR/conf"
    
    log_success "SSL directories created"
}

# Install certbot if not available
install_certbot() {
    if command -v certbot >/dev/null 2>&1; then
        log_info "Certbot already installed: $(certbot --version)"
        return 0
    fi
    
    log_info "Installing certbot..."
    
    if command -v apt-get >/dev/null 2>&1; then
        # Ubuntu/Debian
        sudo apt-get update
        sudo apt-get install -y certbot
    elif command -v yum >/dev/null 2>&1; then
        # CentOS/RHEL
        sudo yum install -y certbot
    elif command -v apk >/dev/null 2>&1; then
        # Alpine
        sudo apk add --no-cache certbot
    else
        log_error "Cannot install certbot - unsupported package manager"
        return 1
    fi
    
    log_success "Certbot installed successfully"
}

# Generate initial certificates using standalone mode
generate_initial_certificates() {
    log_info "Generating initial SSL certificates for $DOMAIN..."
    
    # Stop nginx if running to free port 80
    if docker compose ps nginx | grep -q "Up"; then
        log_info "Stopping nginx temporarily..."
        docker compose stop nginx
        sleep 5
    fi
    
    # Generate certificate using standalone mode
    sudo certbot certonly \
        --standalone \
        --non-interactive \
        --agree-tos \
        --email "$EMAIL" \
        --domains "$DOMAIN" \
        --preferred-challenges http \
        --http-01-port 80 \
        --keep-until-expiring \
        --expand
    
    if [ $? -eq 0 ]; then
        log_success "SSL certificates generated successfully"
    else
        log_error "Failed to generate SSL certificates"
        return 1
    fi
    
    # Copy certificates to application directory
    copy_certificates
}

# Copy certificates from Let's Encrypt to application directory
copy_certificates() {
    log_info "Copying certificates to application directory..."
    
    local cert_dir="/etc/letsencrypt/live/$DOMAIN"
    
    if [ ! -d "$cert_dir" ]; then
        log_error "Certificate directory not found: $cert_dir"
        return 1
    fi
    
    # Copy certificates with proper permissions
    sudo cp "$cert_dir/fullchain.pem" "$SSL_DIR/"
    sudo cp "$cert_dir/privkey.pem" "$SSL_DIR/"
    sudo cp "$cert_dir/chain.pem" "$SSL_DIR/" 2>/dev/null || true
    
    # Set proper ownership and permissions
    sudo chown $USER:$USER "$SSL_DIR"/*.pem
    chmod 644 "$SSL_DIR"/fullchain.pem "$SSL_DIR"/chain.pem 2>/dev/null || true
    chmod 600 "$SSL_DIR"/privkey.pem
    
    log_success "Certificates copied to $SSL_DIR/"
}

# Setup automatic renewal
setup_renewal() {
    log_info "Setting up automatic certificate renewal..."
    
    # Create renewal script
    cat > ./ssl-renew.sh << 'EOF'
#!/bin/bash

# SSL Certificate Renewal Script
set -euo pipefail

DOMAIN="vote.super-csn.ca"
SSL_DIR="./ssl"

echo "[$(date)] Starting certificate renewal process..."

# Renew certificates
sudo certbot renew --quiet --no-self-upgrade

# Copy renewed certificates
if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
    sudo cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "$SSL_DIR/"
    sudo cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem" "$SSL_DIR/"
    sudo cp "/etc/letsencrypt/live/$DOMAIN/chain.pem" "$SSL_DIR/" 2>/dev/null || true
    
    # Set proper permissions
    sudo chown $USER:$USER "$SSL_DIR"/*.pem
    chmod 644 "$SSL_DIR"/fullchain.pem "$SSL_DIR"/chain.pem 2>/dev/null || true
    chmod 600 "$SSL_DIR"/privkey.pem
    
    echo "[$(date)] Certificates renewed and copied"
    
    # Reload nginx
    if docker compose ps nginx | grep -q "Up"; then
        docker compose exec nginx nginx -s reload
        echo "[$(date)] Nginx reloaded"
    fi
else
    echo "[$(date)] Certificate directory not found"
    exit 1
fi

echo "[$(date)] Certificate renewal completed"
EOF

    chmod +x ./ssl-renew.sh
    
    # Add to crontab for automatic renewal (runs twice daily)
    (crontab -l 2>/dev/null | grep -v "ssl-renew.sh"; echo "0 12 * * * cd $(pwd) && ./ssl-renew.sh >> ./logs/ssl-renewal.log 2>&1") | crontab -
    (crontab -l 2>/dev/null | grep -v "ssl-renew.sh"; echo "0 0 * * * cd $(pwd) && ./ssl-renew.sh >> ./logs/ssl-renewal.log 2>&1") | crontab -
    
    log_success "Automatic renewal configured (runs twice daily)"
}

# Verify certificates
verify_certificates() {
    log_info "Verifying SSL certificates..."
    
    if [ ! -f "$SSL_DIR/fullchain.pem" ] || [ ! -f "$SSL_DIR/privkey.pem" ]; then
        log_error "Certificate files not found in $SSL_DIR/"
        return 1
    fi
    
    # Check certificate validity
    local cert_info
    cert_info=$(openssl x509 -in "$SSL_DIR/fullchain.pem" -text -noout)
    
    local expiry_date
    expiry_date=$(echo "$cert_info" | grep "Not After" | cut -d: -f2- | sed 's/^[ \t]*//')
    
    local subject
    subject=$(echo "$cert_info" | grep "Subject:" | cut -d: -f2- | sed 's/^[ \t]*//')
    
    local san
    san=$(echo "$cert_info" | grep -A1 "Subject Alternative Name" | tail -n1 | sed 's/^[ \t]*//')
    
    log_success "Certificate verification:"
    echo "  Subject: $subject"
    echo "  Expires: $expiry_date"
    echo "  SAN: $san"
    
    # Check if certificate expires within 30 days
    local expiry_timestamp
    expiry_timestamp=$(date -d "$expiry_date" +%s)
    local current_timestamp
    current_timestamp=$(date +%s)
    local days_until_expiry
    days_until_expiry=$(( (expiry_timestamp - current_timestamp) / 86400 ))
    
    if [ $days_until_expiry -lt 30 ]; then
        log_warning "Certificate expires in $days_until_expiry days"
    else
        log_success "Certificate is valid for $days_until_expiry days"
    fi
}

# Test HTTPS connectivity
test_https() {
    log_info "Testing HTTPS connectivity..."
    
    # Start nginx if not running
    if ! docker compose ps nginx | grep -q "Up"; then
        log_info "Starting nginx..."
        docker compose up -d nginx
        sleep 10
    fi
    
    # Test HTTPS endpoint
    local response
    if response=$(curl -I -s -k "https://$DOMAIN" -m 10 2>/dev/null); then
        local status_code
        status_code=$(echo "$response" | head -n1 | cut -d' ' -f2)
        
        if [ "$status_code" -eq 200 ] || [ "$status_code" -eq 301 ] || [ "$status_code" -eq 302 ]; then
            log_success "HTTPS is working correctly (HTTP $status_code)"
        else
            log_warning "HTTPS returned HTTP $status_code"
        fi
    else
        log_warning "HTTPS test failed - site may not be fully configured yet"
    fi
}

# Main function
main() {
    echo "=== SSL Certificate Setup for $DOMAIN ==="
    echo
    
    # Prompt for confirmation
    echo "This script will:"
    echo "  1. Generate SSL certificates for $DOMAIN"
    echo "  2. Configure automatic renewal"
    echo "  3. Set up proper permissions"
    echo "  4. Test HTTPS connectivity"
    echo
    
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "SSL setup cancelled"
        exit 0
    fi
    
    # Check if certificates already exist
    if [ -f "$SSL_DIR/fullchain.pem" ] && [ -f "$SSL_DIR/privkey.pem" ]; then
        log_warning "SSL certificates already exist"
        read -p "Regenerate certificates? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            verify_certificates
            test_https
            exit 0
        fi
    fi
    
    # Run setup steps
    check_domain_dns
    setup_directories
    install_certbot
    generate_initial_certificates
    setup_renewal
    verify_certificates
    test_https
    
    echo
    log_success "🎉 SSL setup completed successfully!"
    echo
    echo "Next steps:"
    echo "  1. Your application is now accessible at: https://$DOMAIN"
    echo "  2. Certificates will auto-renew twice daily"
    echo "  3. Check renewal logs in: ./logs/ssl-renewal.log"
    echo "  4. Manual renewal: ./ssl-renew.sh"
    echo
}

# Show help
show_help() {
    echo "SSL Certificate Setup for SUPERvote"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -h, --help     Show this help"
    echo "  --renew-only   Only renew existing certificates"
    echo "  --verify-only  Only verify existing certificates"
    echo
}

# Parse arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    --renew-only)
        copy_certificates
        verify_certificates
        exit 0
        ;;
    --verify-only)
        verify_certificates
        test_https
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac