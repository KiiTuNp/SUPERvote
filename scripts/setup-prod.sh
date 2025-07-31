#!/bin/bash

# Production Setup Script for Vote Secret
# Run this script to set up the production environment

set -e

echo "🚀 Setting up Vote Secret for production deployment..."

# Create necessary directories
echo "📁 Creating necessary directories..."
mkdir -p nginx/ssl
mkdir -p logs
mkdir -p data/mongodb
mkdir -p data/backups

# Check if .env.prod exists
if [ ! -f .env.prod ]; then
    echo "❌ .env.prod file not found!"
    echo "Please copy .env.prod.example to .env.prod and configure your values"
    exit 1
fi

# Generate strong passwords if they don't exist
echo "🔐 Checking environment variables..."
source .env.prod

if [ -z "$MONGO_ROOT_PASSWORD" ] || [ "$MONGO_ROOT_PASSWORD" = "your_secure_mongo_root_password_here" ]; then
    echo "⚠️  WARNING: Please set a secure MONGO_ROOT_PASSWORD in .env.prod"
fi

if [ -z "$MONGO_USER_PASSWORD" ] || [ "$MONGO_USER_PASSWORD" = "your_secure_mongo_user_password_here" ]; then
    echo "⚠️  WARNING: Please set a secure MONGO_USER_PASSWORD in .env.prod"
fi

# SSL Certificate setup
echo "🔒 Setting up SSL certificates..."
if [ ! -f nginx/ssl/vote.super-csn.ca.crt ]; then
    echo "⚠️  SSL certificate not found at nginx/ssl/vote.super-csn.ca.crt"
    echo "Please place your SSL certificate files in the nginx/ssl directory:"
    echo "  - vote.super-csn.ca.crt (certificate file)"
    echo "  - vote.super-csn.ca.key (private key file)"
    echo ""
    echo "For Let's Encrypt certificates, you can use:"
    echo "  certbot certonly --webroot -w ./nginx/html -d vote.super-csn.ca"
fi

# Docker setup
echo "🐳 Preparing Docker environment..."
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

# Build production images
echo "🏗️  Building production Docker images..."
docker-compose -f docker-compose.prod.yml build

# Security checks
echo "🛡️  Running security checks..."
echo "Checking file permissions..."
chmod 600 .env.prod
chmod -R 600 nginx/ssl/ 2>/dev/null || echo "SSL directory not found - will be created"

# Create backup script
cat > scripts/backup.sh << 'EOF'
#!/bin/bash
# Backup script for Vote Secret production data

BACKUP_DIR="./data/backups"
DATE=$(date +%Y%m%d_%H%M%S)

echo "Creating backup at $BACKUP_DIR/backup_$DATE"
mkdir -p $BACKUP_DIR

# Backup MongoDB data
docker exec vote-secret-mongodb mongodump --host localhost --db vote_secret_db --out /tmp/backup_$DATE
docker cp vote-secret-mongodb:/tmp/backup_$DATE $BACKUP_DIR/
docker exec vote-secret-mongodb rm -rf /tmp/backup_$DATE

# Compress backup
cd $BACKUP_DIR
tar -czf mongodb_backup_$DATE.tar.gz backup_$DATE/
rm -rf backup_$DATE/

echo "Backup completed: mongodb_backup_$DATE.tar.gz"

# Keep only last 7 days of backups
find $BACKUP_DIR -name "mongodb_backup_*.tar.gz" -mtime +7 -delete
EOF

chmod +x scripts/backup.sh

echo "✅ Production setup completed!"
echo ""
echo "📋 Next steps:"
echo "1. Configure your SSL certificates in nginx/ssl/"
echo "2. Update .env.prod with your secure passwords"
echo "3. Configure your domain DNS to point to this server"
echo "4. Run: docker-compose -f docker-compose.prod.yml up -d"
echo "5. Monitor logs: docker-compose -f docker-compose.prod.yml logs -f"
echo ""
echo "🔍 Useful commands:"
echo "  - Start: docker-compose -f docker-compose.prod.yml up -d"
echo "  - Stop: docker-compose -f docker-compose.prod.yml down"
echo "  - Logs: docker-compose -f docker-compose.prod.yml logs -f"
echo "  - Backup: ./scripts/backup.sh"