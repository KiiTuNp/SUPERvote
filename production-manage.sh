#!/bin/bash

# SUPERvote Production Management Script
# Gère SUPERvote sur le serveur de production à distance

# Configuration
PRODUCTION_SERVER="ubuntu@46.226.104.149"
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

# Fonctions de gestion
show_usage() {
    echo "Usage: $0 {status|logs|start|stop|restart|update|backup|shell}"
    echo ""
    echo "Commandes disponibles:"
    echo "  status   - Affiche le statut des services"
    echo "  logs     - Affiche les logs en temps réel"
    echo "  start    - Démarre l'application"
    echo "  stop     - Arrête l'application"
    echo "  restart  - Redémarre l'application"
    echo "  update   - Met à jour l'application"
    echo "  backup   - Crée une sauvegarde"
    echo "  shell    - Ouvre une session SSH"
    echo ""
}

check_ssh() {
    if ! ssh -o ConnectTimeout=5 -o BatchMode=yes ${PRODUCTION_SERVER} exit 2>/dev/null; then
        log_error "Impossible de se connecter à ${PRODUCTION_SERVER}"
        log_error "Vérifiez votre connexion SSH"
        exit 1
    fi
}

show_status() {
    log_info "Statut de SUPERvote sur ${PRODUCTION_SERVER}..."
    ssh ${PRODUCTION_SERVER} "cd ${APP_DIR} && docker compose -f docker-compose.prod.yml ps"
    echo ""
    log_info "Vérification HTTPS..."
    if curl -I https://vote.super-csn.ca >/dev/null 2>&1; then
        log_success "✅ Site accessible sur https://vote.super-csn.ca"
    else
        log_error "❌ Site non accessible"
    fi
}

show_logs() {
    log_info "Logs de SUPERvote (Ctrl+C pour quitter)..."
    ssh ${PRODUCTION_SERVER} "cd ${APP_DIR} && docker compose -f docker-compose.prod.yml logs -f"
}

start_app() {
    log_info "Démarrage de SUPERvote..."
    ssh ${PRODUCTION_SERVER} "cd ${APP_DIR} && docker compose -f docker-compose.prod.yml up -d"
    log_success "Application démarrée"
}

stop_app() {
    log_info "Arrêt de SUPERvote..."
    ssh ${PRODUCTION_SERVER} "cd ${APP_DIR} && docker compose -f docker-compose.prod.yml down"
    log_success "Application arrêtée"
}

restart_app() {
    log_info "Redémarrage de SUPERvote..."
    ssh ${PRODUCTION_SERVER} "cd ${APP_DIR} && docker compose -f docker-compose.prod.yml restart"
    log_success "Application redémarrée"
}

update_app() {
    log_info "Lancement de la mise à jour..."
    ./production-update.sh
}

backup_app() {
    log_info "Création d'une sauvegarde..."
    backup_name="supervote_backup_$(date +%Y%m%d_%H%M%S)"
    ssh ${PRODUCTION_SERVER} "cd /opt/supervote && tar -czf ${backup_name}.tar.gz SUPERvote"
    log_success "Sauvegarde créée: ${backup_name}.tar.gz"
    
    read -p "Voulez-vous télécharger la sauvegarde? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Téléchargement de la sauvegarde..."
        scp ${PRODUCTION_SERVER}:/opt/supervote/${backup_name}.tar.gz ./
        log_success "Sauvegarde téléchargée: ./${backup_name}.tar.gz"
    fi
}

open_shell() {
    log_info "Ouverture d'une session SSH..."
    ssh ${PRODUCTION_SERVER} "cd ${APP_DIR} && bash"
}

# Fonction principale
main() {
    if [ $# -eq 0 ]; then
        show_usage
        exit 1
    fi
    
    check_ssh
    
    case "$1" in
        status)
            show_status
            ;;
        logs)
            show_logs
            ;;
        start)
            start_app
            ;;
        stop)
            stop_app
            ;;
        restart)
            restart_app
            ;;
        update)
            update_app
            ;;
        backup)
            backup_app
            ;;
        shell)
            open_shell
            ;;
        *)
            log_error "Commande inconnue: $1"
            show_usage
            exit 1
            ;;
    esac
}

# Exécution
main "$@"