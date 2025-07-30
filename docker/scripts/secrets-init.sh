#!/bin/bash

# SUPERvote Secrets Management - Industry Grade
# Secure secrets generation and Docker Swarm integration

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Configuration
SECRETS_DIR="${SECRETS_DIR:-./secrets}"
BACKUP_DIR="${BACKUP_DIR:-./secrets/backup}"

# Ensure directories exist
mkdir -p "$SECRETS_DIR" "$BACKUP_DIR"
chmod 700 "$SECRETS_DIR" "$BACKUP_DIR"

# Generate secure random values
generate_secret() {
    local length=${1:-32}
    openssl rand -base64 $((length * 3 / 4)) | tr -d "=+/" | head -c "$length"
}

generate_password() {
    local length=${1:-24}
    openssl rand -base64 $((length * 3 / 4)) | tr -d "=+/" | head -c "$length"
}

generate_jwt_secret() {
    openssl rand -base64 64 | tr -d "=+/" | head -c 64
}

# Secrets to generate
declare -A SECRETS=(
    ["mongo_root_user"]="admin"
    ["mongo_root_password"]="$(generate_password 32)"
    ["app_secret_key"]="$(generate_secret 64)"
    ["jwt_secret"]="$(generate_jwt_secret)"
    ["grafana_admin_password"]="$(generate_password 24)"
    ["grafana_secret_key"]="$(generate_secret 32)"
    ["backup_encryption_key"]="$(generate_secret 32)"
    ["s3_access_key"]="${S3_ACCESS_KEY:-}"
    ["s3_secret_key"]="${S3_SECRET_KEY:-}"
)

# Function to create Docker secret
create_docker_secret() {
    local secret_name="$1"
    local secret_value="$2"
    local version="${3:-v1}"
    
    local full_name="supervote_${secret_name}_${version}"
    
    # Check if secret already exists
    if docker secret inspect "$full_name" >/dev/null 2>&1; then
        log_warning "Secret $full_name already exists, skipping..."
        return 0
    fi
    
    # Create secret
    echo "$secret_value" | docker secret create "$full_name" -
    
    if [ $? -eq 0 ]; then
        log_success "Created Docker secret: $full_name"
    else
        log_error "Failed to create Docker secret: $full_name"
        return 1
    fi
}

# Function to save secrets to file (for backup)
save_secret_to_file() {
    local secret_name="$1"
    local secret_value="$2"
    
    local file_path="$SECRETS_DIR/${secret_name}.txt"
    
    # Save to file with restricted permissions
    echo "$secret_value" > "$file_path"
    chmod 600 "$file_path"
    
    log_info "Saved secret to file: $file_path"
}

# Function to backup existing secrets
backup_secrets() {
    if [ -d "$SECRETS_DIR" ] && [ "$(ls -A $SECRETS_DIR)" ]; then
        local backup_file="$BACKUP_DIR/secrets_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
        
        tar -czf "$backup_file" -C "$SECRETS_DIR" .
        chmod 600 "$backup_file"
        
        log_success "Backed up existing secrets to: $backup_file"
    fi
}

# Function to initialize Docker Swarm if not already done
init_docker_swarm() {
    if ! docker info --format '{{.Swarm.LocalNodeState}}' | grep -q active; then
        log_info "Initializing Docker Swarm..."
        docker swarm init --advertise-addr 127.0.0.1 2>/dev/null || true
        log_success "Docker Swarm initialized"
    else
        log_info "Docker Swarm already active"
    fi
}

# Function to create environment files
create_env_files() {
    local env_file=".env.production"
    
    cat > "$env_file" << EOF
# SUPERvote Production Environment Configuration
# Generated on $(date)

# Application Configuration  
VERSION=2.0.0
ENVIRONMENT=production
DEBUG=false

# Database Configuration
DB_NAME=poll_app_prod
DATA_PATH=./data

# Performance Configuration
BACKEND_WORKERS=4
MAX_CONNECTIONS=1000
RATE_LIMIT_REQUESTS=1000
RATE_LIMIT_WINDOW=60
CACHE_TTL=300
CACHE_MAX_SIZE=1000

# Security Configuration
CORS_ORIGINS=https://vote.super-csn.ca
TRUSTED_HOSTS=vote.super-csn.ca,localhost

# Frontend Configuration
FRONTEND_BACKEND_URL=https://vote.super-csn.ca

# Backup Configuration
BACKUP_SCHEDULE=0 2 * * *
BACKUP_RETENTION_DAYS=30
BACKUP_COMPRESSION=gzip
BACKUP_ENCRYPTION=true

# Monitoring Configuration
LOG_LEVEL=INFO

# Build Information
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GIT_COMMIT=\${GIT_COMMIT:-unknown}
EOF

    chmod 600 "$env_file"
    log_success "Created environment file: $env_file"
}

# Function to validate secrets
validate_secrets() {
    local errors=0
    
    for secret_name in "${!SECRETS[@]}"; do
        local secret_value="${SECRETS[$secret_name]}"
        
        if [ -z "$secret_value" ]; then
            log_error "Secret $secret_name is empty"
            ((errors++))
            continue
        fi
        
        # Validate secret strength
        case "$secret_name" in
            *password*)
                if [ ${#secret_value} -lt 16 ]; then
                    log_error "Password $secret_name is too short (${#secret_value} chars, minimum 16)"
                    ((errors++))
                fi
                ;;
            *secret*|*key*)
                if [ ${#secret_value} -lt 32 ]; then
                    log_error "Secret $secret_name is too short (${#secret_value} chars, minimum 32)"
                    ((errors++))
                fi
                ;;
        esac
    done
    
    if [ $errors -eq 0 ]; then
        log_success "All secrets validated successfully"
        return 0
    else
        log_error "Found $errors validation errors"
        return 1
    fi
}

# Main execution
main() {
    log_info "Starting SUPERvote secrets initialization..."
    
    # Check if running with proper permissions
    if [ "$EUID" -eq 0 ]; then
        log_warning "Running as root is not recommended for security reasons"
    fi
    
    # Backup existing secrets
    backup_secrets
    
    # Initialize Docker Swarm
    init_docker_swarm
    
    # Validate generated secrets
    if ! validate_secrets; then
        log_error "Secret validation failed"
        exit 1
    fi
    
    # Create Docker secrets
    log_info "Creating Docker secrets..."
    for secret_name in "${!SECRETS[@]}"; do
        local secret_value="${SECRETS[$secret_name]}"
        
        # Skip empty secrets (like optional S3 keys)
        if [ -z "$secret_value" ]; then
            log_warning "Skipping empty secret: $secret_name"
            continue
        fi
        
        create_docker_secret "$secret_name" "$secret_value"
        save_secret_to_file "$secret_name" "$secret_value"
    done
    
    # Create environment files
    create_env_files
    
    # Set up data directories
    log_info "Creating data directories..."
    mkdir -p data/{mongodb_primary,redis,prometheus,grafana}
    chmod -R 755 data/
    
    # Create logs directories  
    log_info "Creating log directories..."
    mkdir -p logs/{nginx,backend,frontend}
    chmod -R 755 logs/
    
    # Security summary
    log_info "Security Summary:"
    echo "  - Generated $(( ${#SECRETS[@]} - 2 )) secure secrets"
    echo "  - Secrets stored in Docker Swarm with encryption at rest"
    echo "  - File backups created with 600 permissions"
    echo "  - Environment configuration created"
    echo "  - Data and log directories prepared"
    
    log_success "SUPERvote secrets initialization completed!"
    
    echo
    log_info "Next steps:"
    echo "  1. Review generated secrets in: $SECRETS_DIR"
    echo "  2. Configure external services (S3, monitoring, etc.)"
    echo "  3. Deploy with: docker stack deploy -c compose.production.yml supervote"
    echo "  4. Or use: docker compose -f compose.production.yml up -d"
    
    echo
    log_warning "IMPORTANT: Store the secrets backup safely and delete local files after deployment!"
}

# Execute main function
main "$@"