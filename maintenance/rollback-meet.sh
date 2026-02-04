#!/bin/bash
################################################################################
# Script de rollback de La Suite Meet
#
# Ce script permet de revenir à une version précédente en cas de problème
# après une mise à jour
#
# Usage: ./rollback-meet.sh [BACKUP_FILE]
#   Si BACKUP_FILE n'est pas spécifié, le backup le plus récent sera utilisé
#
# Exemple: ./rollback-meet.sh backups/meet-db-backup-20260204_120000.sql.gz
################################################################################

set -e  # Arrêter en cas d'erreur

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yaml}"
BACKUP_DIR="${BACKUP_DIR:-./backups}"
LOG_FILE="./logs/rollback-$(date +%Y%m%d_%H%M%S).log"

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

mkdir -p "$(dirname "$LOG_FILE")"

log "========================================="
log "Début du rollback de Meet"
log "========================================="

# Vérifications
if [ ! -f "$COMPOSE_FILE" ]; then
    error "Fichier $COMPOSE_FILE introuvable"
    exit 1
fi

if [ ! -d "$BACKUP_DIR" ]; then
    error "Répertoire de backups $BACKUP_DIR introuvable"
    exit 1
fi

# Sélectionner le fichier de backup
if [ -n "$1" ]; then
    BACKUP_FILE="$1"
    if [ ! -f "$BACKUP_FILE" ]; then
        error "Fichier de backup $BACKUP_FILE introuvable"
        exit 1
    fi
else
    # Trouver le backup le plus récent
    BACKUP_FILE=$(ls -t "$BACKUP_DIR"/meet-db-backup-*.sql.gz 2>/dev/null | head -1)
    if [ -z "$BACKUP_FILE" ]; then
        error "Aucun fichier de backup trouvé dans $BACKUP_DIR"
        exit 1
    fi
    warning "Aucun backup spécifié, utilisation du plus récent: $BACKUP_FILE"
fi

info "Fichier de backup: $BACKUP_FILE"
echo ""
warning "ATTENTION: Cette opération va restaurer la base de données"
warning "Toutes les données créées depuis le backup seront perdues"
echo ""
read -p "Êtes-vous sûr de vouloir continuer ? (o/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[OoYy]$ ]]; then
    log "Rollback annulé"
    exit 0
fi

# Étape 1: Restaurer le compose file si backup existe
if [ -f "${COMPOSE_FILE}.bak" ]; then
    log "Étape 1/4: Restauration du fichier compose..."
    cp "${COMPOSE_FILE}.bak" "$COMPOSE_FILE"
    log "✓ Fichier compose restauré"
else
    info "Pas de backup du compose file trouvé, étape ignorée"
fi

# Étape 2: Arrêter les services
log "Étape 2/4: Arrêt des services..."
docker compose down
log "✓ Services arrêtés"

# Étape 3: Restaurer la base de données
log "Étape 3/4: Restauration de la base de données..."

# Démarrer uniquement PostgreSQL
docker compose up -d db
info "Attente du démarrage de PostgreSQL (10s)..."
sleep 10

# Vider la base actuelle
warning "Suppression de la base de données actuelle..."
docker compose exec -T db psql -U meet -d postgres -c "DROP DATABASE IF EXISTS meet;" 2>> "$LOG_FILE" || true
docker compose exec -T db psql -U meet -d postgres -c "CREATE DATABASE meet;" 2>> "$LOG_FILE"

# Restaurer le backup
if [[ "$BACKUP_FILE" == *.gz ]]; then
    gunzip -c "$BACKUP_FILE" | docker compose exec -T db psql -U meet -d meet 2>> "$LOG_FILE"
else
    cat "$BACKUP_FILE" | docker compose exec -T db psql -U meet -d meet 2>> "$LOG_FILE"
fi

log "✓ Base de données restaurée"

# Étape 4: Redémarrer tous les services
log "Étape 4/4: Redémarrage de tous les services..."
docker compose up -d
log "✓ Services redémarrés"

info "Attente du démarrage complet (30s)..."
sleep 30

# Vérifier l'état
log "État des services:"
docker compose ps

log "========================================="
log "Rollback terminé avec succès !"
log "========================================="
log "Log complet: $LOG_FILE"

exit 0
