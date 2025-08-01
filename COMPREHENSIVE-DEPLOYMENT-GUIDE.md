# Vote Secret - Complete Deployment Guide 🚀

![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)
![FastAPI](https://img.shields.io/badge/FastAPI-0.116.1-00a373.svg)
![React](https://img.shields.io/badge/React-19.1.1-61dafb.svg)
![MongoDB](https://img.shields.io/badge/MongoDB-8.0-4ea94b.svg)
![Production Ready](https://img.shields.io/badge/Production-Ready-green.svg)

## 📋 Table of Contents
- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Development Setup](#development-setup)
- [Production Deployment](#production-deployment)
- [Docker Deployment](#docker-deployment)
- [Security & SSL](#security--ssl)
- [Monitoring & Maintenance](#monitoring--maintenance)
- [Troubleshooting](#troubleshooting)
- [API Documentation](#api-documentation)

## 🎯 Overview

Vote Secret is a modern, secure anonymous voting application designed for assemblies and meetings. It features:

### ✨ Key Features
- **🔒 Complete Anonymity**: No vote-user linkage stored
- **⚡ Real-time Updates**: Live participant and voting updates
- **📱 Responsive Design**: Modern UI with glassmorphism effects
- **📄 PDF Reports**: Automatic report generation with data deletion
- **🛡️ Security First**: Input validation, CORS, rate limiting
- **🐳 Production Ready**: Docker containers with SSL support

### 🏗️ Architecture
```
Frontend (React 19) ↔ Backend (FastAPI) ↔ Database (MongoDB 8.0)
        ↓                    ↓                    ↓
   Modern UI/UX         REST API           Document Store
   Real-time UI      PDF Generation      Anonymous Data
```

## 📋 Prerequisites

### System Requirements
- **Operating System**: Ubuntu 20.04+ / CentOS 8+ / macOS 11+ / Windows 10+
- **Memory**: 4GB RAM minimum (8GB recommended for production)
- **Storage**: 20GB free space minimum (50GB recommended for production)
- **Network**: Internet access for package downloads

### Required Software Versions

#### Python 3.11+
```bash
# Ubuntu/Debian
sudo apt update
sudo apt install python3.11 python3.11-venv python3.11-dev python3-pip

# macOS (with Homebrew)
brew install python@3.11

# Windows (download from python.org)
# https://www.python.org/downloads/

# Verify installation
python3.11 --version
```

#### Node.js 20+
```bash
# Ubuntu/Debian
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# macOS (with Homebrew)
brew install node@20

# Windows (download from nodejs.org)
# https://nodejs.org/en/download/

# Verify installation
node --version  # Should be >= 20.0.0
npm --version   # Should be >= 10.0.0
```

#### MongoDB 8.0+
```bash
# Ubuntu/Debian
wget -qO - https://www.mongodb.org/static/pgp/server-8.0.asc | sudo apt-key add -
echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/8.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list
sudo apt-get update
sudo apt-get install -y mongodb-org

# Start MongoDB
sudo systemctl start mongod
sudo systemctl enable mongod

# macOS (with Homebrew)
brew tap mongodb/brew
brew install mongodb-community@8.0
brew services start mongodb/brew/mongodb-community@8.0

# Verify installation
mongod --version
```

#### Yarn Package Manager
```bash
# Install globally
npm install -g yarn

# Verify installation
yarn --version
```

#### Docker & Docker Compose (for production)
```bash
# Ubuntu/Debian
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# macOS
brew install docker docker-compose

# Verify installation
docker --version
docker-compose --version
```

## 🛠️ Development Setup

### 1. Clone the Repository
```bash
# Clone the project
git clone <your-repository-url>
cd supervote

# Verify project structure
ls -la
```

### 2. Backend Setup (FastAPI + Python)

#### Create Python Virtual Environment
```bash
cd backend

# Create virtual environment
python3.11 -m venv venv

# Activate virtual environment
source venv/bin/activate  # Linux/macOS
# OR
venv\Scripts\activate     # Windows

# Upgrade pip
pip install --upgrade pip setuptools wheel
```

#### Install Python Dependencies
```bash
# Install all dependencies
pip install -r requirements.txt

# Verify critical packages
pip list | grep -E "(fastapi|uvicorn|pymongo|motor|reportlab)"
```

#### Configure Backend Environment
```bash
# The .env file should contain:
cat .env
```
```env
MONGO_URL=mongodb://localhost:27017
DB_NAME=vote_secret_db
```

### 3. Frontend Setup (React + Node.js)

#### Install Node.js Dependencies
```bash
cd ../frontend

# Install dependencies with Yarn
yarn install

# Verify installation
yarn list --pattern="react|axios|tailwindcss"
```

#### Configure Frontend Environment
```bash
# Check .env file
cat .env
```
```env
REACT_APP_BACKEND_URL=http://localhost:8001/api
WDS_SOCKET_PORT=443
```

### 4. Database Setup

#### Start MongoDB
```bash
# Linux
sudo systemctl start mongod
sudo systemctl status mongod

# macOS
brew services start mongodb/brew/mongodb-community@8.0

# Verify MongoDB is running
mongo --eval "db.adminCommand('ismaster')"
```

### 5. Start Development Servers

#### Terminal 1: Backend Server
```bash
cd backend
source venv/bin/activate
uvicorn server:app --host 0.0.0.0 --port 8001 --reload
```

#### Terminal 2: Frontend Development Server
```bash
cd frontend
yarn start
```

### 6. Verify Development Setup
- **Frontend**: http://localhost:3000
- **Backend API**: http://localhost:8001/docs (FastAPI auto-generated docs)
- **Health Check**: http://localhost:8001/api/health

## 🚀 Production Deployment

### Option 1: Manual Production Setup

#### 1. Server Preparation
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y nginx certbot python3-certbot-nginx

# Create application user
sudo useradd -m -s /bin/bash ubuntu
sudo usermod -aG sudo ubuntu
```

#### 2. Application Deployment
```bash
# Clone to production location
sudo mkdir -p /opt/supervote
sudo chown ubuntu:ubuntu /opt/supervote
cd /opt/supervote

# Clone repository
git clone <your-repository-url> .

# Set proper permissions
sudo chown -R ubuntu:ubuntu /opt/supervote
```

#### 3. Backend Production Setup
```bash
cd /opt/supervote/backend

# Create production virtual environment
python3.11 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Create production environment file
cp .env .env.prod
```

Edit `.env.prod`:
```env
MONGO_URL=mongodb://localhost:27017
DB_NAME=vote_secret_production
```

#### 4. Frontend Production Build
```bash
cd /opt/supervote/frontend

# Install dependencies
yarn install

# Create production environment
cp .env .env.production
```

Edit `.env.production`:
```env
REACT_APP_BACKEND_URL=https://your-domain.com/api
```

```bash
# Build for production
yarn build

# The build files will be in the 'build' directory
```

#### 5. Nginx Configuration
```bash
sudo nano /etc/nginx/sites-available/supervote
```

```nginx
server {
    listen 80;
    server_name your-domain.com;

    # Redirect HTTP to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name your-domain.com;

    # SSL Configuration (will be added by certbot)
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload";

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=general:10m rate=30r/s;

    # Frontend (React build)
    location / {
        root /opt/supervote/frontend/build;
        try_files $uri $uri/ /index.html;
        
        # Cache static assets
        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
    }

    # Backend API
    location /api/ {
        limit_req zone=api burst=20 nodelay;
        proxy_pass http://127.0.0.1:8001/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Health check
    location /health {
        return 200 "OK";
        add_header Content-Type text/plain;
    }
}
```

Enable the site:
```bash
sudo ln -s /etc/nginx/sites-available/supervote /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

#### 6. SSL Certificate Setup
```bash
# Get Let's Encrypt certificate
sudo certbot --nginx -d your-domain.com

# Set up auto-renewal
sudo crontab -e
# Add: 0 12 * * * /usr/bin/certbot renew --quiet
```

#### 7. Process Management with Systemd
Create backend service:
```bash
sudo nano /etc/systemd/system/supervote-backend.service
```

```ini
[Unit]
Description=Vote Secret Backend
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/supervote/backend
Environment=PATH=/opt/supervote/backend/venv/bin
ExecStart=/opt/supervote/backend/venv/bin/uvicorn server:app --host 127.0.0.1 --port 8001
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

Enable and start:
```bash
sudo systemctl daemon-reload
sudo systemctl enable supervote-backend
sudo systemctl start supervote-backend
sudo systemctl status supervote-backend
```

### Option 2: Docker Production Deployment (Recommended)

#### 1. Prepare Production Environment
```bash
# Copy production environment template
cp .env.prod .env.prod.local

# Generate secure passwords
openssl rand -base64 32  # Use for MONGO_ROOT_PASSWORD
openssl rand -base64 32  # Use for MONGO_USER_PASSWORD
openssl rand -base64 32  # Use for SESSION_SECRET
openssl rand -base64 32  # Use for JWT_SECRET
```

Edit `.env.prod.local`:
```env
# Domain Configuration
DOMAIN=your-domain.com

# MongoDB Configuration
MONGO_ROOT_PASSWORD=your_secure_root_password_here
MONGO_USER_PASSWORD=your_secure_user_password_here

# Application Security
SESSION_SECRET=your_secure_session_secret_here
JWT_SECRET=your_secure_jwt_secret_here

# Environment
NODE_ENV=production
PYTHON_ENV=production
```

#### 2. SSL Certificate Setup

**Option A: Manual SSL Certificates**
```bash
# Create SSL directory
mkdir -p nginx/ssl

# Copy your certificates
cp your-certificate.crt nginx/ssl/your-domain.com.crt
cp your-private-key.key nginx/ssl/your-domain.com.key

# Set permissions
chmod 600 nginx/ssl/*
```

**Option B: Let's Encrypt (Automated)**
```bash
# Make scripts executable
chmod +x scripts/*.sh

# Run automated SSL setup
./scripts/setup-ssl.sh
```

#### 3. Deploy with Docker
```bash
# Make deployment scripts executable
chmod +x scripts/deploy.sh scripts/deploy-secure.sh

# Option A: Standard deployment
./scripts/deploy.sh

# Option B: Secure deployment with SSL automation
./scripts/deploy-secure.sh
```

#### 4. Verify Deployment
```bash
# Check all services
docker-compose -f docker-compose.prod.yml ps

# View logs
docker-compose -f docker-compose.prod.yml logs -f

# Test application
curl -I https://your-domain.com
curl https://your-domain.com/api/health
```

## 🐳 Docker Deployment

### Development with Docker
```bash
# Build and start development containers
docker-compose up --build

# Run in background
docker-compose up -d

# View logs
docker-compose logs -f

# Stop containers
docker-compose down
```

### Production with Docker
```bash
# Build production images
docker-compose -f docker-compose.prod.yml build

# Start production services
docker-compose -f docker-compose.prod.yml up -d

# Monitor services
docker-compose -f docker-compose.prod.yml ps
docker-compose -f docker-compose.prod.yml logs -f

# Update application
git pull
docker-compose -f docker-compose.prod.yml build --no-cache
docker-compose -f docker-compose.prod.yml up -d
```

### Docker Commands Reference
```bash
# Container management
docker ps                                      # List running containers
docker logs supervote-backend               # View specific container logs
docker exec -it supervote-backend bash      # Access container shell

# Image management
docker images                                  # List images
docker system prune -a                        # Clean up unused images/containers

# Database access
docker exec -it supervote-mongodb mongosh vote_secret_db -u voteuser -p
```

## 🔐 Security & SSL

### SSL Certificate Management

#### Let's Encrypt Automation
```bash
# Initial certificate generation
sudo certbot certonly --standalone -d your-domain.com

# For Docker deployment
./scripts/setup-ssl.sh

# Manual renewal
sudo certbot renew

# Auto-renewal setup
echo "0 12 * * * /usr/bin/certbot renew --quiet" | sudo crontab -
```

#### SSL Certificate Verification
```bash
# Check certificate validity
openssl x509 -in nginx/ssl/your-domain.com.crt -text -noout

# Test SSL configuration
curl -I https://your-domain.com
openssl s_client -connect your-domain.com:443 -servername your-domain.com
```

### Security Best Practices Implemented

#### Application Security
- ✅ **Input Validation**: Pydantic models for all API inputs
- ✅ **CORS Configuration**: Restricted to specific domains
- ✅ **Rate Limiting**: API and general request limits
- ✅ **Anonymous Voting**: No user-vote linkage stored
- ✅ **Data Deletion**: Automatic cleanup after PDF generation

#### Infrastructure Security
- ✅ **HTTPS Only**: HTTP to HTTPS redirection
- ✅ **Security Headers**: HSTS, XSS Protection, Frame Options
- ✅ **Network Isolation**: Internal Docker networks
- ✅ **Database Authentication**: MongoDB user/password auth
- ✅ **Strong Passwords**: Generated secure credentials

## 📊 Monitoring & Maintenance

### Health Checks
```bash
# Application health
curl https://your-domain.com/health
curl https://your-domain.com/api/health

# Service status (Docker)
docker-compose -f docker-compose.prod.yml ps

# Service status (Systemd)
sudo systemctl status supervote-backend
sudo systemctl status nginx
sudo systemctl status mongod
```

### Log Management
```bash
# Docker logs
docker-compose -f docker-compose.prod.yml logs backend --tail=100
docker-compose -f docker-compose.prod.yml logs frontend --tail=100
docker-compose -f docker-compose.prod.yml logs nginx --tail=100

# System logs
sudo journalctl -u supervote-backend -f
sudo journalctl -u nginx -f
tail -f /var/log/nginx/access.log
tail -f /var/log/nginx/error.log
```

### Backup & Recovery
```bash
# Database backup (Docker)
docker exec supervote-mongodb mongodump --uri="mongodb://voteuser:password@localhost:27017/vote_secret_db" --out=/backup

# Database backup (Manual)
mongodump --uri="mongodb://localhost:27017/vote_secret_db" --out=./backup-$(date +%Y%m%d)

# Backup script
./scripts/backup.sh

# Restore from backup
mongorestore --uri="mongodb://localhost:27017/vote_secret_db" ./backup-20241201/vote_secret_db
```

### Performance Monitoring
```bash
# Docker container stats
docker stats

# System resource usage
htop
df -h
free -m

# MongoDB performance
mongo --eval "db.stats()"
```

### Maintenance Tasks

#### Regular Updates
```bash
# Update application
git pull origin main
docker-compose -f docker-compose.prod.yml build --no-cache
docker-compose -f docker-compose.prod.yml up -d

# Update system packages
sudo apt update && sudo apt upgrade -y

# Update Node.js packages
cd frontend && yarn upgrade

# Update Python packages
cd backend && pip list --outdated
```

#### Certificate Renewal
```bash
# Check certificate expiry
certbot certificates

# Renew certificates
certbot renew

# Restart nginx after renewal
sudo systemctl reload nginx
```

## 🐛 Troubleshooting

### Common Issues and Solutions

#### 1. Application Won't Start

**Symptoms**: Application not accessible, connection refused
```bash
# Check service status
docker-compose -f docker-compose.prod.yml ps
sudo systemctl status supervote-backend

# Check logs for errors
docker-compose -f docker-compose.prod.yml logs backend
sudo journalctl -u supervote-backend --no-pager
```

**Common causes**:
- Port already in use
- Environment variables misconfigured
- Database connection failed
- SSL certificate issues

**Solutions**:
```bash
# Check port usage
sudo netstat -tlnp | grep :8001

# Restart services
docker-compose -f docker-compose.prod.yml restart
sudo systemctl restart supervote-backend

# Check environment variables
cat .env.prod.local
```

#### 2. Database Connection Issues

**Symptoms**: Database connection errors, data not persisting
```bash
# Test MongoDB connection
docker exec -it supervote-mongodb mongosh --eval "db.adminCommand('ping')"
mongo --eval "db.adminCommand('ping')"

# Check MongoDB status
docker-compose -f docker-compose.prod.yml logs mongodb
sudo systemctl status mongod
```

**Solutions**:
```bash
# Restart MongoDB
docker-compose -f docker-compose.prod.yml restart mongodb
sudo systemctl restart mongod

# Check MongoDB configuration
cat /etc/mongod.conf

# Verify network connectivity
telnet localhost 27017
```

#### 3. SSL Certificate Problems

**Symptoms**: SSL warnings, certificate errors
```bash
# Check certificate validity
openssl x509 -in nginx/ssl/your-domain.com.crt -text -noout | grep -A2 "Validity"

# Test SSL configuration
curl -I https://your-domain.com
```

**Solutions**:
```bash
# Renew Let's Encrypt certificate
sudo certbot renew --force-renewal

# Restart nginx
sudo systemctl reload nginx
docker-compose -f docker-compose.prod.yml restart nginx

# Check nginx configuration
nginx -t
docker exec supervote-nginx nginx -t
```

#### 4. Performance Issues

**Symptoms**: Slow response times, high resource usage
```bash
# Check system resources
htop
df -h
free -m

# Check application performance
curl -w "@curl-format.txt" -o /dev/null -s https://your-domain.com/api/health
```

**Solutions**:
```bash
# Optimize Docker resources
docker system prune -a

# Scale backend services
# Edit docker-compose.prod.yml to add replicas

# Monitor database performance
mongo --eval "db.runCommand({serverStatus: 1}).connections"
```

#### 5. Frontend Not Loading

**Symptoms**: Blank page, 404 errors for static files
```bash
# Check nginx configuration
nginx -t
curl -I https://your-domain.com

# Check build files
ls -la frontend/build/
```

**Solutions**:
```bash
# Rebuild frontend
cd frontend
yarn build

# Restart nginx
sudo systemctl reload nginx

# Check nginx logs
tail -f /var/log/nginx/error.log
```

### Debug Commands

#### System Information
```bash
# Check versions
python3 --version
node --version
mongo --version
docker --version

# Check running processes
ps aux | grep -E "(uvicorn|nginx|mongod)"

# Check network connections
sudo netstat -tlnp | grep -E ":(80|443|8001|27017|3000)"

# Check disk space
df -h
du -sh /opt/supervote

# Check memory usage
free -h
```

#### Application Debug
```bash
# Test API endpoints
curl -X GET https://your-domain.com/api/health
curl -X POST https://your-domain.com/api/meeting -H "Content-Type: application/json" -d '{"name":"Test"}'

# Check database records
mongo vote_secret_db --eval "db.meetings.find().pretty()"

# Monitor logs in real-time
tail -f /var/log/nginx/access.log | grep -v "GET /health"
```

### Recovery Procedures

#### Complete System Recovery
```bash
# 1. Stop all services
docker-compose -f docker-compose.prod.yml down
sudo systemctl stop supervote-backend nginx

# 2. Backup current state
tar -czf supervote-backup-$(date +%Y%m%d).tar.gz /opt/supervote

# 3. Fresh deployment
git pull origin main
./scripts/deploy-secure.sh

# 4. Restore data if needed
mongorestore --uri="mongodb://localhost:27017/vote_secret_db" ./backup/
```

## 📚 API Documentation

### Core Endpoints

#### Health Check
```http
GET /api/health
```

Response:
```json
{
  "status": "healthy",
  "database": "connected",
  "timestamp": "2024-01-01T12:00:00Z"
}
```

#### Meeting Management
```http
POST /api/meeting
Content-Type: application/json

{
  "name": "Assembly Meeting 2024"
}
```

Response:
```json
{
  "id": "meeting-uuid",
  "name": "Assembly Meeting 2024",
  "code": "ABC123XY",
  "created_at": "2024-01-01T12:00:00Z"
}
```

#### Join Meeting
```http
POST /api/meeting/{code}/join
Content-Type: application/json

{
  "name": "John Doe"
}
```

#### Create Poll
```http
POST /api/meeting/{meeting_id}/poll
Content-Type: application/json

{
  "question": "Approve budget proposal?",
  "options": ["Yes", "No", "Abstain"],
  "timer_minutes": 5
}
```

#### Submit Vote
```http
POST /api/poll/{poll_id}/vote
Content-Type: application/json

{
  "option": "Yes"
}
```

#### Generate Report
```http
POST /api/meeting/{meeting_id}/report
```

Returns PDF file with meeting results and automatically deletes meeting data.

### Frontend Routes

- `/` - Home page with join meeting form
- `/organizer` - Organizer login/dashboard
- `/meeting/{code}` - Participant meeting interface
- `/organizer/meeting/{id}` - Organizer meeting management

## 🎯 Quick Reference

### Development Commands
```bash
# Start development
cd backend && source venv/bin/activate && uvicorn server:app --reload
cd frontend && yarn start

# Install new dependencies
pip install package && pip freeze > requirements.txt
yarn add package
```

### Production Commands
```bash
# Deploy updates
git pull && ./scripts/deploy.sh

# View logs
docker-compose -f docker-compose.prod.yml logs -f

# Restart services
docker-compose -f docker-compose.prod.yml restart

# SSL renewal
sudo certbot renew && sudo systemctl reload nginx
```

### Emergency Commands
```bash
# Stop everything
docker-compose -f docker-compose.prod.yml down
sudo systemctl stop supervote-backend nginx

# Quick restart
docker-compose -f docker-compose.prod.yml restart
sudo systemctl restart supervote-backend nginx

# Check status
docker-compose -f docker-compose.prod.yml ps
curl -I https://your-domain.com/health
```

---

## 🎉 Success!

Your Vote Secret application should now be running successfully! 

- **Development**: http://localhost:3000
- **Production**: https://your-domain.com

For additional support or questions, refer to the detailed sections above or check the application logs.

**Vote Secret v2.0** - Secure, Anonymous, Modern Voting for Assemblies 🗳️
