# 🚀 Déploiement en Production SUPERvote

Guide complet pour déployer SUPERvote sur le serveur de production `ubuntu@46.226.104.149`.

## 📋 Prérequis

- Accès SSH configuré pour `ubuntu@46.226.104.149`
- Clé SSH dans `~/.ssh/`
- DNS configuré pour `vote.super-csn.ca` pointant vers `46.226.104.149`

## 🛠️ Scripts Disponibles

### 1. `production-deploy.sh` - Déploiement Initial
Installe et configure SUPERvote sur le serveur de production.

```bash
chmod +x production-deploy.sh
./production-deploy.sh
```

**Ce que fait ce script :**
- ✅ Mise à jour du système Ubuntu 22.04
- ✅ Installation de Docker (méthode officielle)
- ✅ Configuration du firewall UFW
- ✅ Clonage du repository SUPERvote
- ✅ Configuration Docker Compose pour la production
- ✅ Construction et démarrage des conteneurs
- ✅ Configuration SSL avec Let's Encrypt
- ✅ Configuration HTTPS et redirections
- ✅ Service systemd pour auto-start
- ✅ Scripts de gestion

### 2. `production-update.sh` - Mise à Jour
Met à jour l'application déjà déployée.

```bash
./production-update.sh
```

**Fonctionnalités :**
- 🔄 Sauvegarde automatique avant mise à jour
- 📡 Pull du code depuis Git
- 🐳 Reconstruction des conteneurs Docker
- ✅ Vérification de fonctionnement
- 🔙 Restauration automatique en cas d'échec

### 3. `production-manage.sh` - Gestion à Distance
Gère l'application de production depuis votre machine locale.

```bash
./production-manage.sh [commande]
```

**Commandes disponibles :**
- `status` - Statut des services et test HTTPS
- `logs` - Logs en temps réel
- `start` - Démarre l'application
- `stop` - Arrête l'application  
- `restart` - Redémarre l'application
- `update` - Lance une mise à jour
- `backup` - Crée et télécharge une sauvegarde
- `shell` - Ouvre une session SSH

## 🚀 Déploiement Initial Complet

### Étape 1: Vérifier la Connexion SSH
```bash
ssh ubuntu@46.226.104.149
exit
```

### Étape 2: Lancer le Déploiement
```bash
./production-deploy.sh
```

### Étape 3: Vérifier le Déploiement
```bash
./production-manage.sh status
```

## 📊 Gestion Quotidienne

### Vérifier le Statut
```bash
./production-manage.sh status
```

### Voir les Logs
```bash
./production-manage.sh logs
```

### Redémarrer l'Application
```bash
./production-manage.sh restart
```

### Mettre à Jour
```bash
./production-manage.sh update
```

## 🔧 Commandes Directes sur le Serveur

Une fois connecté en SSH (`ssh ubuntu@46.226.104.149`):

### Gestion avec le Script Local
```bash
cd /opt/supervote/SUPERvote
./manage.sh status    # Statut
./manage.sh logs      # Logs
./manage.sh restart   # Redémarrer
./manage.sh update    # Mettre à jour
```

### Commandes Docker Directes
```bash
cd /opt/supervote/SUPERvote
docker compose -f docker-compose.prod.yml ps      # Statut
docker compose -f docker-compose.prod.yml logs -f # Logs
docker compose -f docker-compose.prod.yml restart # Redémarrer
docker compose -f docker-compose.prod.yml up -d --build # Rebuild
```

### Service Systemd
```bash
sudo systemctl status supervote    # Statut
sudo systemctl start supervote     # Démarrer
sudo systemctl stop supervote      # Arrêter
sudo systemctl restart supervote   # Redémarrer
```

## 🛡️ Sécurité et SSL

### Certificat SSL
- **Auto-renouvellement** configuré via cron
- **Test manuel du renouvellement** : `sudo certbot renew --dry-run`
- **Forcer le renouvellement** : `sudo certbot renew --force-renewal`

### Firewall
```bash
sudo ufw status    # Statut du firewall
sudo ufw app list  # Applications autorisées
```

### Ports Ouverts
- **22** : SSH
- **80** : HTTP (redirige vers HTTPS)
- **443** : HTTPS

## 📁 Structure des Fichiers sur le Serveur

```
/opt/supervote/SUPERvote/
├── docker-compose.prod.yml    # Configuration Docker
├── nginx.conf                 # Configuration Nginx
├── backend/
│   └── Dockerfile.prod       # Dockerfile backend
├── frontend/
│   └── Dockerfile.prod       # Dockerfile frontend
├── ssl/                      # Certificats SSL
├── logs/                     # Logs Nginx
└── manage.sh                 # Script de gestion local
```

## 🚨 Dépannage

### Application Non Accessible
```bash
./production-manage.sh status
./production-manage.sh logs
```

### Problèmes SSL
```bash
ssh ubuntu@46.226.104.149
sudo certbot certificates
sudo certbot renew
```

### Redémarrage Complet
```bash
./production-manage.sh stop
./production-manage.sh start
```

### Vérifier les Conteneurs
```bash
ssh ubuntu@46.226.104.149
cd /opt/supervote/SUPERvote
docker compose -f docker-compose.prod.yml ps
docker compose -f docker-compose.prod.yml logs
```

## 📞 Support

- **URL de Production** : https://vote.super-csn.ca
- **Serveur** : ubuntu@46.226.104.149
- **Email SSL** : simon@super-csn.ca
- **Repository** : https://github.com/KiiTuNp/SUPERvote.git

## 🔄 Workflow de Mise à Jour

1. **Développement local** → Push vers GitHub
2. **Mise à jour production** : `./production-manage.sh update`  
3. **Vérification** : `./production-manage.sh status`
4. **Sauvegarde** (si nécessaire) : `./production-manage.sh backup`

---

**✅ Votre application SUPERvote est maintenant prête pour la production !**