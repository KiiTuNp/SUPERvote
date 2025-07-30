#!/bin/bash

# SUPERvote Production Deployment Script
# Déploie SUPERvote sur le serveur de production Ubuntu 22.04

set -e  # Arrêt en cas d'erreur

# Configuration
PRODUCTION_SERVER="ubuntu@46.226.104.149"
DOMAIN="vote.super-csn.ca"
EMAIL="simon@super-csn.ca"
APP_DIR="/opt/supervote"

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # Pas de couleur

# Fonctions de logging
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCÈS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[ATTENTION]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERREUR]${NC} $1"
}

# Vérifier la connexion SSH
check_ssh_connection() {
    log_info "Vérification de la connexion SSH vers ${PRODUCTION_SERVER}..."
    if ssh -o ConnectTimeout=10 -o BatchMode=yes ${PRODUCTION_SERVER} exit 2>/dev/null; then
        log_success "Connexion SSH établie avec succès"
    else
        log_error "Impossible de se connecter à ${PRODUCTION_SERVER}"
        log_error "Vérifiez que votre clé SSH est configurée correctement"
        exit 1
    fi
}

# Script de déploiement à exécuter sur le serveur
create_remote_deployment_script() {
    cat > remote-deploy.sh << 'REMOTE_SCRIPT'
#!/bin/bash

set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCÈS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[ATTENTION]${NC} $1"; }
log_error() { echo -e "${RED}[ERREUR]${NC} $1"; }

DOMAIN="vote.super-csn.ca"
EMAIL="simon@super-csn.ca"
APP_DIR="/opt/supervote"

log_info "=== Déploiement SUPERvote en Production ==="

# Mise à jour du système
log_info "Mise à jour du système..."
sudo apt update && sudo apt upgrade -y

# Installation des paquets essentiels
log_info "Installation des paquets essentiels..."
sudo apt install -y curl wget git ufw ca-certificates software-properties-common

# Installation Docker
log_info "Installation de Docker..."

# Suppression des anciens paquets Docker
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do 
    sudo apt-get remove -y $pkg 2>/dev/null || true
done

# Ajout de la clé GPG officielle Docker
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Ajout du repository aux sources Apt
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

# Installation Docker Engine
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Ajout de l'utilisateur au groupe docker
sudo usermod -aG docker $USER

# Démarrage et activation de Docker
sudo systemctl start docker
sudo systemctl enable docker

log_success "Docker installé avec succès"

# Configuration du firewall
log_info "Configuration du firewall UFW..."
sudo ufw allow 22/tcp   # SSH
sudo ufw allow 80/tcp   # HTTP
sudo ufw allow 443/tcp  # HTTPS
sudo ufw --force enable
log_success "Firewall configuré"

# Création du répertoire de l'application
log_info "Préparation du répertoire de l'application..."
sudo mkdir -p ${APP_DIR}
sudo chown $USER:$USER ${APP_DIR}
cd ${APP_DIR}

# Clonage du repository
log_info "Clonage du repository SUPERvote..."
if [ -d "SUPERvote" ]; then
    log_warning "Le répertoire SUPERvote existe déjà. Suppression..."
    rm -rf SUPERvote
fi

git clone https://github.com/KiiTuNp/SUPERvote.git
cd SUPERvote

# Création des répertoires nécessaires
mkdir -p ssl logs
chmod 755 ssl logs

# Création du fichier Docker Compose pour la production
log_info "Création de la configuration Docker Compose..."
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

# Création du Dockerfile backend
log_info "Création du Dockerfile backend..."
cat > backend/Dockerfile.prod << 'EOF'
FROM python:3.11.13-slim

WORKDIR /app

# Installation des dépendances système
RUN apt-get update && apt-get install -y \
    gcc \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Mise à jour de pip
RUN pip install --upgrade pip

# Installation des dépendances Python
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copie du code de l'application
COPY . .

# Création d'un utilisateur non-root
RUN useradd -m -u 1000 app && chown -R app:app /app
USER app

# Exposition du port
EXPOSE 8001

# Health check
HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8001/api/health || exit 1

# Démarrage de l'application
CMD ["python", "server.py"]
EOF

# Création du Dockerfile frontend
log_info "Création du Dockerfile frontend..."
cat > frontend/Dockerfile.prod << 'EOF'
# Stage de build
FROM node:20.19.4-alpine as build

WORKDIR /app

# Mise à jour npm
RUN npm install -g npm@10.8.2

# Copie des fichiers de package
COPY package*.json ./
COPY yarn.lock ./
RUN npm ci --only=production

# Copie du code source et build
COPY . .
ARG REACT_APP_BACKEND_URL
ENV REACT_APP_BACKEND_URL=$REACT_APP_BACKEND_URL
RUN npm run build

# Stage de production
FROM nginx:alpine

# Copie des fichiers buildés
COPY --from=build /app/build /usr/share/nginx/html

# Configuration nginx pour SPA
RUN echo 'server { \
    listen 80; \
    location / { \
        root /usr/share/nginx/html; \
        index index.html index.htm; \
        try_files $uri $uri/ /index.html; \
    } \
}' > /etc/nginx/conf.d/default.conf

# Exposition du port
EXPOSE 80

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:80/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
EOF

# Création de la configuration Nginx
log_info "Création de la configuration Nginx..."
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

    # Compression Gzip
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;

    # Limitation de débit
    limit_req_zone $binary_remote_addr zone=api:10m rate=100r/m;
    limit_req_zone $binary_remote_addr zone=general:10m rate=200r/m;

    upstream backend {
        server backend:8001;
    }

    upstream frontend {
        server frontend:80;
    }

    # Serveur HTTP (sera redirigé vers HTTPS après configuration SSL)
    server {
        listen 80;
        server_name vote.super-csn.ca;
        
        # En-têtes de sécurité
        add_header X-Frame-Options DENY;
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";
        add_header Referrer-Policy strict-origin-when-cross-origin;
        
        # Routes API
        location /api/ {
            limit_req zone=api burst=20 nodelay;
            proxy_pass http://backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # Support WebSocket
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_read_timeout 86400;
        }
        
        # Routes frontend
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

# Build et démarrage des conteneurs
log_info "Construction et démarrage des conteneurs Docker..."
sudo docker compose -f docker-compose.prod.yml up -d --build

# Attendre que les services soient prêts
log_info "Attente du démarrage des services..."
sleep 30

# Vérification que les services fonctionnent
if sudo docker compose -f docker-compose.prod.yml ps | grep -q "Up"; then
    log_success "Les conteneurs Docker sont démarrés"
else
    log_error "Échec du démarrage des conteneurs"
    sudo docker compose -f docker-compose.prod.yml logs
    exit 1
fi

# Installation de Certbot pour SSL
log_info "Installation de Certbot pour SSL..."
sudo apt update
sudo apt install -y certbot

# Arrêt temporaire de nginx pour obtenir le certificat
log_info "Obtention du certificat SSL..."
sudo docker compose -f docker-compose.prod.yml stop nginx

# Obtention du certificat SSL
sudo certbot certonly --standalone \
  -d vote.super-csn.ca \
  --email simon@super-csn.ca \
  --agree-tos \
  --no-eff-email

# Copie des certificats
sudo cp /etc/letsencrypt/live/vote.super-csn.ca/fullchain.pem ssl/
sudo cp /etc/letsencrypt/live/vote.super-csn.ca/privkey.pem ssl/
sudo chown $USER:$USER ssl/*.pem

# Mise à jour de la configuration nginx pour HTTPS
log_info "Configuration HTTPS..."
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

    # Compression Gzip
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;

    # Limitation de débit
    limit_req_zone $binary_remote_addr zone=api:10m rate=100r/m;
    limit_req_zone $binary_remote_addr zone=general:10m rate=200r/m;

    upstream backend {
        server backend:8001;
    }

    upstream frontend {
        server frontend:80;
    }

    # Redirection HTTP vers HTTPS
    server {
        listen 80;
        server_name vote.super-csn.ca;
        return 301 https://$server_name$request_uri;
    }

    # Serveur HTTPS
    server {
        listen 443 ssl http2;
        server_name vote.super-csn.ca;
        
        ssl_certificate /etc/nginx/ssl/fullchain.pem;
        ssl_certificate_key /etc/nginx/ssl/privkey.pem;
        
        # Configuration SSL moderne
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
        ssl_prefer_server_ciphers off;
        ssl_session_cache shared:SSL:10m;
        ssl_session_timeout 1d;
        
        # En-têtes de sécurité
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        add_header X-Frame-Options DENY;
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";
        add_header Referrer-Policy strict-origin-when-cross-origin;
        
        # Routes API
        location /api/ {
            limit_req zone=api burst=20 nodelay;
            proxy_pass http://backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # Support WebSocket
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_read_timeout 86400;
        }
        
        # Routes frontend
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

# Redémarrage de nginx avec la configuration HTTPS
log_info "Redémarrage de nginx avec HTTPS..."
sudo docker compose -f docker-compose.prod.yml up -d nginx

# Configuration du renouvellement automatique SSL
log_info "Configuration du renouvellement automatique SSL..."
sudo tee /etc/cron.d/certbot-renew << 'EOF'
0 12 * * * root certbot renew --quiet --post-hook "cd /opt/supervote/SUPERvote && docker compose -f docker-compose.prod.yml restart nginx"
EOF

# Test du renouvellement
sudo certbot renew --dry-run

# Création du service systemd pour auto-start
log_info "Configuration du service systemd..."
sudo tee /etc/systemd/system/supervote.service << 'EOF'
[Unit]
Description=SUPERvote Application
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/supervote/SUPERvote
ExecStart=/usr/bin/docker compose -f docker-compose.prod.yml up -d
ExecStop=/usr/bin/docker compose -f docker-compose.prod.yml down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable supervote.service
sudo systemctl start supervote.service

# Création des scripts de gestion
log_info "Création des scripts de gestion..."

cat > manage.sh << 'EOF'
#!/bin/bash

case "$1" in
  start)
    echo "🚀 Démarrage de SUPERvote..."
    docker compose -f docker-compose.prod.yml up -d
    ;;
  stop)
    echo "🛑 Arrêt de SUPERvote..."
    docker compose -f docker-compose.prod.yml down
    ;;
  restart)
    echo "🔄 Redémarrage de SUPERvote..."
    docker compose -f docker-compose.prod.yml restart
    ;;
  status)
    echo "📊 Statut de SUPERvote:"
    docker compose -f docker-compose.prod.yml ps
    ;;
  logs)
    echo "📋 Logs de SUPERvote:"
    docker compose -f docker-compose.prod.yml logs -f
    ;;
  update)
    echo "🔄 Mise à jour de SUPERvote..."
    git pull origin main
    docker compose -f docker-compose.prod.yml up -d --build
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|status|logs|update}"
    exit 1
    ;;
esac
EOF

chmod +x manage.sh

# Vérification finale
log_info "Vérification finale..."
sleep 10

if curl -I https://vote.super-csn.ca >/dev/null 2>&1; then
    log_success "✅ SUPERvote est accessible sur https://vote.super-csn.ca"
else
    log_warning "⚠️  Le site pourrait ne pas être encore accessible. Vérifiez les DNS."
fi

echo ""
echo "=== DÉPLOIEMENT TERMINÉ ==="
log_success "SUPERvote a été déployé avec succès en production!"
echo ""
echo "🌐 URL: https://vote.super-csn.ca"
echo "📊 Statut: ./manage.sh status"
echo "📋 Logs: ./manage.sh logs"
echo "🔄 Redémarrer: ./manage.sh restart"
echo "🔄 Mettre à jour: ./manage.sh update"
echo ""
echo "📁 Répertoire: ${APP_DIR}/SUPERvote"
echo "🔧 Configuration: docker-compose.prod.yml"
echo ""
REMOTE_SCRIPT
}

# Déployer sur le serveur de production
deploy_to_production() {
    log_info "=== DÉPLOIEMENT SUPERVOTE EN PRODUCTION ==="
    log_info "Serveur: ${PRODUCTION_SERVER}"
    log_info "Domaine: ${DOMAIN}"
    log_info "Email: ${EMAIL}"
    echo ""
    
    read -p "Voulez-vous continuer avec le déploiement? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Déploiement annulé par l'utilisateur"
        exit 0
    fi
    
    log_info "Création du script de déploiement distant..."
    create_remote_deployment_script
    
    log_info "Copie du script sur le serveur de production..."
    scp remote-deploy.sh ${PRODUCTION_SERVER}:~/
    
    log_info "Exécution du déploiement sur le serveur..."
    ssh ${PRODUCTION_SERVER} "chmod +x remote-deploy.sh && ./remote-deploy.sh"
    
    log_info "Nettoyage des fichiers temporaires..."
    rm -f remote-deploy.sh
    
    log_success "=== DÉPLOIEMENT TERMINÉ ==="
    echo ""
    echo "🎉 SUPERvote a été déployé avec succès!"
    echo "🌐 Votre application est maintenant disponible sur: https://${DOMAIN}"
    echo ""
    echo "Commandes utiles pour gérer votre application:"
    echo "  ssh ${PRODUCTION_SERVER} 'cd ${APP_DIR}/SUPERvote && ./manage.sh status'"
    echo "  ssh ${PRODUCTION_SERVER} 'cd ${APP_DIR}/SUPERvote && ./manage.sh logs'"
    echo "  ssh ${PRODUCTION_SERVER} 'cd ${APP_DIR}/SUPERvote && ./manage.sh restart'"
    echo "  ssh ${PRODUCTION_SERVER} 'cd ${APP_DIR}/SUPERvote && ./manage.sh update'"
}

# Fonction principale
main() {
    echo "=== Script de Déploiement SUPERvote en Production ==="
    echo "Ce script va déployer SUPERvote sur ${PRODUCTION_SERVER}"
    echo ""
    
    check_ssh_connection
    deploy_to_production
}

# Exécution du script principal
main "$@"