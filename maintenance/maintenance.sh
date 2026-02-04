#!/bin/bash
################################################################################
# Script de maintenance quotidienne de La Suite Meet
#
# Ce script effectue les tâches de maintenance courantes :
# - Nettoyage des logs
# - Rotation des backups
# - Vérification de l'espace disque
# - Nettoyage Docker
#
# Usage: ./maintenance.sh [OPTIONS]
#
# Options:
#   --backup-only    Effectuer uniquement un backup
#   --clean-only     Effectuer uniquement le nettoyage
#   --dry-run        Simuler sans effectuer les actions
#
################################################################################

set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yaml}"
BACKUP_DIR="${BACKUP_DIR:-./backups}"
LOG_DIR="${LOG_DIR:-./logs}"
MAX_BACKUPS="${MAX_BACKUPS:-10}"
MAX_LOGS="${MAX_LOGS:-30}"
MIN_DISK_SPACE="${MIN_DISK_SPACE:-10}"  # En GB

DRY_RUN=false
BACKUP_ONLY=false
CLEAN_ONLY=false

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Parser les arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --backup-only)
            BACKUP_ONLY=true
            shift
            ;;
        --clean-only)
            CLEAN_ONLY=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            error "Option inconnue: $1"
            exit 1
            ;;
    esac
done

if [ "$DRY_RUN" = true ]; then
    warning "Mode DRY-RUN activé - aucune modification ne sera effectuée"
fi

log "========================================="
log "Début de la maintenance de Meet"
log "========================================="

# Créer les répertoires si nécessaire
mkdir -p "$BACKUP_DIR" "$LOG_DIR"

# Fonction de backup
do_backup() {
    log "1. Création d'un backup de la base de données..."
    
    if [ "$DRY_RUN" = true ]; then
        info "  [DRY-RUN] Backup serait créé dans: $BACKUP_DIR"
        return
    fi
    
    BACKUP_FILE="$BACKUP_DIR/meet-db-backup-$(date +%Y%m%d_%H%M%S).sql"
    
    if docker compose ps | grep -q "db.*Up"; then
        if docker compose exec -T db pg_dump -U meet meet > "$BACKUP_FILE" 2>/dev/null; then
            gzip "$BACKUP_FILE"
            BACKUP_SIZE=$(du -h "${BACKUP_FILE}.gz" | cut -f1)
            log "  ✓ Backup créé: ${BACKUP_FILE}.gz ($BACKUP_SIZE)"
        else
            error "  ✗ Échec du backup"
        fi
    else
        warning "  Service PostgreSQL non disponible"
    fi
}

# Fonction de nettoyage
do_cleanup() {
    log "2. Rotation des backups (garder les $MAX_BACKUPS plus récents)..."
    
    BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/meet-db-backup-*.sql.gz 2>/dev/null | wc -l)
    
    if [ "$BACKUP_COUNT" -gt "$MAX_BACKUPS" ]; then
        TO_DELETE=$((BACKUP_COUNT - MAX_BACKUPS))
        
        if [ "$DRY_RUN" = true ]; then
            info "  [DRY-RUN] $TO_DELETE backups seraient supprimés"
            ls -t "$BACKUP_DIR"/meet-db-backup-*.sql.gz | tail -n "$TO_DELETE"
        else
            DELETED=$(ls -t "$BACKUP_DIR"/meet-db-backup-*.sql.gz | tail -n "$TO_DELETE" | xargs rm -v 2>&1 | wc -l)
            log "  ✓ $DELETED anciens backups supprimés"
        fi
    else
        info "  Aucun backup à supprimer ($BACKUP_COUNT/$MAX_BACKUPS)"
    fi
    
    log "3. Rotation des logs (garder les $MAX_LOGS derniers jours)..."
    
    if [ "$DRY_RUN" = true ]; then
        OLD_LOGS=$(find "$LOG_DIR" -name "*.log" -type f -mtime +$MAX_LOGS 2>/dev/null)
        if [ -n "$OLD_LOGS" ]; then
            info "  [DRY-RUN] Ces logs seraient supprimés:"
            echo "$OLD_LOGS"
        else
            info "  Aucun log ancien à supprimer"
        fi
    else
        DELETED=$(find "$LOG_DIR" -name "*.log" -type f -mtime +$MAX_LOGS -delete -print 2>/dev/null | wc -l)
        if [ "$DELETED" -gt 0 ]; then
            log "  ✓ $DELETED anciens logs supprimés"
        else
            info "  Aucun log ancien à supprimer"
        fi
    fi
    
    log "4. Nettoyage Docker..."
    
    if [ "$DRY_RUN" = true ]; then
        info "  [DRY-RUN] Images Docker seraient nettoyées"
        docker image ls --filter "dangling=true"
    else
        PRUNED=$(docker image prune -f 2>&1 | grep "Total reclaimed space" || echo "0B")
        log "  ✓ Images inutilisées supprimées: $PRUNED"
    fi
}

# Fonction de vérification
do_checks() {
    log "5. Vérifications système..."
    
    # Espace disque
    DISK_SPACE=$(df -BG . | tail -1 | awk '{print $4}' | sed 's/G//')
    if [ "$DISK_SPACE" -lt "$MIN_DISK_SPACE" ]; then
        warning "  ⚠ Espace disque faible: ${DISK_SPACE}GB disponible (minimum: ${MIN_DISK_SPACE}GB)"
    else
        info "  ✓ Espace disque: ${DISK_SPACE}GB disponible"
    fi
    
    # État des conteneurs
    if docker compose ps --format json | jq -e '.[] | select(.State != "running")' > /dev/null 2>&1; then
        warning "  ⚠ Certains conteneurs ne sont pas en cours d'exécution"
        docker compose ps
    else
        info "  ✓ Tous les conteneurs sont actifs"
    fi
    
    # Santé de la base de données
    if docker compose exec -T db pg_isready -U meet > /dev/null 2>&1; then
        info "  ✓ PostgreSQL est opérationnel"
    else
        warning "  ⚠ PostgreSQL ne répond pas"
    fi
    
    # Taille de la base
    DB_SIZE=$(docker compose exec -T db psql -U meet -t -c "SELECT pg_size_pretty(pg_database_size('meet'));" 2>/dev/null | tr -d ' ' || echo "N/A")
    info "  Base de données: $DB_SIZE"
    
    # Statistiques Docker
    info "  Statistiques Docker:"
    docker system df
}

# Exécuter les tâches selon les options
if [ "$CLEAN_ONLY" = true ]; then
    do_cleanup
elif [ "$BACKUP_ONLY" = true ]; then
    do_backup
else
    do_backup
    do_cleanup
    do_checks
fi

log "========================================="
log "Maintenance terminée"
log "========================================="

exit 0
