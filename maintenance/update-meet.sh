#!/bin/bash
################################################################################
# Script de mise à jour de La Suite Meet
# 
# Ce script automatise la procédure de mise à jour décrite dans la documentation
# officielle : https://github.com/suitenumerique/meet/blob/main/UPGRADE.md
#
# Usage: ./update-meet.sh [VERSION]
#   Si VERSION n'est pas spécifié, la dernière version stable sera utilisée
#
# Exemple: ./update-meet.sh v1.2.3
################################################################################

set -e  # Arrêter en cas d'erreur

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yaml}"
BACKUP_DIR="${BACKUP_DIR:-./backups}"
LOG_FILE="${LOG_FILE:-./logs/update-$(date +%Y%m%d_%H%M%S).log}"

# Fonctions utilitaires
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

# Créer les répertoires nécessaires
mkdir -p "$BACKUP_DIR"
mkdir -p "$(dirname "$LOG_FILE")"

log "========================================="
log "Début de la mise à jour de Meet"
log "========================================="

# Vérifier que Docker Compose est installé
if ! command -v docker &> /dev/null; then
    error "Docker n'est pas installé"
    exit 1
fi

if ! docker compose version &> /dev/null; then
    error "Docker Compose (v2) n'est pas installé"
    exit 1
fi

# Vérifier que le fichier compose existe
if [ ! -f "$COMPOSE_FILE" ]; then
    error "Fichier $COMPOSE_FILE introuvable"
    exit 1
fi

# Récupérer la version cible
TARGET_VERSION="${1:-latest}"
info "Version cible: $TARGET_VERSION"

# Étape 1: Backup de la base de données
log "Étape 1/6: Sauvegarde de la base de données..."
BACKUP_FILE="$BACKUP_DIR/meet-db-backup-$(date +%Y%m%d_%H%M%S).sql"

if docker compose ps | grep -q "db.*Up"; then
    docker compose exec -T db pg_dump -U meet meet > "$BACKUP_FILE" 2>> "$LOG_FILE"
    if [ -f "$BACKUP_FILE" ] && [ -s "$BACKUP_FILE" ]; then
        log "✓ Base de données sauvegardée: $BACKUP_FILE"
        
        # Compresser le backup
        gzip "$BACKUP_FILE"
        log "✓ Backup compressé: ${BACKUP_FILE}.gz"
    else
        error "Échec de la sauvegarde de la base de données"
        exit 1
    fi
else
    warning "Service PostgreSQL non disponible, backup ignoré"
fi

# Étape 2: Vérifier le CHANGELOG et UPGRADE
log "Étape 2/6: Vérification des notes de mise à jour..."
info "Consultez les documents suivants avant de continuer:"
info "  - CHANGELOG: https://github.com/suitenumerique/meet/blob/main/CHANGELOG.md"
info "  - UPGRADE: https://github.com/suitenumerique/meet/blob/main/UPGRADE.md"
echo ""
read -p "Avez-vous consulté la documentation de mise à jour ? (o/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[OoYy]$ ]]; then
    warning "Mise à jour annulée. Consultez la documentation avant de continuer."
    exit 0
fi

# Étape 3: Mettre à jour les tags d'images
log "Étape 3/6: Mise à jour des tags d'images vers $TARGET_VERSION..."

if [ "$TARGET_VERSION" != "latest" ]; then
    # Remplacer les tags dans le compose file
    sed -i.bak "s|image: registry\.gitlab\.com/lasuite/meet/\([^:]*\):.*|image: registry.gitlab.com/lasuite/meet/\1:$TARGET_VERSION|g" "$COMPOSE_FILE"
    log "✓ Tags mis à jour vers $TARGET_VERSION"
    log "  Backup du compose file: ${COMPOSE_FILE}.bak"
else
    info "Utilisation de la version 'latest'"
fi

# Étape 4: Télécharger les nouvelles images
log "Étape 4/6: Téléchargement des nouvelles images..."
docker compose pull | tee -a "$LOG_FILE"
log "✓ Images téléchargées"

# Étape 5: Arrêter et redémarrer les conteneurs
log "Étape 5/6: Redémarrage des conteneurs..."
docker compose down
docker compose up -d
log "✓ Conteneurs redémarrés"

# Attendre que les services soient prêts
info "Attente du démarrage des services (30s)..."
sleep 30

# Étape 6: Exécuter les migrations
log "Étape 6/6: Exécution des migrations de base de données..."
docker compose run --rm backend python manage.py migrate | tee -a "$LOG_FILE"
log "✓ Migrations exécutées"

# Vérifier l'état des services
log "Vérification de l'état des services..."
docker compose ps

# Afficher les logs récents
info "Logs récents (dernières 20 lignes):"
docker compose logs --tail=20

log "========================================="
log "Mise à jour terminée avec succès !"
log "========================================="
log "Backup disponible: ${BACKUP_FILE}.gz"
log "Logs complets: $LOG_FILE"

exit 0
