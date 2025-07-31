#!/bin/bash

# Deployment script for Vote Secret production
set -e

echo "🚀 Deploying Vote Secret to production..."

# Load environment variables
if [ -f .env.prod ]; then
    source .env.prod
else
    echo "❌ .env.prod file not found!"
    exit 1
fi

# Pre-deployment checks
echo "🔍 Running pre-deployment checks..."

# Check if SSL certificates exist
if [ ! -f nginx/ssl/vote.super-csn.ca.crt ] || [ ! -f nginx/ssl/vote.super-csn.ca.key ]; then
    echo "❌ SSL certificates not found!"
    echo "Please ensure SSL certificates are placed in nginx/ssl/"
    exit 1
fi

# Check if passwords are configured
if [ "$MONGO_ROOT_PASSWORD" = "your_secure_mongo_root_password_here" ] || [ "$MONGO_USER_PASSWORD" = "your_secure_mongo_user_password_here" ]; then
    echo "❌ Default passwords detected in .env.prod!"
    echo "Please configure secure passwords before deployment."
    exit 1
fi

# Stop existing containers if running
echo "🛑 Stopping existing containers..."
docker-compose -f docker-compose.prod.yml down --remove-orphans || true

# Pull latest images and rebuild
echo "🏗️  Building production images..."
docker-compose -f docker-compose.prod.yml build --no-cache

# Start services
echo "🚀 Starting production services..."
docker-compose -f docker-compose.prod.yml up -d

# Wait for services to be healthy
echo "⏳ Waiting for services to start..."
sleep 30

# Health checks
echo "🏥 Running health checks..."

# Check MongoDB
echo "Checking MongoDB..."
if docker exec vote-secret-mongodb mongosh --eval "db.adminCommand('ping')" > /dev/null 2>&1; then
    echo "✅ MongoDB is healthy"
else
    echo "❌ MongoDB health check failed"
    docker-compose -f docker-compose.prod.yml logs mongodb
    exit 1
fi

# Check Backend
echo "Checking Backend API..."
if docker exec vote-secret-backend curl -f http://localhost:8001/api/health > /dev/null 2>&1; then
    echo "✅ Backend API is healthy"
else
    echo "❌ Backend API health check failed"
    docker-compose -f docker-compose.prod.yml logs backend
    exit 1
fi

# Check Frontend
echo "Checking Frontend..."
if docker exec vote-secret-frontend curl -f http://localhost:3000/health > /dev/null 2>&1; then
    echo "✅ Frontend is healthy"
else
    echo "❌ Frontend health check failed"
    docker-compose -f docker-compose.prod.yml logs frontend
    exit 1
fi

# Check Nginx
echo "Checking Nginx..."
if docker exec vote-secret-nginx nginx -t > /dev/null 2>&1; then
    echo "✅ Nginx configuration is valid"
else
    echo "❌ Nginx configuration check failed"
    docker-compose -f docker-compose.prod.yml logs nginx
    exit 1
fi

# Final URL check
echo "🌐 Testing external access..."
sleep 10
if curl -k -f https://vote.super-csn.ca/health > /dev/null 2>&1; then
    echo "✅ External HTTPS access is working"
else
    echo "⚠️  External HTTPS access check failed - this might be expected if DNS is not yet configured"
fi

echo ""
echo "🎉 Deployment completed successfully!"
echo ""
echo "📊 Service Status:"
docker-compose -f docker-compose.prod.yml ps

echo ""
echo "🔗 Your application should be available at:"
echo "   https://vote.super-csn.ca"
echo ""
echo "📋 Management commands:"
echo "   View logs: docker-compose -f docker-compose.prod.yml logs -f"
echo "   Stop services: docker-compose -f docker-compose.prod.yml down"
echo "   Restart: docker-compose -f docker-compose.prod.yml restart"
echo "   Backup: ./scripts/backup.sh"