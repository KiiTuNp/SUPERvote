#!/bin/bash

# SSL Setup Script with Certbot for Vote Secret
# Automatically configures HTTPS for vote.super-csn.ca

set -e

echo "🔒 Setting up SSL certificates with Certbot for vote.super-csn.ca"

# Check if running as root or with sudo
if [[ $EUID -eq 0 ]]; then
    SUDO=""
else
    SUDO="sudo"
fi

# Install required packages
echo "📦 Installing required packages..."
$SUDO apt update
$SUDO apt install -y python3-certbot-nginx docker.io docker-compose

# Create necessary directories
echo "📁 Creating SSL directories..."
mkdir -p certbot/conf
mkdir -p certbot/www
mkdir -p nginx/ssl

# Load environment variables
if [ -f .env.prod ]; then
    source .env.prod
else
    echo "❌ .env.prod file not found!"
    exit 1
fi

# Check if passwords are configured
if [ "$MONGO_ROOT_PASSWORD" = "your_secure_mongo_root_password_here" ] || [ "$MONGO_USER_PASSWORD" = "your_secure_mongo_user_password_here" ]; then
    echo "❌ Please configure secure passwords in .env.prod first!"
    exit 1
fi

# Start nginx for initial certificate generation
echo "🚀 Starting nginx for certificate challenge..."
docker-compose -f docker-compose.prod.yml up -d nginx

# Wait for nginx to be ready
echo "⏳ Waiting for nginx to start..."
sleep 10

# Check if nginx is running
if ! docker ps | grep -q vote-secret-nginx; then
    echo "❌ Nginx failed to start!"
    docker-compose -f docker-compose.prod.yml logs nginx
    exit 1
fi

# Generate initial certificate
echo "🔐 Generating SSL certificate with Certbot..."
docker run --rm \
    -v $(pwd)/certbot/conf:/etc/letsencrypt \
    -v $(pwd)/certbot/www:/var/www/certbot \
    certbot/certbot:latest \
    certonly --webroot \
    --webroot-path=/var/www/certbot \
    --email admin@super-csn.ca \
    --agree-tos \
    --no-eff-email \
    --staging \
    -d vote.super-csn.ca

# Check if staging certificate was generated successfully
if [ -d "certbot/conf/live/vote.super-csn.ca" ]; then
    echo "✅ Staging certificate generated successfully!"
    
    # Generate production certificate
    echo "🔐 Generating production SSL certificate..."
    docker run --rm \
        -v $(pwd)/certbot/conf:/etc/letsencrypt \
        -v $(pwd)/certbot/www:/var/www/certbot \
        certbot/certbot:latest \
        certonly --webroot \
        --webroot-path=/var/www/certbot \
        --email admin@super-csn.ca \
        --agree-tos \
        --no-eff-email \
        --force-renewal \
        -d vote.super-csn.ca
        
    if [ -d "certbot/conf/live/vote.super-csn.ca" ]; then
        echo "✅ Production certificate generated successfully!"
    else
        echo "❌ Failed to generate production certificate!"
        exit 1
    fi
else
    echo "❌ Failed to generate staging certificate!"
    echo "Please ensure:"
    echo "  1. Domain vote.super-csn.ca points to this server"
    echo "  2. Ports 80 and 443 are open"
    echo "  3. No other web server is running on these ports"
    exit 1
fi

# Restart nginx with SSL configuration
echo "🔄 Restarting nginx with SSL configuration..."
docker-compose -f docker-compose.prod.yml down nginx
docker-compose -f docker-compose.prod.yml up -d nginx

# Wait for nginx to restart
sleep 10

# Test SSL configuration
echo "🧪 Testing SSL configuration..."
if docker exec vote-secret-nginx nginx -t; then
    echo "✅ Nginx SSL configuration is valid!"
else
    echo "❌ Nginx SSL configuration error!"
    docker-compose -f docker-compose.prod.yml logs nginx
    exit 1
fi

# Setup auto-renewal cron job
echo "⏰ Setting up automatic certificate renewal..."
cat > /tmp/renewal-script.sh << 'EOF'
#!/bin/bash
docker run --rm \
    -v /opt/vote-secret/certbot/conf:/etc/letsencrypt \
    -v /opt/vote-secret/certbot/www:/var/www/certbot \
    certbot/certbot:latest \
    renew --quiet

# Reload nginx if certificates were renewed
if [ $? -eq 0 ]; then
    docker exec vote-secret-nginx nginx -s reload
fi
EOF

$SUDO mv /tmp/renewal-script.sh /usr/local/bin/renew-vote-secret-ssl.sh
$SUDO chmod +x /usr/local/bin/renew-vote-secret-ssl.sh

# Add cron job for auto-renewal (runs twice daily)
(crontab -l 2>/dev/null; echo "0 12 * * * /usr/local/bin/renew-vote-secret-ssl.sh") | crontab -
(crontab -l 2>/dev/null; echo "0 0 * * * /usr/local/bin/renew-vote-secret-ssl.sh") | crontab -

echo "✅ SSL setup completed successfully!"
echo ""
echo "🔗 Your application should now be available securely at:"
echo "   https://vote.super-csn.ca"
echo ""
echo "📋 SSL Management:"
echo "  - Certificates auto-renew every 12 hours"
echo "  - Manual renewal: /usr/local/bin/renew-vote-secret-ssl.sh"
echo "  - Certificate location: ./certbot/conf/live/vote.super-csn.ca/"
echo "  - Certificate expires: $(docker run --rm -v $(pwd)/certbot/conf:/etc/letsencrypt certbot/certbot:latest certificates | grep 'Expiry Date')"
echo ""
echo "🔍 SSL Test Commands:"
echo "  - Test SSL: curl -I https://vote.super-csn.ca"
echo "  - Check certificate: openssl s_client -connect vote.super-csn.ca:443 -servername vote.super-csn.ca"
echo "  - SSL Labs test: https://www.ssllabs.com/ssltest/analyze.html?d=vote.super-csn.ca"