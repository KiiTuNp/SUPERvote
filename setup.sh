#!/bin/bash

# SUPERvote Complete Setup Script for Ubuntu 22.04
# This script installs and configures everything needed for the SUPERvote application

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
    sudo apt install -y curl wget git nginx ufw python3.11 python3.11-pip python3.11-venv software-properties-common ca-certificates gnupg lsb-release
    log_success "Essential packages installed"
}

# Install MongoDB 8.0
install_mongodb() {
    log_info "Installing MongoDB 8.0..."
    
    # Import MongoDB public GPG key
    curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | sudo gpg --dearmor -o /usr/share/keyrings/mongodb-server-8.0.gpg
    
    # Add MongoDB repository
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/8.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list
    
    # Update package list and install MongoDB
    sudo apt-get update && sudo apt-get install -y mongodb-org
    
    # Start and enable MongoDB
    sudo systemctl start mongod
    sudo systemctl enable mongod
    
    # Verify MongoDB installation
    if sudo systemctl is-active --quiet mongod; then
        log_success "MongoDB 8.0 installed and running"
        mongod --version | head -1
    else
        log_error "MongoDB installation failed"
        exit 1
    fi
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
# Install Node.js via nvm
install_nodejs() {
    log_info "Installing Node.js 20.19.4 via nvm..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
    
    # Source nvm
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
    
    # Install Node.js 20
    nvm install 20
    nvm use 20
    nvm alias default 20
    
    # Verify installation
    if command -v node &> /dev/null; then
        log_success "Node.js installed successfully"
        echo "Node.js version: $(node -v)"
        echo "npm version: $(npm -v)"
    else
        log_error "Node.js installation failed"
        exit 1
    fi
}

# Setup Python environment
setup_python() {
    log_info "Setting up Python environment..."
    
    # Upgrade pip
    python3.11 -m pip install --upgrade pip
    
    # Verify Python installation
    python3.11 --version
    pip3.11 --version
    
    log_success "Python environment ready"
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

# Setup backend
setup_backend() {
    log_info "Setting up backend..."
    
    cd backend
    
    # Create virtual environment
    python3.11 -m venv venv
    source venv/bin/activate
    
    # Upgrade pip in virtual environment
    pip install --upgrade pip
    
    # Install dependencies
    pip install -r requirements.txt
    
    # Create .env file
    if [ ! -f .env ]; then
        cat > .env << EOF
MONGO_URL=mongodb://localhost:27017/poll_app
CORS_ORIGINS=https://vote.super-csn.ca,http://localhost:3000
EOF
        log_success "Backend .env file created"
    fi
    
    deactivate
    cd ..
    
    log_success "Backend setup completed"
}

# Setup frontend
setup_frontend() {
    log_info "Setting up frontend..."
    
    cd frontend
    
    # Source nvm for this shell
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    
    # Install dependencies
    npm install
    
    # Create .env file
    if [ ! -f .env ]; then
        cat > .env << EOF
REACT_APP_BACKEND_URL=http://localhost:8001
EOF
        log_success "Frontend .env file created"
    fi
    
    cd ..
    
    log_success "Frontend setup completed"
}

# Install PM2 for process management
install_pm2() {
    log_info "Installing PM2 for process management..."
    
    # Source nvm for this shell
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    
    npm install -g pm2
    
    # Create PM2 ecosystem file
    cat > ecosystem.config.js << 'EOF'
module.exports = {
  apps: [
    {
      name: 'supervote-backend',
      cwd: './backend',
      script: 'server.py',
      interpreter: './venv/bin/python',
      instances: 1,
      exec_mode: 'fork',
      env: {
        NODE_ENV: 'production'
      },
      error_file: './logs/backend-error.log',
      out_file: './logs/backend-out.log',
      log_file: './logs/backend.log',
      max_memory_restart: '500M',
      restart_delay: 1000
    },
    {
      name: 'supervote-frontend',
      cwd: './frontend',
      script: 'npm',
      args: 'start',
      instances: 1,
      exec_mode: 'fork',
      env: {
        NODE_ENV: 'development'
      },
      error_file: './logs/frontend-error.log',
      out_file: './logs/frontend-out.log',
      log_file: './logs/frontend.log',
      max_memory_restart: '500M'
    }
  ]
};
EOF
    
    # Create logs directory
    mkdir -p logs
    
    log_success "PM2 installed and configured"
}

# Create startup script
create_startup_script() {
    log_info "Creating startup script..."
    
    cat > start.sh << 'EOF'
#!/bin/bash

# SUPERvote Startup Script

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Starting SUPERvote Application...${NC}"

# Source nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Check if MongoDB is running
if ! sudo systemctl is-active --quiet mongod; then
    echo -e "${YELLOW}Starting MongoDB...${NC}"
    sudo systemctl start mongod
fi

# Start applications with PM2
pm2 start ecosystem.config.js

echo -e "${GREEN}SUPERvote started successfully!${NC}"
echo -e "${GREEN}Frontend: http://localhost:3000${NC}"
echo -e "${GREEN}Backend API: http://localhost:8001${NC}"
echo ""
echo "Use 'pm2 status' to check application status"
echo "Use 'pm2 logs' to view logs"
echo "Use 'pm2 stop all' to stop applications"
EOF
    
    chmod +x start.sh
    
    log_success "Startup script created"
}

# Create stop script
create_stop_script() {
    log_info "Creating stop script..."
    
    cat > stop.sh << 'EOF'
#!/bin/bash

# SUPERvote Stop Script

# Colors
RED='\033[0;31m'
NC='\033[0m'

echo -e "${RED}Stopping SUPERvote Application...${NC}"

# Source nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Stop applications
pm2 stop all

echo -e "${RED}SUPERvote stopped${NC}"
EOF
    
    chmod +x stop.sh
    
    log_success "Stop script created"
}

# Final verification
verify_installation() {
    log_info "Verifying installation..."
    
    echo ""
    echo "=== System Information ==="
    echo "OS: $(lsb_release -d | cut -f2)"
    echo "Python: $(python3.11 --version)"
    echo "pip: $(pip3.11 --version | cut -d' ' -f2)"
    
    # Source nvm for verification
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    
    echo "Node.js: $(node -v)"
    echo "npm: $(npm -v)"
    echo "Docker: $(sudo docker --version | cut -d' ' -f3 | tr -d ',')"
    echo "Docker Compose: $(sudo docker compose version --short)"
    echo "MongoDB: $(mongod --version | head -1 | cut -d' ' -f3)"
    echo "Git: $(git --version | cut -d' ' -f3)"
    
    echo ""
    echo "=== Service Status ==="
    if sudo systemctl is-active --quiet mongod; then
        echo "MongoDB: ✅ Running"
    else
        echo "MongoDB: ❌ Not running"
    fi
    
    if sudo systemctl is-active --quiet docker; then
        echo "Docker: ✅ Running"
    else
        echo "Docker: ❌ Not running"
    fi
    
    log_success "Installation verification completed"
}

# Main execution
main() {
    echo "=== SUPERvote Complete Setup Script ==="
    echo "This script will install and configure:"
    echo "- MongoDB 8.0.12"
    echo "- Docker Engine with Docker Compose"
    echo "- Node.js 20.19.4 (via nvm)"
    echo "- Python 3.11"
    echo "- SUPERvote application"
    echo "- PM2 process manager"
    echo ""
    
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Setup cancelled by user"
        exit 0
    fi
    
    log_info "Starting SUPERvote setup..."
    
    check_root
    update_system
    install_essential_packages
    install_docker
    install_mongodb
    install_nodejs
    setup_python
    configure_firewall
    clone_repository
    setup_backend
    setup_frontend
    install_pm2
    create_startup_script
    create_stop_script
    verify_installation
    
    echo ""
    echo "=== Setup Complete! ==="
    log_success "SUPERvote has been successfully installed!"
    echo ""
    echo "Next steps:"
    echo "1. Run './start.sh' to start the application"
    echo "2. Open http://localhost:3000 in your browser"
    echo "3. For production deployment, check the README.md file"
    echo ""
    echo "Useful commands:"
    echo "- Start: ./start.sh"
    echo "- Stop: ./stop.sh"
    echo "- Status: pm2 status"
    echo "- Logs: pm2 logs"
    echo ""
}

# Run main function
main "$@"