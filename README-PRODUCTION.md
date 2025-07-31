# Vote Secret - Production Deployment Guide

## 🚀 Production Setup for vote.super-csn.ca

This guide covers deploying Vote Secret to production with HTTPS, containerized MongoDB, and proper security configurations.

## 📋 Prerequisites

- **Server Requirements:**
  - Ubuntu 20.04+ or similar Linux distribution
  - 4GB RAM minimum (8GB recommended)
  - 50GB disk space minimum
  - Docker and Docker Compose installed
  - Domain pointing to your server IP (vote.super-csn.ca)

- **SSL Certificate:**
  - Valid SSL certificate for vote.super-csn.ca
  - Can be obtained via Let's Encrypt or your certificate provider

## 🛠️ Production Setup

### 1. Environment Configuration

Copy and configure the production environment file:

```bash
cp .env.prod .env.prod.local
```

Edit `.env.prod.local` and set secure passwords:

```env
# Generate secure passwords using: openssl rand -base64 32
MONGO_ROOT_PASSWORD=your_very_secure_root_password
MONGO_USER_PASSWORD=your_very_secure_user_password
SESSION_SECRET=your_secure_session_secret
JWT_SECRET=your_secure_jwt_secret
```

### 2. SSL Certificate Setup

Place your SSL certificates in the `nginx/ssl/` directory:

```bash
mkdir -p nginx/ssl
# Copy your certificate files
cp your-certificate.crt nginx/ssl/vote.super-csn.ca.crt
cp your-private-key.key nginx/ssl/vote.super-csn.ca.key

# Set proper permissions
chmod 600 nginx/ssl/*
```

#### Using Let's Encrypt:

```bash
# Install certbot
sudo apt install certbot

# Get certificate (ensure domain points to your server)
sudo certbot certonly --standalone -d vote.super-csn.ca

# Copy certificates
sudo cp /etc/letsencrypt/live/vote.super-csn.ca/fullchain.pem nginx/ssl/vote.super-csn.ca.crt
sudo cp /etc/letsencrypt/live/vote.super-csn.ca/privkey.pem nginx/ssl/vote.super-csn.ca.key
sudo chown $USER:$USER nginx/ssl/*
chmod 600 nginx/ssl/*
```

### 3. Production Deployment

Run the setup script:

```bash
chmod +x scripts/setup-prod.sh
./scripts/setup-prod.sh
```

Deploy to production:

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## 🏗️ Architecture Overview

```
[Internet] → [Nginx (HTTPS)] → [Frontend (React) / Backend (FastAPI)] → [MongoDB]
```

### Services:
- **Nginx**: Reverse proxy with SSL termination, rate limiting, and security headers
- **Frontend**: React application (port 3000, internal)
- **Backend**: FastAPI application (port 8001, internal)
- **MongoDB**: Database with authentication (port 27017, internal)

## 🔧 Management Commands

### Start/Stop Services
```bash
# Start all services
docker-compose -f docker-compose.prod.yml up -d

# Stop all services
docker-compose -f docker-compose.prod.yml down

# Restart specific service
docker-compose -f docker-compose.prod.yml restart backend
```

### Monitoring
```bash
# View all logs
docker-compose -f docker-compose.prod.yml logs -f

# View specific service logs
docker-compose -f docker-compose.prod.yml logs -f backend

# Check service status
docker-compose -f docker-compose.prod.yml ps
```

### Database Management
```bash
# Create backup
./scripts/backup.sh

# Access MongoDB shell
docker exec -it vote-secret-mongodb mongosh -u voteadmin -p

# View database
docker exec -it vote-secret-mongodb mongosh vote_secret_db -u voteuser -p
```

## 🛡️ Security Features

### Network Security
- Internal network isolation
- Rate limiting (10 req/s for API, 30 req/s general)
- CORS configured for specific domain only

### Headers
- HSTS (HTTP Strict Transport Security)
- X-Frame-Options: DENY
- X-Content-Type-Options: nosniff
- X-XSS-Protection
- Content Security Policy

### Database Security
- MongoDB authentication enabled
- Dedicated application user with limited permissions
- Connection over internal network only

### SSL/TLS
- TLS 1.2 and 1.3 only
- Strong cipher suites
- Perfect Forward Secrecy

## 📊 Monitoring & Health Checks

### Health Endpoints
- **Frontend**: `https://vote.super-csn.ca/health`
- **Backend**: `https://vote.super-csn.ca/api/health`
- **Overall**: `https://vote.super-csn.ca/health`

### Service Health Checks
All services include Docker health checks:
- MongoDB: Connection test
- Backend: API endpoint test
- Frontend: HTTP response test
- Nginx: Configuration validation

## 🔄 Updates & Maintenance

### Application Updates
```bash
# Pull latest code
git pull origin main

# Rebuild and redeploy
docker-compose -f docker-compose.prod.yml build --no-cache
docker-compose -f docker-compose.prod.yml up -d
```

### SSL Certificate Renewal (Let's Encrypt)
```bash
# Renew certificate
sudo certbot renew

# Copy renewed certificates
sudo cp /etc/letsencrypt/live/vote.super-csn.ca/fullchain.pem nginx/ssl/vote.super-csn.ca.crt
sudo cp /etc/letsencrypt/live/vote.super-csn.ca/privkey.pem nginx/ssl/vote.super-csn.ca.key
sudo chown $USER:$USER nginx/ssl/*

# Restart nginx
docker-compose -f docker-compose.prod.yml restart nginx
```

### Database Backups
Automated backup script creates daily backups and keeps 7 days of history:
```bash
./scripts/backup.sh
```

## 🐛 Troubleshooting

### Common Issues

1. **SSL Certificate Issues**
   ```bash
   # Check certificate validity
   openssl x509 -in nginx/ssl/vote.super-csn.ca.crt -text -noout
   
   # Test SSL configuration
   docker exec vote-secret-nginx nginx -t
   ```

2. **Database Connection Issues**
   ```bash
   # Check MongoDB logs
   docker-compose -f docker-compose.prod.yml logs mongodb
   
   # Test connection
   docker exec vote-secret-mongodb mongosh --eval "db.adminCommand('ping')"
   ```

3. **Application Not Accessible**
   ```bash
   # Check all services
   docker-compose -f docker-compose.prod.yml ps
   
   # Check nginx logs
   docker-compose -f docker-compose.prod.yml logs nginx
   ```

### Performance Tuning

For high-traffic deployments:

1. **Increase worker processes** in nginx.conf:
   ```nginx
   worker_processes auto;
   ```

2. **Scale backend** in docker-compose.prod.yml:
   ```yaml
   backend:
     deploy:
       replicas: 3
   ```

3. **Add Redis** for session management (if needed)

## 📞 Support

- **Documentation**: This README and inline comments
- **Logs**: All services provide detailed logging
- **Health Checks**: Built-in monitoring endpoints

## 🔐 Security Checklist

- [ ] Strong passwords configured in .env.prod
- [ ] SSL certificates properly installed
- [ ] Firewall configured (only ports 80, 443 open)
- [ ] Regular backups scheduled
- [ ] SSL certificate auto-renewal setup
- [ ] Log monitoring in place
- [ ] Security headers verified
- [ ] Database access restricted to application only

---

## 🎯 Quick Start Summary

```bash
# 1. Configure environment
cp .env.prod .env.prod.local
# Edit .env.prod.local with secure passwords

# 2. Setup SSL certificates
mkdir -p nginx/ssl
# Place your SSL certificates in nginx/ssl/

# 3. Deploy
./scripts/setup-prod.sh
./scripts/deploy.sh

# 4. Verify
curl -I https://vote.super-csn.ca
```

Your Vote Secret application will be available at: **https://vote.super-csn.ca**