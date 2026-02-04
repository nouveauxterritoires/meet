# Draft: Dockerfile pour Meet avec deploiement GitHub

## Contexte du projet

**Meet** est une application de visioconference multi-services :
- **Backend**: Django (Python) - `lasuite/meet-backend`
- **Frontend**: Nginx + React - `lasuite/meet-frontend`
- **Services externes requis**: PostgreSQL, Redis, LiveKit, OIDC Provider

**Infrastructure existante** :
- Dockerfiles existants : backend (`Dockerfile`), frontend (`src/frontend/Dockerfile`)
- GitHub Actions existant : `.github/workflows/docker-hub.yml` (push vers Docker Hub)
- Compose existant : `docs/examples/compose/compose.yaml`

## Demande utilisateur

> "J'ai besoin d'un dockerfile complet permettant d'installer le projet meet, compatible avec un deploiement via GitHub"

## Points a clarifier

### 1. Objectif exact
- [ ] Dockerfile pour builder l'application ?
- [ ] Docker Compose adapte a son environnement ?
- [ ] GitHub Action pour CI/CD ?
- [ ] Tout-en-un ?

### 2. Type de deploiement "via GitHub"
- [ ] GitHub Actions (CI/CD pipeline)
- [ ] GitHub Container Registry (ghcr.io au lieu de Docker Hub)
- [ ] GitHub Packages
- [ ] Autre ?

### 3. Architecture cible
- [ ] Mono-conteneur (tout dans un seul Docker) - NON RECOMMANDE
- [ ] Multi-conteneurs via docker-compose
- [ ] Orchestrateur (Kubernetes, Swarm)

### 4. Services externes
- [ ] PostgreSQL : embarque ou externe ?
- [ ] Redis : embarque ou externe ?
- [ ] LiveKit : embarque ou externe ?
- [ ] OIDC : quel provider ?

### 5. Environnement de deploiement
- [ ] Serveur VPS auto-heberge
- [ ] Cloud provider (AWS, GCP, Azure)
- [ ] Platform-as-a-Service (Railway, Render, Fly.io)

## Open Questions

1. Que signifie "Dockerfile complet" pour vous ?
2. Qu'entendez-vous par "compatible avec deploiement via GitHub" ?
3. Quel est votre environnement cible ?
