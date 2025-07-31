#!/bin/bash

# Secure Deployment Script for Vote Secret Production
# Complete deployment with SSL certificates and security hardening

set -e

echo "🚀 Deploying Vote Secret securely to vote.super-csn.ca..."

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    echo "⚠️  Running as root. Consider using a non-root user with sudo access."
    SUDO=""
else
    SUDO="sudo"
fi

# Load environment variables
if [ -f .env.prod ]; then
    source .env.prod
else
    echo "❌ .env.prod file not found!"
    echo "Please run: cp .env.prod.example .env.prod and configure your settings"
    exit 1
fi

# Validate environment variables
echo "🔍 Validating environment configuration..."
if [ "$MONGO_ROOT_PASSWORD" = "your_secure_mongo_root_password_here" ] || [ -z "$MONGO_ROOT_PASSWORD" ]; then
    echo "❌ Please set a secure MONGO_ROOT_PASSWORD in .env.prod"
    exit 1
fi

if [ "$MONGO_USER_PASSWORD" = "your_secure_mongo_user_password_here" ] || [ -z "$MONGO_USER_PASSWORD" ]; then
    echo "❌ Please set a secure MONGO_USER_PASSWORD in .env.prod"
    exit 1
fi

# System requirements check
echo "🔧 Checking system requirements..."
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    $SUDO apt update
    $SUDO apt install -y docker.io docker-compose
    $SUDO systemctl enable docker
    $SUDO systemctl start docker
    $SUDO usermod -aG docker $USER
fi

if ! command -v docker-compose &> /dev/null; then
    echo "Installing Docker Compose..."
    $SUDO apt install -y docker-compose
fi

# Security hardening
echo "🛡️  Applying security hardening..."

# Set proper file permissions
chmod 600 .env.prod
chmod -R 755 scripts/
find . -name "*.sh" -exec chmod +x {} \;

# Create backup directory
mkdir -p data/backups
chmod 755 data/backups

# Pre-deployment cleanup
echo "🧹 Cleaning up previous deployment..."
docker-compose -f docker-compose.prod.yml down --remove-orphans || true
docker system prune -f || true

# Build production images
echo "🏗️  Building production images..."
docker-compose -f docker-compose.prod.yml build --no-cache

# Start core services first
echo "🗄️  Starting database..."
docker-compose -f docker-compose.prod.yml up -d mongodb

# Wait for MongoDB to be healthy
echo "⏳ Waiting for MongoDB to be ready..."
timeout=60
while [ $timeout -gt 0 ]; do
    if docker exec vote-secret-mongodb mongosh --eval "db.adminCommand('ping')" &>/dev/null; then
        echo "✅ MongoDB is ready!"
        break
    fi
    echo "Waiting for MongoDB... ($timeout seconds remaining)"
    sleep 2
    timeout=$((timeout-2))
done

if [ $timeout -le 0 ]; then
    echo "❌ MongoDB failed to start within 60 seconds"
    docker-compose -f docker-compose.prod.yml logs mongodb
    exit 1
fi

# Start backend
echo "🔧 Starting backend API..."
docker-compose -f docker-compose.prod.yml up -d backend

# Wait for backend to be healthy
echo "⏳ Waiting for backend to be ready..."
timeout=60
while [ $timeout -gt 0 ]; do
    if docker exec vote-secret-backend curl -f http://localhost:8001/api/health &>/dev/null; then
        echo "✅ Backend API is ready!"
        break
    fi
    echo "Waiting for backend API... ($timeout seconds remaining)"
    sleep 2
    timeout=$((timeout-2))
done

if [ $timeout -le 0 ]; then
    echo "❌ Backend failed to start within 60 seconds"
    docker-compose -f docker-compose.prod.yml logs backend
    exit 1
fi

# Start frontend
echo "🎨 Starting frontend..."
docker-compose -f docker-compose.prod.yml up -d frontend

# Wait for frontend to be ready
echo "⏳ Waiting for frontend to be ready..."
timeout=60
while [ $timeout -gt 0 ]; do
    if docker exec vote-secret-frontend curl -f http://localhost:3000/health &>/dev/null; then
        echo "✅ Frontend is ready!"
        break
    fi
    echo "Waiting for frontend... ($timeout seconds remaining)"
    sleep 2
    timeout=$((timeout-2))
done

if [ $timeout -le 0 ]; then
    echo "❌ Frontend failed to start within 60 seconds"
    docker-compose -f docker-compose.prod.yml logs frontend
    exit 1
fi

# Start nginx
echo "🌐 Starting nginx reverse proxy..."
docker-compose -f docker-compose.prod.yml up -d nginx

# Check if SSL certificates exist
if [ ! -d "certbot/conf/live/vote.super-csn.ca" ]; then
    echo "🔒 SSL certificates not found. Running SSL setup..."
    ./scripts/setup-ssl.sh
else
    echo "✅ SSL certificates found!"
fi

# Final health checks
echo "🏥 Running final health checks..."

# Test database
if docker exec vote-secret-mongodb mongosh --eval "db.adminCommand('ping')" &>/dev/null; then
    echo "✅ Database: Connected"
else
    echo "❌ Database: Connection failed"
    exit 1
fi

# Test backend API
if docker exec vote-secret-backend curl -f http://localhost:8001/api/health &>/dev/null; then
    echo "✅ Backend API: Healthy"
else
    echo "❌ Backend API: Health check failed"
    exit 1
fi

# Test frontend
if docker exec vote-secret-frontend curl -f http://localhost:3000/health &>/dev/null; then
    echo "✅ Frontend: Healthy"
else
    echo "❌ Frontend: Health check failed"
    exit 1
fi

# Test nginx configuration
if docker exec vote-secret-nginx nginx -t &>/dev/null; then
    echo "✅ Nginx: Configuration valid"
else
    echo "❌ Nginx: Configuration error"
    docker-compose -f docker-compose.prod.yml logs nginx
    exit 1
fi

# Test external HTTPS access
echo "🌐 Testing external HTTPS access..."
sleep 5
if curl -k -f -m 10 https://vote.super-csn.ca/health &>/dev/null; then
    echo "✅ HTTPS: External access working"
else
    echo "⚠️  HTTPS: External access test failed (might be expected if DNS not configured yet)"
fi

# Display deployment summary
echo ""
echo "🎉 Deployment completed successfully!"
echo ""
echo "📊 Service Status:"
docker-compose -f docker-compose.prod.yml ps
echo ""
echo "🔗 Application URLs:"
echo "   🌐 Production: https://vote.super-csn.ca"
echo "   🏥 Health Check: https://vote.super-csn.ca/health"
echo "   🔧 API Health: https://vote.super-csn.ca/api/health"
echo ""
echo "📋 Management Commands:"
echo "   📊 Status: docker-compose -f docker-compose.prod.yml ps"
echo "   📜 Logs: docker-compose -f docker-compose.prod.yml logs -f"
echo "   🔄 Restart: docker-compose -f docker-compose.prod.yml restart"
echo "   🛑 Stop: docker-compose -f docker-compose.prod.yml down"
echo "   💾 Backup: ./scripts/backup.sh"
echo ""
echo "🔐 SSL Certificate:"
echo "   📅 Auto-renewal: Configured (runs twice daily)"
echo "   🔍 Manual renewal: /usr/local/bin/renew-vote-secret-ssl.sh"
echo "   📋 Certificate info: docker run --rm -v \$(pwd)/certbot/conf:/etc/letsencrypt certbot/certbot:latest certificates"
echo ""
echo "🛡️  Security Features Enabled:"
echo "   ✅ HTTPS with Let's Encrypt"
echo "   ✅ HSTS headers"
echo "   ✅ Security headers (XSS, CSRF, etc.)"
echo "   ✅ Rate limiting"
echo "   ✅ Database authentication"
echo "   ✅ Internal network isolation"
echo ""
echo "🎯 Next Steps:"
echo "   1. Ensure DNS for vote.super-csn.ca points to this server"
echo "   2. Test the application: https://vote.super-csn.ca"
echo "   3. Monitor logs for any issues"
echo "   4. Schedule regular backups"
echo ""
echo "📞 Support:"
echo "   📜 Documentation: README-PRODUCTION.md"
echo "   📊 Monitoring: docker-compose -f docker-compose.prod.yml logs -f"