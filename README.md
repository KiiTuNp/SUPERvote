# SUPERvote - Real-time Anonymous Polling System

A professional-grade, real-time polling application designed for secure meeting management with anonymous voting, participant approval, and comprehensive reporting.

**Live Demo:** https://vote.super-csn.ca

## 🎯 Features

### Core Functionality
- **Anonymous Polling** - Secure voting with no way to trace participants to their choices
- **Real-time Updates** - Live vote counts and participant synchronization
- **Participant Approval** - Organizer controls who can participate in polls
- **Custom Room IDs** - Professional meeting identification (3-10 alphanumeric characters)
- **Poll Timers** - Automatic poll closure with visual countdown
- **Multiple Active Polls** - Run several polls simultaneously
- **Multi-format Export** - PDF, JSON, and text report generation
- **Data Security** - Complete data deletion after meeting export

### Advanced Features
- **Timer-based Polls** - Automatic stop functionality with visual countdown
- **Participant Management** - Join and participate during active poll sessions  
- **Results Privacy** - Participants cannot see results before voting (prevents bias)
- **WebSocket Communication** - Real-time synchronization across all clients
- **Network Resilience** - Automatic reconnection and retry mechanisms
- **Production-ready** - Comprehensive error handling and user feedback

## 🏗️ Architecture

**Frontend:** React with Tailwind CSS  
**Backend:** FastAPI with WebSocket support  
**Database:** MongoDB  
**Real-time:** WebSocket connections for live updates  
**Export:** PDF generation with reportlab, JSON and text fallbacks

## 📋 Prerequisites

### For Local Development
- **Node.js** 20+ and npm/yarn
- **Python** 3.8+
- **MongoDB** 8.0+
- **Git**

### For Ubuntu 22.04 VPS Production Deployment
- **Ubuntu 22.04 LTS** VPS with root access (minimum 2GB RAM, 20GB storage)
- **Domain name** pointing to your VPS IP (vote.super-csn.ca in this example)
- **SSH access** to your VPS
- **Firewall** configured to allow ports 22, 80, 443

## 🚀 Quick Start (Local Development)

### 1. Clone Repository
```bash
git clone https://github.com/KiiTuNp/SUPERvote.git
cd SUPERvote
```

### 2. Backend Setup
```bash
# Navigate to backend directory
cd backend

# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Set environment variables
cp .env.example .env
# Edit .env with your settings
```

### 3. Frontend Setup
```bash
# Navigate to frontend directory
cd ../frontend

# Install dependencies
npm install
# or
yarn install

# Set environment variables
cp .env.example .env
# Edit .env with your settings
```

### 4. Database Setup
```bash
# Start MongoDB (Ubuntu/Debian)
sudo systemctl start mongod
sudo systemctl enable mongod

# Or using Docker
docker run -d -p 27017:27017 --name mongodb mongo:latest
```

### 5. Run Application
```bash
# Terminal 1: Backend
cd backend
source venv/bin/activate
python server.py

# Terminal 2: Frontend  
cd frontend
npm start
# or
yarn start
```

Application will be available at:
- **Frontend:** http://localhost:3000
- **Backend API:** http://localhost:8001

## 🌐 Production Deployment on Ubuntu 22.04 VPS

### Prerequisites Check
Before starting, ensure you have:
- Ubuntu 22.04 LTS VPS with root access
- Domain `vote.super-csn.ca` pointing to your VPS IP address
- SSH access to your server

### Option 1: Docker Deployment (Recommended for Production)

#### Step 1: Initial VPS Setup
```bash
# Connect to your VPS
ssh root@your-vps-ip

# Update the system
sudo apt update && sudo apt upgrade -y

# Install essential packages
sudo apt install -y curl wget git ufw

# Configure firewall
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable

# Create a non-root user (recommended)
adduser deployer
usermod -aG sudo deployer
su - deployer
```

#### Step 2: Install Docker and Docker Compose
```bash
# Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Start Docker service
sudo systemctl enable docker
sudo systemctl start docker

# Log out and back in to apply Docker group membership
exit
ssh deployer@your-vps-ip
```

#### Step 3: Clone and Setup Application
```bash
# Create application directory
sudo mkdir -p /opt/supervote
sudo chown $USER:$USER /opt/supervote
cd /opt/supervote

# Clone the repository
git clone https://github.com/KiiTuNp/SUPERvote.git .

# Verify the clone
ls -la
```

#### Step 4: Create Production Configuration Files

**Create Docker Compose file (`docker-compose.prod.yml`):**
```bash
cat > docker-compose.prod.yml << 'EOF'
version: '3.8'

services:
  mongodb:
    image: mongo:7.0
    container_name: supervote-mongo
    restart: unless-stopped
    environment:
      - MONGO_INITDB_DATABASE=poll_app
    volumes:
      - mongodb_data:/data/db
    networks:
      - app-network
    healthcheck:
      test: echo 'db.runCommand("ping").ok' | mongosh --quiet
      interval: 30s
      timeout: 10s
      retries: 3

  backend:
    build:
      context: ./backend
      dockerfile: Dockerfile.prod
    container_name: supervote-backend
    restart: unless-stopped
    environment:
      - MONGO_URL=mongodb://mongodb:27017/poll_app
      - CORS_ORIGINS=https://vote.super-csn.ca,https://www.vote.super-csn.ca
    depends_on:
      mongodb:
        condition: service_healthy
    networks:
      - app-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8001/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile.prod
      args:
        - REACT_APP_BACKEND_URL=https://vote.super-csn.ca
    container_name: supervote-frontend
    restart: unless-stopped
    depends_on:
      backend:
        condition: service_healthy
    networks:
      - app-network

  nginx:
    image: nginx:alpine
    container_name: supervote-nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./ssl:/etc/nginx/ssl:ro
      - ./logs:/var/log/nginx
    depends_on:
      - frontend
      - backend
    networks:
      - app-network

volumes:
  mongodb_data:

networks:
  app-network:
    driver: bridge
EOF
```

**Create Backend Dockerfile (`backend/Dockerfile.prod`):**
```bash
cat > backend/Dockerfile.prod << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Create non-root user
RUN useradd -m -u 1000 app && chown -R app:app /app
USER app

# Expose port
EXPOSE 8001

# Health check
HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8001/api/health || exit 1

# Start application
CMD ["python", "server.py"]
EOF
```

**Create Frontend Dockerfile (`frontend/Dockerfile.prod`):**
```bash
cat > frontend/Dockerfile.prod << 'EOF'
# Build stage
FROM node:20.19.4-alpine as build

WORKDIR /app

# Update npm to latest
RUN npm install -g npm@11.5.1

# Copy package files
COPY package*.json ./
COPY yarn.lock ./
RUN npm ci --only=production

# Copy source code and build
COPY . .
ARG REACT_APP_BACKEND_URL
ENV REACT_APP_BACKEND_URL=$REACT_APP_BACKEND_URL
RUN npm run build

# Production stage
FROM nginx:alpine

# Copy built files
COPY --from=build /app/build /usr/share/nginx/html

# Create nginx config for SPA
RUN echo 'server { \
    listen 80; \
    location / { \
        root /usr/share/nginx/html; \
        index index.html index.htm; \
        try_files $uri $uri/ /index.html; \
    } \
}' > /etc/nginx/conf.d/default.conf

# Expose port
EXPOSE 80

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:80/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
EOF
```

**Create Nginx Configuration (`nginx.conf`):**
```bash
cat > nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    # Logging
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log warn;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=100r/m;
    limit_req_zone $binary_remote_addr zone=general:10m rate=200r/m;

    upstream backend {
        server backend:8001;
    }

    upstream frontend {
        server frontend:80;
    }

    # HTTP server (redirects to HTTPS in production)
    server {
        listen 80;
        server_name vote.super-csn.ca www.vote.super-csn.ca;
        
        # Redirect to HTTPS (uncomment after SSL setup)
        # return 301 https://$server_name$request_uri;
        
        # Temporary HTTP access for initial setup
        # Security headers
        add_header X-Frame-Options DENY;
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";
        add_header Referrer-Policy strict-origin-when-cross-origin;
        
        # API routes
        location /api/ {
            limit_req zone=api burst=20 nodelay;
            proxy_pass http://backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # WebSocket support
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_read_timeout 86400;
        }
        
        # Frontend routes
        location / {
            limit_req zone=general burst=50 nodelay;
            proxy_pass http://frontend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }

    # HTTPS server (uncomment after SSL certificate is obtained)
    # server {
    #     listen 443 ssl http2;
    #     server_name vote.super-csn.ca www.vote.super-csn.ca;
    #     
    #     ssl_certificate /etc/nginx/ssl/fullchain.pem;
    #     ssl_certificate_key /etc/nginx/ssl/privkey.pem;
    #     
    #     # Modern SSL configuration
    #     ssl_protocols TLSv1.2 TLSv1.3;
    #     ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    #     ssl_prefer_server_ciphers off;
    #     ssl_session_cache shared:SSL:10m;
    #     ssl_session_timeout 1d;
    #     
    #     # Security headers
    #     add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    #     add_header X-Frame-Options DENY;
    #     add_header X-Content-Type-Options nosniff;
    #     add_header X-XSS-Protection "1; mode=block";
    #     add_header Referrer-Policy strict-origin-when-cross-origin;
    #     
    #     # Same location blocks as HTTP
    #     location /api/ {
    #         limit_req zone=api burst=20 nodelay;
    #         proxy_pass http://backend;
    #         proxy_set_header Host $host;
    #         proxy_set_header X-Real-IP $remote_addr;
    #         proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    #         proxy_set_header X-Forwarded-Proto $scheme;
    #         
    #         proxy_http_version 1.1;
    #         proxy_set_header Upgrade $http_upgrade;
    #         proxy_set_header Connection "upgrade";
    #         proxy_read_timeout 86400;
    #     }
    #     
    #     location / {
    #         limit_req zone=general burst=50 nodelay;
    #         proxy_pass http://frontend;
    #         proxy_set_header Host $host;
    #         proxy_set_header X-Real-IP $remote_addr;
    #         proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    #         proxy_set_header X-Forwarded-Proto $scheme;
    #     }
    # }
}
EOF
```

#### Step 5: Create Required Directories
```bash
# Create SSL and logs directories
mkdir -p ssl logs

# Set proper permissions
chmod 755 ssl logs
```

#### Step 6: Build and Deploy Application
```bash
# Build and start all services
docker-compose -f docker-compose.prod.yml up -d --build

# Check if all services are running
docker-compose -f docker-compose.prod.yml ps

# View logs to ensure everything is working
docker-compose -f docker-compose.prod.yml logs -f
```

#### Step 7: Verify Deployment
```bash
# Check if the application is accessible
curl -I http://vote.super-csn.ca

# Test the API health endpoint
curl http://vote.super-csn.ca/api/health

# If everything is working, you should see HTTP 200 responses
```

#### Step 8: SSL Certificate Setup (Production Required)
```bash
# Install Certbot
sudo apt update
sudo apt install -y certbot

# Stop nginx temporarily to obtain certificate
docker-compose -f docker-compose.prod.yml stop nginx

# Obtain SSL certificate for your domain
sudo certbot certonly --standalone \
  -d vote.super-csn.ca \
  -d www.vote.super-csn.ca \
  --email your-email@example.com \
  --agree-tos \
  --no-eff-email

# Copy certificates to project directory
sudo cp /etc/letsencrypt/live/vote.super-csn.ca/fullchain.pem ssl/
sudo cp /etc/letsencrypt/live/vote.super-csn.ca/privkey.pem ssl/
sudo chown $USER:$USER ssl/*.pem

# Update nginx.conf to enable HTTPS
# Uncomment the HTTPS server block and comment the HTTP redirect
sed -i 's/# return 301 https/return 301 https/' nginx.conf
sed -i '/# server {/,/# }/s/# //' nginx.conf

# Restart nginx with SSL configuration
docker-compose -f docker-compose.prod.yml up -d nginx

# Verify HTTPS is working
curl -I https://vote.super-csn.ca
```

#### Step 9: Setup Auto-renewal for SSL Certificate
```bash
# Create renewal script
sudo tee /etc/cron.d/certbot-renew << 'EOF'
0 12 * * * root certbot renew --quiet --post-hook "cd /opt/supervote && docker-compose -f docker-compose.prod.yml restart nginx"
EOF

# Test the renewal process
sudo certbot renew --dry-run
```

#### Step 10: Production Optimization
```bash
# Create systemd service for auto-start on boot
sudo tee /etc/systemd/system/supervote.service << 'EOF'
[Unit]
Description=SUPERvote Application
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/supervote
ExecStart=/usr/local/bin/docker-compose -f docker-compose.prod.yml up -d
ExecStop=/usr/local/bin/docker-compose -f docker-compose.prod.yml down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

# Enable the service
sudo systemctl enable supervote.service
sudo systemctl start supervote.service
```

### Option 2: Manual Ubuntu 22.04 VPS Deployment

#### Step 1: System Preparation
```bash
# Connect to your VPS
ssh root@your-vps-ip

# Update system
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y curl wget git nginx mongodb python3 python3-pip python3-venv nodejs npm ufw
```

#### Step 2: Install Node.js 20
```bash
# Install Node.js 20.19.4 (required for the frontend)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Verify installation
node --version  # Should be v20.19.4
npm --version   # Should be 11.5.1 or higher
```

#### Step 3: Setup MongoDB
```bash
# Start and enable MongoDB
sudo systemctl start mongodb
sudo systemctl enable mongodb

# Verify MongoDB is running
sudo systemctl status mongodb
```

#### Step 4: Clone and Setup Application
```bash
# Create application directory
sudo mkdir -p /opt/supervote
sudo chown $USER:$USER /opt/supervote
cd /opt/supervote

# Clone the repository
git clone https://github.com/KiiTuNp/SUPERvote.git .
```

#### Step 5: Setup Backend
```bash
cd /opt/supervote/backend

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install Python dependencies
pip install -r requirements.txt

# Create production environment file
cat > .env << EOF
MONGO_URL=mongodb://localhost:27017/poll_app
CORS_ORIGINS=https://vote.super-csn.ca,https://www.vote.super-csn.ca
EOF
```

#### Step 6: Setup Frontend
```bash
cd /opt/supervote/frontend

# Install dependencies
npm install

# Create production environment file
cat > .env << EOF
REACT_APP_BACKEND_URL=https://vote.super-csn.ca
EOF

# Build the frontend
npm run build
```

#### Step 7: Install PM2 for Process Management
```bash
# Install PM2 globally
sudo npm install -g pm2

# Create PM2 ecosystem file
cd /opt/supervote
cat > ecosystem.config.js << 'EOF'
module.exports = {
  apps: [
    {
      name: 'supervote-backend',
      cwd: '/opt/supervote/backend',
      script: 'server.py',
      interpreter: '/opt/supervote/backend/venv/bin/python',
      instances: 2,
      exec_mode: 'cluster',
      env: {
        NODE_ENV: 'production'
      },
      error_file: '/var/log/pm2/supervote-backend-error.log',
      out_file: '/var/log/pm2/supervote-backend-out.log',
      log_file: '/var/log/pm2/supervote-backend.log',
      max_memory_restart: '500M',
      restart_delay: 1000
    }
  ]
};
EOF
```

#### Step 8: Configure Nginx
```bash
# Create Nginx configuration
sudo tee /etc/nginx/sites-available/supervote << 'EOF'
server {
    listen 80;
    server_name vote.super-csn.ca www.vote.super-csn.ca;
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Referrer-Policy strict-origin-when-cross-origin;
    
    # Serve frontend
    location / {
        root /opt/supervote/frontend/build;
        index index.html;
        try_files $uri $uri/ /index.html;
        
        # Cache static assets
        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
    }
    
    # API proxy
    location /api/ {
        proxy_pass http://localhost:8001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
    }
}
EOF

# Enable the site
sudo ln -s /etc/nginx/sites-available/supervote /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# Test nginx configuration
sudo nginx -t

# Reload nginx
sudo systemctl reload nginx
```

#### Step 9: Start Services
```bash
# Create PM2 log directory
sudo mkdir -p /var/log/pm2
sudo chown $USER:$USER /var/log/pm2

# Start the application with PM2
pm2 start ecosystem.config.js

# Save PM2 configuration
pm2 save

# Setup PM2 to start on boot
pm2 startup
# Follow the instructions that PM2 provides (run the command it shows)
```

#### Step 10: Configure Firewall
```bash
# Configure UFW firewall
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable
```

#### Step 11: SSL Certificate Setup
```bash
# Install Certbot
sudo apt install -y certbot python3-certbot-nginx

# Obtain SSL certificate
sudo certbot --nginx -d vote.super-csn.ca -d www.vote.super-csn.ca --email your-email@example.com --agree-tos --no-eff-email

# Test auto-renewal
sudo certbot renew --dry-run
```

## 🔧 Production Configuration

### Environment Variables

#### Backend (`.env`)
```env
# Database
MONGO_URL=mongodb://localhost:27017/poll_app

# CORS (for production)
CORS_ORIGINS=https://vote.super-csn.ca,https://www.vote.super-csn.ca

# Optional: Custom port
PORT=8001
```

#### Frontend (`.env`)
```env
# Backend URL
REACT_APP_BACKEND_URL=https://vote.super-csn.ca

# Optional: Custom port for development
PORT=3000
```

## 🔍 Production Monitoring and Maintenance

### Health Checks
```bash
# Check application status
curl -I https://vote.super-csn.ca
curl https://vote.super-csn.ca/api/health

# For Docker deployment
docker-compose -f docker-compose.prod.yml ps
docker-compose -f docker-compose.prod.yml logs -f

# For manual deployment
pm2 status
pm2 logs supervote-backend
sudo systemctl status nginx
sudo systemctl status mongodb
```

### Log Management
```bash
# Docker logs
docker-compose -f docker-compose.prod.yml logs --tail=100 backend
docker-compose -f docker-compose.prod.yml logs --tail=100 frontend

# Manual deployment logs
pm2 logs supervote-backend --lines 100
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

### Updates and Maintenance
```bash
# Update application (both Docker and manual deployments)
cd /opt/supervote
git pull origin main

# For Docker deployment
docker-compose -f docker-compose.prod.yml down
docker-compose -f docker-compose.prod.yml up -d --build

# For manual deployment
cd backend && source venv/bin/activate && pip install -r requirements.txt
cd ../frontend && npm install && npm run build
pm2 restart supervote-backend
sudo systemctl reload nginx
```

## 📱 Usage Guide

### For Organizers
1. **Create Meeting**
   - Visit https://vote.super-csn.ca
   - Enter your name and optional custom room ID (3-10 characters)
   - Share room ID with participants

2. **Manage Participants**
   - View participants as they join
   - Approve or deny access individually
   - Monitor approval status in real-time

3. **Create Polls**
   - Add questions with multiple options
   - Set optional auto-stop timers (1-60 minutes)
   - Start/stop polls as needed

4. **Monitor Results**
   - View live vote counts
   - See real-time participation
   - Track multiple active polls

5. **Export Data**
   - Generate comprehensive reports
   - Multiple format download (PDF, JSON, Text)
   - Automatic data cleanup after export

### For Participants
1. **Join Meeting**
   - Visit https://vote.super-csn.ca
   - Enter your name and room ID
   - Wait for organizer approval

2. **Vote on Polls**
   - See active polls after approval
   - Vote without seeing biased results
   - View results after voting

3. **Real-time Updates**
   - Automatic poll notifications
   - Live result updates
   - Timer countdowns

## 🛠️ API Documentation

### Base URL
- **Production:** https://vote.super-csn.ca/api
- **Local Development:** http://localhost:8001/api

### Authentication
No authentication required - uses anonymous session tokens

### Core Endpoints

#### Rooms
- `POST /api/rooms/create` - Create new room
- `POST /api/rooms/join` - Join existing room
- `GET /api/rooms/{room_id}/status` - Get room status
- `GET /api/rooms/{room_id}/participants` - List participants
- `GET /api/rooms/{room_id}/polls` - List all polls
- `GET /api/rooms/{room_id}/report` - Generate PDF report
- `DELETE /api/rooms/{room_id}/cleanup` - Delete room data

#### Polls
- `POST /api/polls/create` - Create new poll
- `POST /api/polls/{poll_id}/start` - Start poll
- `POST /api/polls/{poll_id}/stop` - Stop poll
- `POST /api/polls/{poll_id}/vote` - Submit vote

#### Participants
- `POST /api/participants/{participant_id}/approve` - Approve participant
- `POST /api/participants/{participant_id}/deny` - Deny participant

#### WebSocket
- `WS /api/ws/{room_id}` - Real-time updates

## 🔍 Troubleshooting

### Common Ubuntu 22.04 Issues

#### Domain Not Resolving
```bash
# Check DNS resolution
nslookup vote.super-csn.ca
dig vote.super-csn.ca

# Verify firewall rules
sudo ufw status
```

#### MongoDB Connection Issues
```bash
# Check MongoDB status
sudo systemctl status mongodb

# Restart MongoDB
sudo systemctl restart mongodb

# Check logs
sudo journalctl -u mongodb
```

#### Nginx Configuration Issues
```bash
# Test nginx configuration
sudo nginx -t

# Check nginx status
sudo systemctl status nginx

# View nginx error logs
sudo tail -f /var/log/nginx/error.log
```

#### Docker Issues
```bash
# Check Docker service
sudo systemctl status docker

# Check disk space
df -h

# Restart Docker
sudo systemctl restart docker
```

#### SSL Certificate Issues
```bash
# Check certificate status
sudo certbot certificates

# Renew certificate manually
sudo certbot renew

# Check nginx SSL configuration
sudo nginx -t
```

## 🔒 Security Considerations

### Production Security Checklist
- ✅ HTTPS enabled with valid SSL certificate
- ✅ Firewall configured (UFW)
- ✅ Rate limiting implemented
- ✅ Security headers configured
- ✅ Regular security updates
- ✅ Non-root user for application
- ✅ MongoDB secured (no external access)
- ✅ Environment variables for secrets

### Data Privacy
- Anonymous voting system
- Automatic data cleanup after meetings
- No personal data persistence beyond meeting duration
- Secure session management with temporary tokens

## 📦 Maintenance Scripts

### Backup Script
```bash
#!/bin/bash
# Create backup script
cat > /opt/supervote/backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/opt/supervote/backups"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

# Backup MongoDB (if data needs to be preserved)
mongodump --db poll_app --out $BACKUP_DIR/mongo_$DATE

# Backup application files
tar -czf $BACKUP_DIR/app_$DATE.tar.gz /opt/supervote --exclude=/opt/supervote/backups

# Keep only last 7 days of backups
find $BACKUP_DIR -name "*.tar.gz" -mtime +7 -delete
find $BACKUP_DIR -name "mongo_*" -mtime +7 -exec rm -rf {} \;

echo "Backup completed: $DATE"
EOF

chmod +x /opt/supervote/backup.sh

# Add to crontab for daily backups
(crontab -l 2>/dev/null; echo "0 2 * * * /opt/supervote/backup.sh") | crontab -
```

### Update Script
```bash
#!/bin/bash
# Create update script
cat > /opt/supervote/update.sh << 'EOF'
#!/bin/bash
cd /opt/supervote

echo "Pulling latest changes..."
git pull origin main

if [ -f "docker-compose.prod.yml" ]; then
    echo "Updating Docker deployment..."
    docker-compose -f docker-compose.prod.yml down
    docker-compose -f docker-compose.prod.yml up -d --build
else
    echo "Updating manual deployment..."
    cd backend
    source venv/bin/activate
    pip install -r requirements.txt
    cd ../frontend
    npm install
    npm run build
    pm2 restart supervote-backend
    sudo systemctl reload nginx
fi

echo "Update completed!"
EOF

chmod +x /opt/supervote/update.sh
```

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🤝 Contributing

1. Fork the repository: https://github.com/KiiTuNp/SUPERvote
2. Create feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit changes (`git commit -m 'Add AmazingFeature'`)
4. Push to branch (`git push origin feature/AmazingFeature`)
5. Open Pull Request

## 📞 Support

For support and questions:
- Check troubleshooting section above
- Review API documentation
- Visit: https://vote.super-csn.ca
- Create GitHub issue: https://github.com/KiiTuNp/SUPERvote/issues

---

**SUPERvote** - Professional anonymous polling for secure meetings 🗳️  
**Live at:** https://vote.super-csn.ca
