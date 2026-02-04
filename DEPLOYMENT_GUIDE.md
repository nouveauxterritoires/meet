# 🚀 Guide de Déploiement - La Suite Meet

## Déploiement via Private Repository (with Deploy Key)

Ce guide explique comment déployer La Suite Meet via un outil de gestion de serveur compatible avec Git (Coolify, CapRover, etc.).

---

## 📋 Prérequis

### Serveur
- Docker Engine 24.0+ avec Docker Compose v2
- Minimum 4 GB RAM, 2 vCPUs
- 20 GB d'espace disque
- Ports ouverts : 80, 443 (TCP/UDP), 7881 (TCP), 7882 (UDP)

### Services externes requis
- **OIDC Provider** (Keycloak recommandé) - Authentification utilisateur
- **Service SMTP** - Pour l'envoi d'emails
- **Nom de domaine** avec DNS configuré

---

## 🔧 Configuration dans votre outil de gestion

### Option : **Private Repository (with Deploy Key)**

1. **Repository Git**
   ```
   URL: git@github.com:votre-org/meet.git
   Branch: main
   ```

2. **Deploy Key**
   - Générez une clé SSH dédiée au déploiement
   - Ajoutez-la aux Deploy Keys de votre dépôt Git
   - Configuration en lecture seule suffisante

3. **Fichier Docker Compose**
   ```
   Chemin: docker-compose.yaml
   ```
   ✅ Le fichier est déjà à la racine du projet

4. **Domaines requis** (3 sous-domaines)
   - `meet.votre-domaine.tld` - Application principale
   - `livekit.votre-domaine.tld` - Serveur WebRTC
   - `id.votre-domaine.tld` - Provider OIDC (Keycloak)

---

## 🛠️ Installation Automatique

### Méthode 1 : Script d'installation (Recommandé)

Une fois le dépôt cloné sur votre serveur :

```bash
cd /chemin/vers/meet
chmod +x setup.sh
./setup.sh
```

Le script va :
- ✅ Vérifier les prérequis
- ✅ Générer automatiquement tous les secrets sécurisés
- ✅ Configurer les domaines
- ✅ Configurer SMTP et OIDC
- ✅ Démarrer les services
- ✅ Initialiser la base de données
- ✅ Créer l'utilisateur administrateur

### Méthode 2 : Configuration manuelle

Si vous préférez configurer manuellement :

```bash
# 1. Copier les fichiers d'exemple
cp .env.common.example .env.common
cp .env.postgresql.example .env.postgresql

# 2. Générer les secrets
# Django Secret
python3 -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())"

# Autres secrets (DB, Livekit)
openssl rand -base64 32

# 3. Éditer les fichiers de configuration
nano .env.common
nano .env.postgresql
nano livekit/livekit-server.yaml

# 4. Démarrer
docker compose up -d

# 5. Initialiser la base
docker compose exec backend python manage.py migrate
docker compose exec backend python manage.py createsuperuser
```

---

## 📝 Variables d'environnement à configurer

### 🌐 Domaines (.env.common)
```bash
MEET_HOST=meet.votre-domaine.tld
KEYCLOAK_HOST=id.votre-domaine.tld
LIVEKIT_HOST=livekit.votre-domaine.tld
```

### 🔐 Secrets à générer

```bash
# Django Secret Key (dans .env.common)
DJANGO_SECRET_KEY=<generer_avec_django>

# Database Password (dans .env.postgresql)
DB_PASSWORD=<generer_avec_openssl>

# Livekit API Secret (dans .env.common ET livekit/livekit-server.yaml)
LIVEKIT_API_SECRET=<generer_avec_openssl>
```

### 📧 Configuration SMTP (.env.common)
```bash
DJANGO_EMAIL_HOST=smtp.example.com
DJANGO_EMAIL_HOST_USER=noreply@example.com
DJANGO_EMAIL_HOST_PASSWORD=votre_mot_de_passe
DJANGO_EMAIL_PORT=587
DJANGO_EMAIL_FROM=noreply@example.com
DJANGO_EMAIL_USE_TLS=true
```

### 🔑 Configuration OIDC (.env.common)

Pour Keycloak :
```bash
OIDC_RP_CLIENT_ID=meet
OIDC_RP_CLIENT_SECRET=<secret_depuis_keycloak>
REALM_NAME=meet
```

Les endpoints OIDC sont automatiquement configurés à partir de `KEYCLOAK_HOST` et `REALM_NAME`.

---

## 🔥 Configuration du Firewall

```bash
# UFW (Ubuntu/Debian)
sudo ufw allow 80/tcp comment "HTTP"
sudo ufw allow 443/tcp comment "HTTPS"
sudo ufw allow 443/udp comment "TURN/TLS"
sudo ufw allow 7881/tcp comment "WebRTC ICE TCP"
sudo ufw allow 7882/udp comment "WebRTC UDP"
sudo ufw enable

# Firewalld (CentOS/RHEL)
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --permanent --add-port=443/udp
sudo firewall-cmd --permanent --add-port=7881/tcp
sudo firewall-cmd --permanent --add-port=7882/udp
sudo firewall-cmd --reload
```

---

## 🌐 Configuration Reverse Proxy

### Option A : Labels Traefik (Déjà dans docker-compose.yaml)

Les labels Traefik sont déjà configurés. Si vous utilisez Traefik, ajoutez simplement le réseau :

```yaml
networks:
  meet-public:
    external: true
    name: traefik_default  # Ou le nom de votre réseau Traefik
```

### Option B : Caddy

Exposez les ports dans docker-compose.yaml :
```yaml
frontend:
  ports:
    - "8083:8083"

livekit:
  ports:
    - "7880:7880"
    - "7881:7881/tcp"
    - "7882:7882/udp"
```

Caddyfile :
```
meet.votre-domaine.tld {
    reverse_proxy localhost:8083
}

livekit.votre-domaine.tld {
    reverse_proxy localhost:7880
}
```

### Option C : Nginx

```nginx
# meet.conf
server {
    listen 443 ssl http2;
    server_name meet.votre-domaine.tld;
    
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    
    location / {
        proxy_pass http://localhost:8083;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# livekit.conf
server {
    listen 443 ssl http2;
    server_name livekit.votre-domaine.tld;
    
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    
    location / {
        proxy_pass http://localhost:7880;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }
}
```

---

## 🔑 Configuration OIDC (Keycloak)

### 1. Créer un Realm
- Nom : `meet` (ou selon votre configuration)

### 2. Créer un Client
- Client ID : `meet`
- Client Protocol : `openid-connect`
- Access Type : `confidential`
- Valid Redirect URIs : `https://meet.votre-domaine.tld/*`
- Web Origins : `https://meet.votre-domaine.tld`

### 3. Récupérer le Client Secret
- Onglet "Credentials"
- Copier le "Secret" dans `.env.common` → `OIDC_RP_CLIENT_SECRET`

---

## ✅ Vérification du Déploiement

```bash
# Vérifier les services
docker compose ps

# Tous les services doivent être "Up" et "healthy"
# - postgresql (healthy)
# - redis (healthy)
# - backend (healthy)
# - celery (up)
# - frontend (up)
# - livekit (up)

# Logs
docker compose logs -f

# Santé du backend
docker compose exec backend python manage.py check

# Test de connexion OIDC
curl -I https://meet.votre-domaine.tld/accounts/login
# Doit rediriger vers votre provider OIDC
```

---

## 🔄 Commandes de Maintenance

### Logs
```bash
# Tous les services
docker compose logs -f

# Service spécifique
docker compose logs -f backend
docker compose logs -f livekit
```

### Redémarrage
```bash
# Redémarrer tous les services
docker compose restart

# Service spécifique
docker compose restart backend
```

### Mise à jour
```bash
# Pull des nouvelles images
docker compose pull

# Redémarrer avec nouvelles images
docker compose up -d

# Migrations de la base
docker compose exec backend python manage.py migrate
```

### Backup de la base de données
```bash
# Dump PostgreSQL
docker compose exec -T postgresql pg_dump -U meet meet > backup_$(date +%Y%m%d).sql

# Restaurer
docker compose exec -T postgresql psql -U meet meet < backup.sql
```

### Arrêter complètement
```bash
docker compose down

# Avec suppression des volumes (⚠️ DANGER)
docker compose down -v
```

---

## 🐛 Troubleshooting

### Backend ne démarre pas
```bash
# Vérifier les logs
docker compose logs backend

# Problèmes courants :
# - Variables d'environnement manquantes
# - Secret key Django invalide
# - Connection Redis/PostgreSQL échouée
```

### Livekit connection failed
```bash
# Vérifier le secret
# Le secret dans .env.common doit correspondre à livekit/livekit-server.yaml

# Vérifier les ports
sudo netstat -tulpn | grep -E '7880|7881|7882'

# Test de connectivité
curl https://livekit.votre-domaine.tld/
```

### OIDC redirect error
```bash
# Vérifier la configuration Keycloak
# - Valid Redirect URIs doit contenir https://meet.votre-domaine.tld/*
# - Client Secret doit correspondre

# Logs backend
docker compose logs backend | grep -i oidc
```

### Performance issues
```bash
# Ressources du serveur
docker stats

# Si besoin, augmenter :
# - RAM disponible
# - Range de ports UDP pour Livekit
```

---

## 📚 Documentation Complémentaire

- [Documentation officielle](https://github.com/suitenumerique/meet/tree/main/docs)
- [Configuration Livekit](https://docs.livekit.io/home/self-hosting/)
- [Django Settings](https://docs.djangoproject.com/en/stable/ref/settings/)
- [Keycloak Documentation](https://www.keycloak.org/documentation)

---

## 🆘 Support

- GitHub Issues : https://github.com/suitenumerique/meet/issues
- Documentation : https://github.com/suitenumerique/meet/tree/main/docs
