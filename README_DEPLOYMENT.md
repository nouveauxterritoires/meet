# 🎥 La Suite Meet

Application de visioconférence sécurisée et auto-hébergée.

## 🚀 Installation Rapide

### Prérequis
- Docker Engine 24.0+
- Docker Compose v2
- 4 GB RAM minimum
- Ports : 80, 443, 7881, 7882

### Installation en 1 commande

```bash
./setup.sh
```

Le script interactif va :
- ✅ Générer tous les secrets automatiquement
- ✅ Configurer les domaines, SMTP et OIDC
- ✅ Démarrer tous les services
- ✅ Initialiser la base de données
- ✅ Créer l'utilisateur administrateur

### Installation non-interactive (CI/CD)

```bash
NONINTERACTIVE=true \
MEET_HOST_ENV=meet.example.com \
LIVEKIT_HOST_ENV=livekit.example.com \
KEYCLOAK_HOST_ENV=id.example.com \
SMTP_HOST_ENV=smtp.example.com \
SMTP_USER_ENV=noreply@example.com \
SMTP_PASSWORD_ENV=votre_password \
SMTP_FROM_ENV=noreply@example.com \
OIDC_CLIENT_SECRET_ENV=votre_secret \
./setup.sh --non-interactive
```

## 📚 Documentation Complète

**➡️ Voir [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) pour:**
- Configuration détaillée
- Déploiement via Private Repository
- Configuration reverse proxy (Caddy/Nginx/Traefik)
- Configuration OIDC/Keycloak
- Troubleshooting
- Commandes de maintenance

## ⚙️ Services Requis

| Service | Description | Configuration |
|---------|-------------|---------------|
| PostgreSQL | Base de données | Inclus dans docker-compose |
| Redis | Cache & sessions | Inclus dans docker-compose |
| Livekit | WebRTC SFU | Inclus dans docker-compose |
| **OIDC Provider** | Authentification | **Keycloak requis** |
| **SMTP** | Envoi emails | **Service externe requis** |

## 🌐 Domaines Nécessaires

3 sous-domaines sont requis :
- `meet.votre-domaine.tld` - Application principale
- `livekit.votre-domaine.tld` - Serveur WebRTC
- `id.votre-domaine.tld` - Provider OIDC (Keycloak)

## 🔧 Commandes Utiles

```bash
# Voir les logs
docker compose logs -f

# Redémarrer
docker compose restart

# Arrêter
docker compose down

# Mettre à jour
docker compose pull && docker compose up -d
docker compose exec backend python manage.py migrate

# Backup base de données
docker compose exec -T postgresql pg_dump -U meet meet > backup.sql
```

## 🐛 Problèmes Courants

**Backend ne démarre pas**
```bash
docker compose logs backend
# Vérifier .env.common et .env.postgresql
```

**Livekit connection failed**
```bash
# Vérifier que le secret est identique dans:
# - .env.common (LIVEKIT_API_SECRET)
# - livekit/livekit-server.yaml (keys.meet)
```

**OIDC redirect error**
```bash
# Vérifier dans Keycloak:
# - Client ID = meet
# - Valid Redirect URIs = https://meet.votre-domaine.tld/*
# - Client Secret = celui dans .env.common
```

## 📖 Plus d'Informations

- Documentation officielle : [docs/](./docs/)
- Guide d'installation : [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)
- Changelog : [CHANGELOG.md](CHANGELOG.md)
- Guide de mise à niveau : [UPGRADE.md](UPGRADE.md)

## 🆘 Support

- Issues : https://github.com/suitenumerique/meet/issues
- Documentation : https://github.com/suitenumerique/meet/tree/main/docs

---

**La Suite Numérique** - Suite collaborative souveraine
