#!/bin/bash

# La Suite Meet - Script d'Installation Automatique
# Compatible avec Private Repository (with Deploy Key)
# Version: 2.0.0

set -e

echo "=========================================="
echo "  La Suite Meet - Installation Automatique"
echo "  Version 2.0.0"
echo "=========================================="
echo ""

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables pour mode non-interactif
NONINTERACTIVE=${NONINTERACTIVE:-false}
SKIP_FIREWALL=${SKIP_FIREWALL:-false}
SKIP_MIGRATION=${SKIP_MIGRATION:-false}

# Fonction pour afficher les messages
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

step() {
    echo -e "\n${BLUE}[STEP]${NC} $1"
}

# Fonction pour générer des secrets sécurisés
generate_secret() {
    if command -v openssl &> /dev/null; then
        openssl rand -base64 32 | tr -d '\n'
    else
        # Fallback si openssl n'est pas disponible
        head -c 32 /dev/urandom | base64 | tr -d '\n'
    fi
}

# Fonction pour générer une clé Django
generate_django_secret() {
    # Essayer d'abord avec Python
    if command -v python3 &> /dev/null; then
        python3 -c "import secrets, string; print(''.join(secrets.choice(string.ascii_letters + string.digits + '!@#$%^&*(-_=+)') for i in range(50)))" 2>/dev/null || generate_secret
    else
        generate_secret
    fi
}

# Vérification des prérequis
check_requirements() {
    step "Vérification des prérequis"
    
    local errors=0
    
    # Docker
    if ! command -v docker &> /dev/null; then
        error "Docker n'est pas installé"
        echo "  Installation: https://docs.docker.com/engine/install/"
        errors=$((errors + 1))
    else
        local docker_version=$(docker --version | grep -oP '\d+\.\d+' | head -1)
        success "Docker ${docker_version} détecté"
    fi
    
    # Docker Compose
    if ! docker compose version &> /dev/null; then
        error "Docker Compose v2 n'est pas installé"
        echo "  Installation: https://docs.docker.com/compose/install/"
        errors=$((errors + 1))
    else
        local compose_version=$(docker compose version | grep -oP 'v\d+\.\d+' | head -1)
        success "Docker Compose ${compose_version} détecté"
    fi
    
    # Vérifier les permissions Docker
    if ! docker ps &> /dev/null; then
        warn "Permission denied pour Docker. Vous devrez peut-être utiliser 'sudo'"
    fi
    
    if [ $errors -gt 0 ]; then
        error "Installation impossible : $errors prérequis manquants"
        exit 1
    fi
    
    success "Tous les prérequis sont satisfaits"
}

# Vérifier si la configuration existe déjà
check_existing_config() {
    if [ -f .env.common ] && [ -f .env.postgresql ]; then
        warn "Configuration existante détectée"
        
        if [ "$NONINTERACTIVE" = "true" ]; then
            info "Mode non-interactif: configuration existante conservée"
            return 1
        fi
        
        read -p "Voulez-vous recréer la configuration ? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Configuration existante conservée"
            return 1
        fi
    fi
    return 0
}

# Configuration des variables d'environnement
configure_environment() {
    step "Configuration de l'environnement"
    
    # Vérifier si on garde la config existante
    if ! check_existing_config; then
        return 0
    fi
    
    # Créer les fichiers à partir des exemples
    info "Création des fichiers de configuration..."
    cp .env.common.example .env.common
    cp .env.postgresql.example .env.postgresql
    success "Fichiers de configuration créés"
    
    # Générer les secrets
    info "Génération des secrets sécurisés..."
    local DJANGO_SECRET=$(generate_django_secret)
    local DB_PASSWORD=$(generate_secret)
    local LIVEKIT_SECRET=$(generate_secret)
    
    # Remplacer dans .env.common (compatible macOS et Linux)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s|DJANGO_SECRET_KEY=.*|DJANGO_SECRET_KEY=${DJANGO_SECRET}|" .env.common
        sed -i '' "s|LIVEKIT_API_SECRET=.*|LIVEKIT_API_SECRET=${LIVEKIT_SECRET}|" .env.common
    else
        # Linux
        sed -i "s|DJANGO_SECRET_KEY=.*|DJANGO_SECRET_KEY=${DJANGO_SECRET}|" .env.common
        sed -i "s|LIVEKIT_API_SECRET=.*|LIVEKIT_API_SECRET=${LIVEKIT_SECRET}|" .env.common
    fi
    
    # Remplacer dans .env.postgresql
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|DB_PASSWORD=.*|DB_PASSWORD=${DB_PASSWORD}|" .env.postgresql
    else
        sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=${DB_PASSWORD}|" .env.postgresql
    fi
    
    # Mettre à jour livekit-server.yaml
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|<LIVEKIT_API_SECRET>|${LIVEKIT_SECRET}|g" livekit/livekit-server.yaml
    else
        sed -i "s|<LIVEKIT_API_SECRET>|${LIVEKIT_SECRET}|g" livekit/livekit-server.yaml
    fi
    
    success "Secrets générés et configurés"
    
    # Configuration des domaines
    if [ "$NONINTERACTIVE" != "true" ]; then
        configure_domains
        configure_smtp
        configure_oidc
    else
        info "Mode non-interactif: utilisez les variables d'environnement pour configurer"
        info "  MEET_HOST, LIVEKIT_HOST, KEYCLOAK_HOST"
        info "  SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASSWORD, SMTP_FROM"
        info "  OIDC_CLIENT_ID, OIDC_CLIENT_SECRET"
    fi
}

# Configuration des domaines
configure_domains() {
    echo ""
    info "Configuration des domaines"
    info "Laissez vide pour garder les valeurs par défaut"
    
    # Lire les domaines
    read -p "Domaine pour Meet [meet.domain.tld]: " MEET_HOST
    MEET_HOST=${MEET_HOST:-${MEET_HOST_ENV:-meet.domain.tld}}
    
    read -p "Domaine pour Keycloak [id.domain.tld]: " KEYCLOAK_HOST
    KEYCLOAK_HOST=${KEYCLOAK_HOST:-${KEYCLOAK_HOST_ENV:-id.domain.tld}}
    
    read -p "Domaine pour Livekit [livekit.domain.tld]: " LIVEKIT_HOST
    LIVEKIT_HOST=${LIVEKIT_HOST:-${LIVEKIT_HOST_ENV:-livekit.domain.tld}}
    
    # Remplacer les domaines
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|MEET_HOST=.*|MEET_HOST=${MEET_HOST}|" .env.common
        sed -i '' "s|KEYCLOAK_HOST=.*|KEYCLOAK_HOST=${KEYCLOAK_HOST}|" .env.common
        sed -i '' "s|LIVEKIT_HOST=.*|LIVEKIT_HOST=${LIVEKIT_HOST}|" .env.common
    else
        sed -i "s|MEET_HOST=.*|MEET_HOST=${MEET_HOST}|" .env.common
        sed -i "s|KEYCLOAK_HOST=.*|KEYCLOAK_HOST=${KEYCLOAK_HOST}|" .env.common
        sed -i "s|LIVEKIT_HOST=.*|LIVEKIT_HOST=${LIVEKIT_HOST}|" .env.common
    fi
    
    success "Domaines configurés"
}

# Configuration SMTP
configure_smtp() {
    echo ""
    info "Configuration SMTP (requis pour les invitations)"
    
    read -p "Hôte SMTP [smtp.example.com]: " SMTP_HOST
    SMTP_HOST=${SMTP_HOST:-${SMTP_HOST_ENV:-smtp.example.com}}
    
    read -p "Port SMTP [587]: " SMTP_PORT
    SMTP_PORT=${SMTP_PORT:-${SMTP_PORT_ENV:-587}}
    
    read -p "Utilisateur SMTP: " SMTP_USER
    SMTP_USER=${SMTP_USER:-${SMTP_USER_ENV:-}}
    
    read -s -p "Mot de passe SMTP: " SMTP_PASSWORD
    echo
    SMTP_PASSWORD=${SMTP_PASSWORD:-${SMTP_PASSWORD_ENV:-}}
    
    read -p "Email expéditeur: " SMTP_FROM
    SMTP_FROM=${SMTP_FROM:-${SMTP_FROM_ENV:-}}
    
    # Remplacer dans .env.common
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|DJANGO_EMAIL_HOST=.*|DJANGO_EMAIL_HOST=${SMTP_HOST}|" .env.common
        sed -i '' "s|DJANGO_EMAIL_PORT=.*|DJANGO_EMAIL_PORT=${SMTP_PORT}|" .env.common
        sed -i '' "s|DJANGO_EMAIL_HOST_USER=.*|DJANGO_EMAIL_HOST_USER=${SMTP_USER}|" .env.common
        sed -i '' "s|DJANGO_EMAIL_HOST_PASSWORD=.*|DJANGO_EMAIL_HOST_PASSWORD=${SMTP_PASSWORD}|" .env.common
        sed -i '' "s|DJANGO_EMAIL_FROM=.*|DJANGO_EMAIL_FROM=${SMTP_FROM}|" .env.common
    else
        sed -i "s|DJANGO_EMAIL_HOST=.*|DJANGO_EMAIL_HOST=${SMTP_HOST}|" .env.common
        sed -i "s|DJANGO_EMAIL_PORT=.*|DJANGO_EMAIL_PORT=${SMTP_PORT}|" .env.common
        sed -i "s|DJANGO_EMAIL_HOST_USER=.*|DJANGO_EMAIL_HOST_USER=${SMTP_USER}|" .env.common
        sed -i "s|DJANGO_EMAIL_HOST_PASSWORD=.*|DJANGO_EMAIL_HOST_PASSWORD=${SMTP_PASSWORD}|" .env.common
        sed -i "s|DJANGO_EMAIL_FROM=.*|DJANGO_EMAIL_FROM=${SMTP_FROM}|" .env.common
    fi
    
    success "SMTP configuré"
}

# Configuration OIDC
configure_oidc() {
    echo ""
    info "Configuration OIDC (authentification)"
    
    read -p "Client ID OIDC [meet]: " OIDC_CLIENT_ID
    OIDC_CLIENT_ID=${OIDC_CLIENT_ID:-${OIDC_CLIENT_ID_ENV:-meet}}
    
    read -s -p "Client Secret OIDC: " OIDC_CLIENT_SECRET
    echo
    OIDC_CLIENT_SECRET=${OIDC_CLIENT_SECRET:-${OIDC_CLIENT_SECRET_ENV:-}}
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|OIDC_RP_CLIENT_ID=.*|OIDC_RP_CLIENT_ID=${OIDC_CLIENT_ID}|" .env.common
        sed -i '' "s|OIDC_RP_CLIENT_SECRET=.*|OIDC_RP_CLIENT_SECRET=${OIDC_CLIENT_SECRET}|" .env.common
    else
        sed -i "s|OIDC_RP_CLIENT_ID=.*|OIDC_RP_CLIENT_ID=${OIDC_CLIENT_ID}|" .env.common
        sed -i "s|OIDC_RP_CLIENT_SECRET=.*|OIDC_RP_CLIENT_SECRET=${OIDC_CLIENT_SECRET}|" .env.common
    fi
    
    success "OIDC configuré"
    
    echo ""
    warn "⚠️  N'oubliez pas de configurer votre provider OIDC (Keycloak) avec:"
    warn "    - Client ID: ${OIDC_CLIENT_ID}"
    warn "    - Redirect URIs: https://${MEET_HOST}/*"
    warn "    - Web Origins: https://${MEET_HOST}"
}

# Créer les répertoires nécessaires
create_directories() {
    step "Création des répertoires de données"
    
    local dirs=(
        "data/postgresql"
        "data/redis"
        "logs"
    )
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            info "Créé: $dir"
        fi
    done
    
    success "Répertoires créés"
}

# Configuration du firewall
configure_firewall() {
    if [ "$SKIP_FIREWALL" = "true" ]; then
        info "Configuration firewall ignorée (SKIP_FIREWALL=true)"
        return 0
    fi
    
    echo ""
    if [ "$NONINTERACTIVE" = "true" ]; then
        info "Mode non-interactif: configuration firewall ignorée"
        warn "Configurez manuellement les ports: 80, 443 (TCP/UDP), 7881 (TCP), 7882 (UDP)"
        return 0
    fi
    
    read -p "Voulez-vous configurer le firewall automatiquement (ufw) ? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        warn "Configuration firewall ignorée"
        return 0
    fi
    
    step "Configuration du firewall"
    
    if command -v ufw &> /dev/null; then
        info "Configuration UFW..."
        sudo ufw allow 80/tcp comment "Meet - HTTP" || true
        sudo ufw allow 443/tcp comment "Meet - HTTPS" || true
        sudo ufw allow 443/udp comment "Meet - TURN/TLS" || true
        sudo ufw allow 7881/tcp comment "Meet - WebRTC ICE TCP" || true
        sudo ufw allow 7882/udp comment "Meet - WebRTC UDP" || true
        
        # Activer ufw si pas encore actif
        if ! sudo ufw status | grep -q "Status: active"; then
            sudo ufw --force enable
        fi
        
        success "Firewall configuré (ufw)"
    elif command -v firewall-cmd &> /dev/null; then
        info "Configuration firewalld..."
        sudo firewall-cmd --permanent --add-port=80/tcp || true
        sudo firewall-cmd --permanent --add-port=443/tcp || true
        sudo firewall-cmd --permanent --add-port=443/udp || true
        sudo firewall-cmd --permanent --add-port=7881/tcp || true
        sudo firewall-cmd --permanent --add-port=7882/udp || true
        sudo firewall-cmd --reload
        
        success "Firewall configuré (firewalld)"
    else
        warn "Aucun firewall reconnu (ufw/firewalld). Configurez manuellement:"
        warn "  - 80/tcp (HTTP)"
        warn "  - 443/tcp (HTTPS)"
        warn "  - 443/udp (TURN/TLS)"
        warn "  - 7881/tcp (WebRTC ICE TCP)"
        warn "  - 7882/udp (WebRTC UDP)"
    fi
}

# Démarrer les services
start_services() {
    step "Démarrage des services Docker"
    
    info "Pull des images Docker..."
    docker compose pull
    
    info "Démarrage des conteneurs..."
    docker compose up -d
    
    success "Services démarrés"
    
    # Attente que les services soient prêts
    info "Attente que les services soient prêts (cela peut prendre 30-60 secondes)..."
    local max_wait=60
    local waited=0
    
    while [ $waited -lt $max_wait ]; do
        if docker compose ps | grep -q "unhealthy"; then
            sleep 2
            waited=$((waited + 2))
        else
            break
        fi
    done
    
    success "Services opérationnels"
}

# Vérifier la santé des services
check_services_health() {
    step "Vérification de la santé des services"
    
    local services=("postgresql" "redis" "backend")
    local all_healthy=true
    
    for service in "${services[@]}"; do
        local health=$(docker compose ps "$service" --format json 2>/dev/null | grep -o '"Health":"[^"]*"' | cut -d'"' -f4)
        
        if [ "$health" = "healthy" ] || docker compose ps "$service" | grep -q "Up"; then
            success "$service: OK"
        else
            error "$service: NOK"
            all_healthy=false
        fi
    done
    
    if [ "$all_healthy" = false ]; then
        warn "Certains services ne sont pas en bon état"
        info "Vérifiez les logs: docker compose logs"
        return 1
    fi
    
    success "Tous les services sont en bonne santé"
}

# Initialiser la base de données
init_database() {
    if [ "$SKIP_MIGRATION" = "true" ]; then
        info "Migration de base de données ignorée (SKIP_MIGRATION=true)"
        return 0
    fi
    
    step "Initialisation de la base de données"
    
    # Attendre que le backend soit prêt
    info "Attente que le backend soit prêt..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if docker compose exec -T backend python manage.py check &> /dev/null; then
            break
        fi
        sleep 2
        attempt=$((attempt + 1))
    done
    
    if [ $attempt -eq $max_attempts ]; then
        error "Le backend n'est pas devenu prêt à temps"
        warn "Vérifiez les logs: docker compose logs backend"
        return 1
    fi
    
    # Migrations
    info "Application des migrations..."
    if docker compose exec -T backend python manage.py migrate; then
        success "Migrations appliquées"
    else
        error "Échec des migrations"
        return 1
    fi
    
    # Créer le superuser
    if [ "$NONINTERACTIVE" = "true" ]; then
        warn "Mode non-interactif: création du superuser ignorée"
        info "Créez-le manuellement: docker compose exec backend python manage.py createsuperuser"
        return 0
    fi
    
    echo ""
    info "Création de l'utilisateur administrateur"
    read -p "Email administrateur: " ADMIN_EMAIL
    read -s -p "Mot de passe administrateur: " ADMIN_PASSWORD
    echo
    
    if [ -z "$ADMIN_EMAIL" ] || [ -z "$ADMIN_PASSWORD" ]; then
        warn "Email ou mot de passe vide, création du superuser ignorée"
        info "Créez-le plus tard: docker compose exec backend python manage.py createsuperuser"
    else
        if docker compose exec -T backend python manage.py createsuperuser \
            --email "$ADMIN_EMAIL" \
            --password "$ADMIN_PASSWORD" \
            --noinput 2>/dev/null; then
            success "Utilisateur administrateur créé"
        else
            warn "L'utilisateur existe peut-être déjà ou erreur lors de la création"
        fi
    fi
}

# Afficher les informations finales
show_final_info() {
    local MEET_HOST=$(grep "^MEET_HOST=" .env.common | cut -d'=' -f2)
    local LIVEKIT_HOST=$(grep "^LIVEKIT_HOST=" .env.common | cut -d'=' -f2)
    
    echo ""
    echo "=========================================="
    success "Installation terminée avec succès ! 🎉"
    echo "=========================================="
    echo ""
    info "Vos services La Suite Meet sont maintenant en cours d'exécution."
    echo ""
    info "URLs d'accès:"
    echo "  • Meet: https://${MEET_HOST}"
    echo "  • Admin: https://${MEET_HOST}/admin"
    echo "  • Livekit: https://${LIVEKIT_HOST}"
    echo ""
    info "Prochaines étapes:"
    echo "  1. ✅ Configurez votre reverse proxy (nginx, Caddy, Traefik, etc.)"
    echo "  2. ✅ Configurez votre provider OIDC (Keycloak)"
    echo "  3. ✅ Assurez-vous que les certificats SSL/TLS sont en place"
    echo ""
    info "Commandes utiles:"
    echo "  • Voir les logs:        docker compose logs -f"
    echo "  • Redémarrer:          docker compose restart"
    echo "  • Arrêter:             docker compose down"
    echo "  • Mettre à jour:       docker compose pull && docker compose up -d"
    echo "  • Vérifier la santé:   docker compose ps"
    echo ""
    warn "Secrets générés (sauvegardez-les en sécurité):"
    echo "  • Django Secret:       Voir .env.common"
    echo "  • DB Password:         Voir .env.postgresql"
    echo "  • Livekit Secret:      Voir livekit/livekit-server.yaml"
    echo ""
    info "Documentation complète: DEPLOYMENT_GUIDE.md"
    echo ""
}

# Afficher l'aide
show_help() {
    cat << EOF
Usage: ./setup.sh [OPTIONS]

Installation automatique de La Suite Meet

OPTIONS:
    -h, --help              Afficher cette aide
    -n, --non-interactive   Mode non-interactif (utilise les variables d'environnement)
    --skip-firewall         Ignorer la configuration du firewall
    --skip-migration        Ignorer les migrations de base de données
    
VARIABLES D'ENVIRONNEMENT (mode non-interactif):
    MEET_HOST_ENV           Domaine pour Meet (défaut: meet.domain.tld)
    LIVEKIT_HOST_ENV        Domaine pour Livekit (défaut: livekit.domain.tld)
    KEYCLOAK_HOST_ENV       Domaine pour Keycloak (défaut: id.domain.tld)
    SMTP_HOST_ENV           Hôte SMTP (défaut: smtp.example.com)
    SMTP_PORT_ENV           Port SMTP (défaut: 587)
    SMTP_USER_ENV           Utilisateur SMTP
    SMTP_PASSWORD_ENV       Mot de passe SMTP
    SMTP_FROM_ENV           Email expéditeur
    OIDC_CLIENT_ID_ENV      Client ID OIDC (défaut: meet)
    OIDC_CLIENT_SECRET_ENV  Secret OIDC

EXEMPLES:
    # Installation interactive
    ./setup.sh
    
    # Installation non-interactive
    NONINTERACTIVE=true \\
    MEET_HOST_ENV=meet.example.com \\
    LIVEKIT_HOST_ENV=livekit.example.com \\
    KEYCLOAK_HOST_ENV=id.example.com \\
    ./setup.sh --non-interactive
    
    # Installation sans firewall
    ./setup.sh --skip-firewall

EOF
}

# Parser les arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -n|--non-interactive)
                NONINTERACTIVE=true
                shift
                ;;
            --skip-firewall)
                SKIP_FIREWALL=true
                shift
                ;;
            --skip-migration)
                SKIP_MIGRATION=true
                shift
                ;;
            *)
                error "Option inconnue: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Fonction principale
main() {
    # Parser les arguments
    parse_arguments "$@"
    
    # Exécuter les étapes d'installation
    check_requirements
    configure_environment
    create_directories
    configure_firewall
    start_services
    check_services_health || warn "Vérifiez les logs si des problèmes persistent"
    init_database
    show_final_info
}

# Point d'entrée
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
