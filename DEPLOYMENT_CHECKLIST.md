# 🎯 Checklist Déploiement La Suite Meet

## ✅ Avant de commencer

- [ ] Serveur avec Docker + Docker Compose v2
- [ ] 3 sous-domaines configurés dans le DNS
  - `meet.votre-domaine.tld`
  - `livekit.votre-domaine.tld`
  - `id.votre-domaine.tld`
- [ ] Service SMTP configuré (host, port, credentials)
- [ ] Provider OIDC déployé (Keycloak recommandé)

## 📦 Déploiement via Git (Private Repository)

### 1. Configuration dans votre outil de déploiement

**Type:** Private Repository (with Deploy Key)

```
Repository URL: git@github.com:votre-org/meet.git
Branch: main
Compose File: docker-compose.yaml (à la racine)
```

**Domaines à configurer:**
- Application: `meet.votre-domaine.tld`
- Livekit: `livekit.votre-domaine.tld`

### 2. Variables d'environnement

#### En mode interactif (après déploiement)
```bash
ssh votre-serveur
cd /chemin/vers/meet
./setup.sh
```

#### En mode automatisé (CI/CD)
```bash
NONINTERACTIVE=true \
MEET_HOST_ENV=meet.example.com \
LIVEKIT_HOST_ENV=livekit.example.com \
KEYCLOAK_HOST_ENV=id.example.com \
SMTP_HOST_ENV=smtp.gmail.com \
SMTP_PORT_ENV=587 \
SMTP_USER_ENV=noreply@example.com \
SMTP_PASSWORD_ENV=votre_password \
SMTP_FROM_ENV=noreply@example.com \
OIDC_CLIENT_ID_ENV=meet \
OIDC_CLIENT_SECRET_ENV=votre_secret_keycloak \
./setup.sh --non-interactive
```

### 3. Configuration Keycloak (OIDC)

#### Créer un Realm
1. Nom: `meet`
2. Enabled: `ON`

#### Créer un Client
1. Client ID: `meet`
2. Client Protocol: `openid-connect`
3. Access Type: `confidential`
4. Valid Redirect URIs: `https://meet.votre-domaine.tld/*`
5. Web Origins: `https://meet.votre-domaine.tld`
6. Récupérer le **Client Secret** dans l'onglet **Credentials**

#### Configurer les scopes
- openid: ✅ Activé
- email: ✅ Activé
- profile: ✅ Activé

### 4. Firewall

```bash
# UFW (Ubuntu/Debian)
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 443/udp
sudo ufw allow 7881/tcp
sudo ufw allow 7882/udp
sudo ufw enable

# Ou avec le script
./setup.sh  # Répondre "y" à la question firewall
```

### 5. Configuration Reverse Proxy

#### Option A: Traefik (labels déjà configurés)
Les labels Traefik sont déjà dans `docker-compose.yaml`.
Ajoutez simplement le réseau Traefik si nécessaire.

#### Option B: Caddy
```caddy
meet.votre-domaine.tld {
    reverse_proxy localhost:8083
}

livekit.votre-domaine.tld {
    reverse_proxy localhost:7880
}
```

Exposez les ports dans docker-compose.yaml:
```yaml
frontend:
  ports:
    - "8083:8083"

livekit:
  ports:
    - "7880:7880"
```

#### Option C: Nginx
Voir `DEPLOYMENT_GUIDE.md` pour la configuration complète.

## 🔍 Vérification

```bash
# Services
docker compose ps
# Tous doivent être "Up" et "healthy"

# Logs
docker compose logs -f

# Test OIDC
curl -I https://meet.votre-domaine.tld/accounts/login
# Doit rediriger vers Keycloak

# Test Livekit
curl https://livekit.votre-domaine.tld/
# Doit retourner une réponse JSON
```

## 📝 Post-Installation

1. [ ] Connexion admin: `https://meet.votre-domaine.tld/admin`
2. [ ] Test de création de salle
3. [ ] Test d'invitation par email
4. [ ] Test de visioconférence
5. [ ] Configurer le backup automatique:
   ```bash
   # Crontab
   0 2 * * * docker compose -f /chemin/vers/meet/docker-compose.yaml exec -T postgresql pg_dump -U meet meet > /backup/meet_$(date +\%Y\%m\%d).sql
   ```

## 🔄 Maintenance

```bash
# Mise à jour
cd /chemin/vers/meet
git pull
docker compose pull
docker compose up -d
docker compose exec backend python manage.py migrate

# Backup
docker compose exec -T postgresql pg_dump -U meet meet > backup.sql

# Restaurer
docker compose exec -T postgresql psql -U meet meet < backup.sql

# Redémarrage
docker compose restart

# Logs
docker compose logs -f [service]
```

## 🆘 Problèmes Courants

### Backend ne démarre pas
```bash
docker compose logs backend
# Vérifier .env.common et .env.postgresql
```

### OIDC ne fonctionne pas
1. Vérifier Client ID et Secret dans `.env.common`
2. Vérifier Redirect URIs dans Keycloak
3. Vérifier que `KEYCLOAK_HOST` est accessible

### Livekit connection failed
1. Vérifier que `LIVEKIT_API_SECRET` est identique dans:
   - `.env.common`
   - `livekit/livekit-server.yaml`
2. Vérifier que les ports 7881/tcp et 7882/udp sont ouverts
3. Vérifier `livekit/livekit-server.yaml` → `keys.meet`

### Emails non envoyés
1. Vérifier configuration SMTP dans `.env.common`
2. Tester avec: `docker compose exec backend python manage.py sendtestemail admin@example.com`
3. Vérifier les logs: `docker compose logs backend | grep -i email`

## 📚 Documentation

- Guide complet: [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)
- README: [README_DEPLOYMENT.md](README_DEPLOYMENT.md)
- Documentation officielle: https://github.com/suitenumerique/meet/tree/main/docs
