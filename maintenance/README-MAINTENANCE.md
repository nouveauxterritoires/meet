# Guide de maintenance de La Suite Meet

Ce guide décrit les procédures de mise à jour et de rollback de votre instance Meet.

## 📋 Prérequis

- Docker et Docker Compose v2 installés
- Accès root ou sudo sur le serveur
- Connexion Internet pour télécharger les images

## 🔄 Mise à jour de Meet

### Procédure standard

```bash
# Mettre à jour vers la dernière version
./update-meet.sh

# Mettre à jour vers une version spécifique
./update-meet.sh v1.2.3
```

### Ce que fait le script

1. **Backup automatique** de la base de données PostgreSQL
2. **Vérification** des notes de version (CHANGELOG/UPGRADE)
3. **Mise à jour** des tags d'images Docker
4. **Téléchargement** des nouvelles images
5. **Redémarrage** des conteneurs
6. **Migration** de la base de données

### Variables d'environnement

Vous pouvez personnaliser le comportement du script :

```bash
# Utiliser un fichier compose différent
COMPOSE_FILE=docker-compose.prod.yaml ./update-meet.sh

# Changer le répertoire de backup
BACKUP_DIR=/data/backups ./update-meet.sh

# Logs dans un répertoire spécifique
LOG_FILE=/var/log/meet/update.log ./update-meet.sh
```

## ⏪ Rollback en cas de problème

Si la mise à jour échoue ou cause des problèmes :

```bash
# Rollback avec le backup le plus récent
./rollback-meet.sh

# Rollback avec un backup spécifique
./rollback-meet.sh backups/meet-db-backup-20260204_120000.sql.gz
```

### Ce que fait le script de rollback

1. **Restaure** le fichier docker-compose.yaml (si backup existe)
2. **Arrête** tous les services
3. **Restaure** la base de données depuis le backup
4. **Redémarre** tous les services

## 📁 Structure des fichiers

```
.
├── docker-compose.yaml       # Configuration principale
├── docker-compose.yaml.bak   # Backup auto du compose (après update)
├── .env                      # Variables d'environnement (secrets)
├── env.d/                    # Configuration détaillée
│   ├── common
│   └── postgresql
├── backups/                  # Backups automatiques
│   └── meet-db-backup-*.sql.gz
├── logs/                     # Logs des opérations
│   ├── update-*.log
│   └── rollback-*.log
├── update-meet.sh           # Script de mise à jour
├── rollback-meet.sh         # Script de rollback
└── .gitignore              # Fichiers à ne pas versionner
```

## 🔍 Vérification post-mise à jour

Après une mise à jour, vérifiez que tout fonctionne :

```bash
# État des conteneurs
docker compose ps

# Logs en temps réel
docker compose logs -f

# Vérifier un service spécifique
docker compose logs backend

# Santé des services
docker compose exec backend python manage.py check
```

## 🛡️ Bonnes pratiques

### Avant chaque mise à jour

1. ✅ Consultez le [CHANGELOG](https://github.com/suitenumerique/meet/blob/main/CHANGELOG.md)
2. ✅ Lisez le guide [UPGRADE](https://github.com/suitenumerique/meet/blob/main/UPGRADE.md)
3. ✅ Planifiez la mise à jour pendant une période de faible trafic
4. ✅ Prévenez les utilisateurs de la maintenance
5. ✅ Gardez un terminal de secours ouvert sur le serveur

### Gestion des backups

```bash
# Lister les backups
ls -lh backups/

# Garder uniquement les 10 derniers backups
ls -t backups/meet-db-backup-*.sql.gz | tail -n +11 | xargs rm -f

# Backup manuel avant opération critique
docker compose exec -T db pg_dump -U meet meet | gzip > backups/manual-backup-$(date +%Y%m%d).sql.gz
```

### Nettoyage Docker

Après plusieurs mises à jour, nettoyez les images inutilisées :

```bash
# Voir l'espace utilisé
docker system df

# Nettoyer les images obsolètes
docker image prune -a

# Nettoyer tout (attention, supprime volumes non utilisés)
docker system prune -a --volumes
```

## 🚨 Dépannage

### La mise à jour échoue

1. Consultez les logs : `cat logs/update-*.log`
2. Vérifiez l'état : `docker compose ps`
3. Regardez les logs : `docker compose logs`
4. Si nécessaire, effectuez un rollback

### Les migrations échouent

```bash
# Voir l'état des migrations
docker compose run --rm backend python manage.py showmigrations

# Forcer une migration spécifique
docker compose run --rm backend python manage.py migrate app_name migration_name

# Revenir à une migration précédente (dangereux !)
docker compose run --rm backend python manage.py migrate app_name migration_name
```

### Service qui ne démarre pas

```bash
# Voir les logs détaillés
docker compose logs --tail=100 service_name

# Redémarrer un service spécifique
docker compose restart service_name

# Recréer un conteneur
docker compose up -d --force-recreate service_name
```

## 📞 Support

- Documentation officielle : https://github.com/suitenumerique/meet
- Issues GitHub : https://github.com/suitenumerique/meet/issues
- La Suite Numérique : https://lasuite.numerique.gouv.fr/

## 📝 Historique des versions

Gardez trace de vos mises à jour dans ce tableau :

| Date | Version | Succès | Notes |
|------|---------|--------|-------|
| 2026-02-04 | v1.0.0 | ✅ | Installation initiale |
|      |         |        |       |
