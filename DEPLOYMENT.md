# La Suite Meet - Déploiement avec Private Repository

Guide complet pour déployer La Suite Meet via votre outil de gestion de serveur utilisant l'option **Private Repository (with Deploy Key)**.

## 📋 Prérequis

### Serveur
- Ubuntu 20.04+ / Debian 11+ (recommandé)
- 4 CPU cores minimum
- 8 GB RAM minimum
- 50 GB espace disque
- Docker Engine installé
- Docker Compose v2 installé

### Services externes requis
- ✅ **Provider OIDC** (Keycloak, Auth0, etc.)
- ✅ **Service SMTP** pour les emails
- ✅ **Certificats SSL/TLS** (Let's Encrypt recommandé)
- ✅ **DNS configuré** pour les 3 domaines

### Ports réseau requis
```
80/tcp    - HTTP (redirection HTTPS)
443/tcp   - HTTPS
443/udp   - TURN/TLS
7881/tcp  - WebRTC ICE over TCP
7882/udp  - WebRTC UDP multiplexing
```

## 🚀 Installation

### Option 1: Installation automatique (Recommandée)

```bash
# Cloner le dépôt
git clone <votre-repo-privé> meet
cd meet

# Lancer le script d'installation
./setup.sh
```

Le script va automatiquement:
1. ✅ Vérifier les prérequis
2. ✅ Générer tous les secrets sécurisés
3. ✅ Configurer les variables d'environnement
4. ✅ Créer les répertoires de données
5. ✅ Configurer le firewall (optionnel)
6. ✅ Démarrer les services
7. ✅ Initialiser la base de données
8. ✅ Créer l'utilisateur administrateur

### Option 2: Installation manuelle

#### 1. Configuration de l'environnement

```bash
# Copier les templates
cp .env.common.example .env.common
cp .env.postgresql.example .env.postgresql

# Générer les secrets
DJANGO_SECRET=$(python3 -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())")
DB_PASSWORD=$(openssl rand -base64 32)
LIVEKIT_SECRET=$(openssl rand -base64 32)

# Éditer les fichiers
nano .env.common
nano .env.postgresql
nano livekit/livekit-server.yaml
```

#### 2. Configuration des domaines dans `.env.common`

```bash
MEET_HOST=meet.votre-domaine.fr
KEYCLOAK_HOST=id.votre-domaine.fr
LIVEKIT_HOST=livekit.votre-domaine.fr
```

#### 3. Configuration SMTP

```bash
DJANGO_EMAIL_HOST=smtp.example.com
DJANGO_EMAIL_HOST_USER=noreply@example.com
DJANGO_EMAIL_HOST_PASSWORD=votre_password
DJANGO_EMAIL_PORT=587
DJANGO_EMAIL_FROM=noreply@example.com
DJANGO_EMAIL_USE_TLS=true
```

#### 4. Créer les répertoires et démarrer

```bash
# Créer les répertoires de données
mkdir -p data/postgresql data/redis

# Démarrer les services
docker compose pull
docker compose up -d

# Initialiser la base de données
docker compose exec backend python manage.py migrate

# Créer l'administrateur
docker compose exec backend python manage.py createsuperuser \
  --email admin@example.com \
  --password VotreMotDePasseSecurise
```

## 🔐 Configuration OIDC (Keycloak)

### Créer un Realm

1. Connectez-vous à votre Keycloak
2. Créez un nouveau realm nommé `meet`
3. Configurez les paramètres du realm

### Créer un Client

1. Dans le realm `meet`, créez un nouveau client:
   - **Client ID**: `meet`
   - **Client Protocol**: `openid-connect`
   - **Access Type**: `confidential`

2. Configurez les URLs:
   - **Root URL**: `https://meet.votre-domaine.fr`
   - **Valid Redirect URIs**: `https://meet.votre-domaine.fr/*`
   - **Web Origins**: `https://meet.votre-domaine.fr`

3. Récupérez le **Client Secret** dans l'onglet "Credentials"

4. Mettez à jour `.env.common`:
```bash
OIDC_RP_CLIENT_ID=meet
OIDC_RP_CLIENT_SECRET=<votre_client_secret>
```

## 🌐 Configuration Reverse Proxy

### Avec Caddy (Recommandé - Simple)

```caddy
meet.votre-domaine.fr {
    reverse_proxy frontend:8083
}

livekit.votre-domaine.fr {
    reverse_proxy livekit:7880
}
```

### Avec Nginx

```nginx
# Meet Frontend
server {
    listen 443 ssl http2;
    server_name meet.votre-domaine.fr;
    
    ssl_certificate /etc/letsencrypt/live/meet.votre-domaine.fr/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/meet.votre-domaine.fr/privkey.pem;
    
    location / {
        proxy_pass http://localhost:8083;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# Livekit Server
server {
    listen 443 ssl http2;
    server_name livekit.votre-domaine.fr;
    
    ssl_certificate /etc/letsencrypt/live/livekit.votre-domaine.fr/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/livekit.votre-domaine.fr/privkey.pem;
    
    location / {
        proxy_pass http://localhost:7880;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

### Avec Traefik

Les labels Traefik sont déjà configurés dans le `docker-compose.yaml`.
Il suffit d'avoir Traefik configuré avec un réseau externe `meet-public`.

## 📊 Monitoring et Logs

### Voir les logs en temps réel

```bash
# Tous les services
docker compose logs -f

# Un service spécifique
docker compose logs -f backend
docker compose logs -f frontend
docker compose logs -f livekit
```

### Vérifier l'état des services

```bash
docker compose ps
```

### Vérifier la santé du backend

```bash
docker compose exec backend python manage.py check
```

## 🔄 Mise à jour

```bash
# 1. Sauvegarder les données
docker compose exec postgresql pg_dump -U meet meet > backup_$(date +%Y%m%d).sql

# 2. Mettre à jour les images
docker compose pull

# 3. Redémarrer les services
docker compose up -d

# 4. Appliquer les migrations
docker compose exec backend python manage.py migrate
```

## 🐛 Dépannage

### Le backend ne démarre pas

```bash
# Vérifier les logs
docker compose logs backend

# Vérifier la base de données
docker compose exec postgresql psql -U meet -d meet -c "SELECT 1"
```

### Problèmes OIDC

```bash
# Vérifier la configuration OIDC
docker compose exec backend python manage.py shell
>>> from django.conf import settings
>>> print(settings.OIDC_RP_CLIENT_ID)
>>> print(settings.OIDC_OP_AUTHORIZATION_ENDPOINT)
```

### Livekit ne se connecte pas

1. Vérifiez que le secret est identique dans:
   - `.env.common` (`LIVEKIT_API_SECRET`)
   - `livekit/livekit-server.yaml` (dans la section `keys`)

2. Vérifiez les ports:
```bash
netstat -tulpn | grep -E '7880|7881|7882'
```

### Réinitialiser complètement

```bash
# ATTENTION: Supprime toutes les données
docker compose down -v
rm -rf data/*
./setup.sh
```

## 📁 Structure du projet

```
meet/
├── docker-compose.yaml       # Configuration Docker principale
├── .env.common               # Variables d'environnement communes
├── .env.postgresql           # Configuration base de données
├── setup.sh                  # Script d'installation automatique
├── DEPLOYMENT.md            # Ce fichier
├── livekit/
│   └── livekit-server.yaml  # Configuration Livekit
├── nginx/
│   └── default.conf.template # Configuration Nginx
└── data/                     # Données persistantes
    ├── postgresql/
    └── redis/
```

## 🔒 Sécurité

### Bonnes pratiques

1. **Secrets**:
   - Ne commitez JAMAIS les fichiers `.env.common` et `.env.postgresql`
   - Utilisez des mots de passe forts (>32 caractères)
   - Changez régulièrement les secrets

2. **Firewall**:
   - Limitez l'accès SSH
   - N'exposez que les ports nécessaires
   - Utilisez fail2ban pour les attaques brute-force

3. **SSL/TLS**:
   - Utilisez Let's Encrypt pour les certificats
   - Activez HSTS
   - Forcez HTTPS

4. **Mises à jour**:
   - Mettez à jour régulièrement les images Docker
   - Surveillez les CVE
   - Testez les mises à jour en staging d'abord

## 📞 Support

- Documentation officielle: https://github.com/suitenumerique/meet
- Issues: https://github.com/suitenumerique/meet/issues

