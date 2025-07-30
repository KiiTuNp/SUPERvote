#!/bin/bash

# SUPERvote Production Update Script
# Met à jour SUPERvote sur le serveur de production

set -e

# Configuration
PRODUCTION_SERVER="ubuntu@46.226.104.149"
DOMAIN="vote.super-csn.ca"
APP_DIR="/opt/supervote/SUPERvote"

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

# Vérifier la connexion SSH
check_ssh_connection() {
    log_info "Vérification de la connexion SSH..."
    if ! ssh -o ConnectTimeout=10 -o BatchMode=yes ${PRODUCTION_SERVER} exit 2>/dev/null; then
        log_error "Impossible de se connecter à ${PRODUCTION_SERVER}"
        exit 1
    fi
    log_success "Connexion SSH établie"
}

# Créer le script de mise à jour
create_update_script() {
    cat > remote-update.sh << 'UPDATE_SCRIPT'
#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCÈS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[ATTENTION]${NC} $1"; }
log_error() { echo -e "${RED}[ERREUR]${NC} $1"; }

APP_DIR="/opt/supervote/SUPERvote"
DOMAIN="vote.super-csn.ca"

log_info "=== Mise à jour SUPERvote ==="

# Aller dans le répertoire de l'application
cd ${APP_DIR}

# Sauvegarde avant mise à jour
log_info "Création d'une sauvegarde..."
backup_dir="backup_$(date +%Y%m%d_%H%M%S)"
cp -r . ../${backup_dir}
log_success "Sauvegarde créée dans ../${backup_dir}"

# Vérifier le statut actuel
log_info "Vérification du statut actuel..."
docker compose -f docker-compose.prod.yml ps

# Mettre à jour le code
log_info "Mise à jour du code depuis Git..."
git stash || true  # Sauvegarder les modifications locales s'il y en a
git pull origin main
log_success "Code mis à jour"

# Rebuild et redémarrer les conteneurs
log_info "Reconstruction et redémarrage des conteneurs..."
docker compose -f docker-compose.prod.yml up -d --build

# Attendre que les services redémarrent
log_info "Attente du redémarrage des services..."
sleep 30

# Vérifier que tout fonctionne
log_info "Vérification du fonctionnement..."
if curl -I https://${DOMAIN} >/dev/null 2>&1; then
    log_success "✅ Application accessible sur https://${DOMAIN}"
else
    log_error "❌ Application non accessible"
    log_warning "Tentative de restauration de la sauvegarde..."
    
    # Restaurer la sauvegarde
    cd ..
    rm -rf SUPERvote
    cp -r ${backup_dir} SUPERvote
    cd SUPERvote
    docker compose -f docker-compose.prod.yml up -d --build
    
    log_error "Sauvegarde restaurée. Veuillez vérifier les erreurs."
    exit 1
fi

# Nettoyer les anciennes images Docker
log_info "Nettoyage des anciennes images Docker..."
docker image prune -f || true

# Afficher le statut final
log_info "Statut final:"
docker compose -f docker-compose.prod.yml ps

log_success "=== Mise à jour terminée avec succès ==="
echo "🌐 Application: https://${DOMAIN}"
echo "📊 Statut: ./manage.sh status"
echo "📋 Logs: ./manage.sh logs"
UPDATE_SCRIPT
}

# Fonction principale de mise à jour
update_production() {
    log_info "=== MISE À JOUR SUPERVOTE EN PRODUCTION ==="
    log_info "Serveur: ${PRODUCTION_SERVER}"
    log_info "Domaine: ${DOMAIN}"
    echo ""
    
    read -p "Voulez-vous continuer avec la mise à jour? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Mise à jour annulée"
        exit 0
    fi
    
    log_info "Création du script de mise à jour..."
    create_update_script
    
    log_info "Copie du script sur le serveur..."
    scp remote-update.sh ${PRODUCTION_SERVER}:~/
    
    log_info "Exécution de la mise à jour..."
    ssh ${PRODUCTION_SERVER} "chmod +x remote-update.sh && ./remote-update.sh"
    
    log_info "Nettoyage..."
    rm -f remote-update.sh
    
    log_success "=== MISE À JOUR TERMINÉE ==="
    echo ""
    echo "🎉 SUPERvote a été mis à jour avec succès!"
    echo "🌐 Vérifiez votre application sur: https://${DOMAIN}"
}

# Fonction principale
main() {
    echo "=== Script de Mise à Jour SUPERvote Production ==="
    echo "Met à jour SUPERvote sur ${PRODUCTION_SERVER}"
    echo ""
    
    check_ssh_connection
    update_production
}

# Exécution
main "$@"