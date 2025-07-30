#!/bin/bash

# SUPERvote Docker Setup Script for Ubuntu 22.04
# This script sets up SUPERvote using Docker containers

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should not be run as root. Please run as a regular user with sudo privileges."
        exit 1
    fi
}

# Update system
update_system() {
    log_info "Updating system packages..."
    sudo apt update && sudo apt upgrade -y
    log_success "System updated successfully"
}

# Install essential packages
install_essential_packages() {
    log_info "Installing essential packages..."
    sudo apt install -y curl wget git ufw ca-certificates
    log_success "Essential packages installed"
}

# Install Docker
install_docker() {
    log_info "Installing Docker..."
    
    # Remove any existing Docker packages
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do 
        sudo apt-get remove -y $pkg 2>/dev/null || true
    done
    
    # Add Docker's official GPG key
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    
    # Add the repository to Apt sources
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    
    # Install Docker Engine
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Add current user to docker group
    sudo usermod -aG docker $USER
    
    # Start and enable Docker
    sudo systemctl start docker
    sudo systemctl enable docker
    
    # Verify Docker installation
    if sudo docker --version && sudo docker compose version; then
        log_success "Docker installed successfully"
        sudo docker --version
        sudo docker compose version
    else
        log_error "Docker installation failed"
        exit 1
    fi
}

# Configure firewall
configure_firewall() {
    log_info "Configuring UFW firewall..."
    
    sudo ufw allow 22/tcp   # SSH
    sudo ufw allow 80/tcp   # HTTP
    sudo ufw allow 443/tcp  # HTTPS
    sudo ufw --force enable
    
    log_success "Firewall configured"
}

# Clone SUPERvote repository
clone_repository() {
    log_info "Cloning SUPERvote repository..."
    
    if [ -d "SUPERvote" ]; then
        log_warning "SUPERvote directory already exists. Removing..."
        rm -rf SUPERvote
    fi
    
    git clone https://github.com/KiiTuNp/SUPERvote.git
    cd SUPERvote
    
    log_success "Repository cloned successfully"
}

# Setup Docker environment
setup_docker_environment() {
    log_info "Setting up Docker environment..."
    
    # Create production directories
    mkdir -p ssl logs
    chmod 755 ssl logs
    
    # Create Docker Compose file
    cat > docker-compose.prod.yml << 'EOF'
version: '3.8'

services:
  mongodb:
    image: mongo:8.0.12
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
      - CORS_ORIGINS=https://vote.super-csn.ca
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

    # Create backend Dockerfile
    cat > backend/Dockerfile.prod << 'EOF'
FROM python:3.11.13-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Upgrade pip to latest version
RUN pip install --upgrade pip

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

    # Create frontend Dockerfile
    cat > frontend/Dockerfile.prod << 'EOF'
# Build stage
FROM node:20.19.4-alpine as build

WORKDIR /app

# Update npm to correct version
RUN npm install -g npm@10.8.2

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

    # Create nginx configuration
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

    # HTTP server
    server {
        listen 80;
        server_name vote.super-csn.ca;
        
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
}
EOF

    log_success "Docker environment configured"
}

# Create Docker management scripts
create_docker_scripts() {
    log_info "Creating Docker management scripts..."
    
    # Create start script
    cat > docker-start.sh << 'EOF'
#!/bin/bash

echo "🐳 Starting SUPERvote with Docker..."

# Build and start all services
docker compose -f docker-compose.prod.yml up -d --build

echo "✅ SUPERvote started with Docker!"
echo "📱 Frontend: http://localhost"
echo "🔧 Backend API: http://localhost/api"
echo ""
echo "Useful commands:"
echo "- Status: docker compose -f docker-compose.prod.yml ps"
echo "- Logs: docker compose -f docker-compose.prod.yml logs -f"
echo "- Stop: ./docker-stop.sh"
EOF

    # Create stop script
    cat > docker-stop.sh << 'EOF'
#!/bin/bash

echo "🛑 Stopping SUPERvote Docker containers..."

docker compose -f docker-compose.prod.yml down

echo "✅ SUPERvote stopped"
EOF

    # Create logs script
    cat > docker-logs.sh << 'EOF'
#!/bin/bash

echo "📋 SUPERvote Docker Logs..."
docker compose -f docker-compose.prod.yml logs -f
EOF

    # Make scripts executable
    chmod +x docker-start.sh docker-stop.sh docker-logs.sh
    
    log_success "Docker management scripts created"
}

# Final verification
verify_installation() {
    log_info "Verifying Docker installation..."
    
    echo ""
    echo "=== System Information ==="
    echo "OS: $(lsb_release -d | cut -f2)"
    echo "Docker: $(sudo docker --version | cut -d' ' -f3 | tr -d ',')"
    echo "Docker Compose: $(sudo docker compose version --short)"
    echo "Git: $(git --version | cut -d' ' -f3)"
    
    echo ""
    echo "=== Service Status ==="
    if sudo systemctl is-active --quiet docker; then
        echo "Docker: ✅ Running"
    else
        echo "Docker: ❌ Not running"
    fi
    
    log_success "Docker installation verification completed"
}

# Main execution
main() {
    echo "=== SUPERvote Docker Setup Script ==="
    echo "This script will install and configure:"
    echo "- Docker Engine with Docker Compose"
    echo "- SUPERvote application (containerized)"
    echo "- Nginx reverse proxy"
    echo "- MongoDB database"
    echo ""
    
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Setup cancelled by user"
        exit 0
    fi
    
    log_info "Starting SUPERvote Docker setup..."
    
    check_root
    update_system
    install_essential_packages
    install_docker
    configure_firewall
    clone_repository
    setup_docker_environment
    create_docker_scripts
    verify_installation
    
    echo ""
    echo "=== Docker Setup Complete! ==="
    log_success "SUPERvote Docker environment has been successfully set up!"
    echo ""
    echo "Next steps:"
    echo "1. Run './docker-start.sh' to start the application with Docker"
    echo "2. Open http://localhost in your browser"
    echo "3. For SSL setup, check the README.md file"
    echo ""
    echo "Docker commands:"
    echo "- Start: ./docker-start.sh"
    echo "- Stop: ./docker-stop.sh"
    echo "- Logs: ./docker-logs.sh"
    echo "- Status: docker compose -f docker-compose.prod.yml ps"
    echo ""
    log_warning "Note: You may need to log out and back in for Docker group membership to take effect"
}

# Run main function
main "$@"