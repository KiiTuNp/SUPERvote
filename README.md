# Vote Secret - Application de Vote Anonyme pour Assemblées

![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)
![FastAPI](https://img.shields.io/badge/FastAPI-0.116.1-00a373.svg)
![React](https://img.shields.io/badge/React-19.1.1-61dafb.svg)
![MongoDB](https://img.shields.io/badge/MongoDB-8.0-4ea94b.svg)
![Python](https://img.shields.io/badge/Python-3.11+-blue.svg)
![Node.js](https://img.shields.io/badge/Node.js-20+-green.svg)

Une application web moderne pour organiser des votes secrets en assemblée avec suppression automatique des données après génération du rapport PDF.

## 🚀 Fonctionnalités

### 🏛️ Côté Organisateur
- ✅ Création de réunion avec code unique automatique
- ✅ Approbation/rejet des participants en temps réel
- ✅ Création de sondages avec options multiples
- ✅ Minuteur optionnel sur les sondages
- ✅ Lancement et fermeture manuelle des sondages
- ✅ Visualisation des résultats en temps réel
- ✅ Génération de rapport PDF complet
- ✅ Suppression automatique de toutes les données après PDF

### 👥 Côté Participant
- ✅ Rejoindre avec nom + code de réunion
- ✅ Système d'attente d'approbation
- ✅ Vote anonyme (AUCUNE traçabilité)
- ✅ Résultats visibles SEULEMENT après avoir voté
- ✅ Interface claire avec indications de vote secret

### 🔒 Anonymat & Sécurité
- ✅ Votes complètement anonymes (pas de user_id stocké)
- ✅ Participants ne voient pas les résultats avant de voter
- ✅ Suppression automatique de toutes les données après rapport PDF
- ✅ Vote secret préservé à 100%

## 📋 Prérequis Système

### Versions Recommandées (2025)

#### Python 3.11+
```bash
# Ubuntu/Debian
sudo apt update
sudo apt install python3.11 python3.11-venv python3.11-dev python3-pip

# macOS (avec Homebrew)
brew install python@3.11

# Vérifier la version
python3.11 --version
```

#### Node.js 20+
```bash
# Ubuntu/Debian - via NodeSource
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# macOS (avec Homebrew)
brew install node@20

# Vérifier les versions
node --version  # doit être >= 20.0.0
npm --version   # doit être >= 10.0.0
```

#### MongoDB 8.0+
```bash
# Ubuntu/Debian
wget -qO - https://www.mongodb.org/static/pgp/server-8.0.asc | sudo apt-key add -
echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/8.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list
sudo apt-get update
sudo apt-get install -y mongodb-org

# macOS (avec Homebrew)
brew tap mongodb/brew
brew install mongodb-community@8.0

# Démarrer MongoDB
sudo systemctl start mongod  # Linux
brew services start mongodb/brew/mongodb-community@8.0  # macOS

# Vérifier la version
mongod --version
```

#### Yarn (Gestionnaire de paquets Node.js)
```bash
# Installer Yarn globalement
sudo npm install -g yarn

# Vérifier la version
yarn --version
```

## 🛠️ Installation

### 1. Cloner le projet
```bash
git clone https://github.com/KiiTuNp/SUPERvote.git
cd SUPERvote
```

### 2. Configuration Backend (Python/FastAPI)

#### Créer un environnement virtuel Python
```bash
cd backend
python3.11 -m venv venv
```

#### Installer les dépendances Python
```bash
pip install --upgrade pip setuptools wheel
pip install -r requirements.txt
```

#### Configuration de l'environnement
```bash
# Le fichier .env est déjà configuré avec :
# MONGO_URL="mongodb://localhost:27017"
# DB_NAME="vote_secret_db"
```

### 3. Configuration Frontend (React)

#### Installer les dépendances Node.js
```bash
cd ../frontend
yarn install
```

#### Configuration de l'environnement
```bash
# Le fichier .env contient déjà :
# REACT_APP_BACKEND_URL=http://127.0.0.1:8001
# WDS_SOCKET_PORT=443
```

### 4. Démarrage des services

#### Démarrer MongoDB
```bash
# Linux
sudo systemctl start mongod
sudo systemctl enable mongod

# macOS
brew services start mongodb/brew/mongodb-community@8.0

# Vérifier que MongoDB fonctionne
mongo --eval "db.adminCommand('ismaster')"
```

#### Démarrer le Backend
```bash
cd backend
source venv/bin/activate
uvicorn server:app --host 0.0.0.0 --port 8001 --reload
```

#### Démarrer le Frontend
```bash
cd frontend
yarn start
```

## 🏗️ Architecture Technique

### Stack Technologique 2025
- **Backend**: FastAPI 0.116.1 + Python 3.11+
- **Base de données**: MongoDB 8.0 + Motor 3.6.0 (driver async)
- **Frontend**: React 19.1.1 + TypeScript
- **UI**: Tailwind CSS 3.4.18 + Shadcn/UI
- **PDF**: ReportLab 4.3.0
- **Temps réel**: Polling automatique (3 secondes)

### Structure du Projet
```
vote-secret/
├── backend/                 # API FastAPI
│   ├── server.py           # Serveur principal
│   ├── requirements.txt    # Dépendances Python
│   └── .env               # Variables d'environnement
├── frontend/               # Application React
│   ├── src/
│   │   ├── App.js         # Composant principal
│   │   ├── App.css        # Styles globaux
│   │   └── components/ui/ # Composants Shadcn/UI
│   ├── package.json       # Dépendances Node.js
│   └── .env              # Variables d'environnement
└── README.md             # Documentation
```

## 🔧 Dépendances Principales

### Backend (Python)
```txt
fastapi==0.116.1          # Framework web moderne
uvicorn[standard]==0.30.0 # Serveur ASGI
pymongo==4.9.0           # Driver MongoDB
motor==3.6.0             # Driver MongoDB async
pydantic==2.11.7         # Validation des données
reportlab==4.3.0         # Génération PDF
cryptography==43.0.0     # Sécurité
requests==2.32.3         # Requêtes HTTP
```

### Frontend (Node.js)
```json
{
  "react": "^19.1.1",
  "react-dom": "^19.1.1",
  "axios": "^1.8.9",
  "lucide-react": "^0.528.0",
  "tailwindcss": "^3.4.18",
  "react-router-dom": "^7.6.2",
  "@radix-ui/react-*": "^1.2.8+"
}
```

## 🚀 Déploiement

### Production avec Docker (Recommandé)
```dockerfile
# Dockerfile exemple
FROM python:3.11-slim as backend
WORKDIR /app/backend
COPY backend/requirements.txt .
RUN pip install -r requirements.txt
COPY backend/ .
CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8001"]

FROM node:20-alpine as frontend
WORKDIR /app/frontend
COPY frontend/package.json frontend/yarn.lock ./
RUN yarn install --frozen-lockfile
COPY frontend/ .
RUN yarn build
CMD ["yarn", "start"]
```

### Variables d'environnement de production
```bash
# Backend
MONGO_URL=mongodb://mongodb:27017
DB_NAME=vote_secret_production

# Frontend
REACT_APP_BACKEND_URL=https://votre-domaine.com
```

## 🧪 Tests

### Tests Backend
```bash
cd backend
source venv/bin/activate
pytest
```

### Tests Frontend
```bash
cd frontend
yarn test
```

## 📊 Monitoring et Logs

### Logs Backend
```bash
# Voir les logs du serveur
tail -f backend.log

# Logs MongoDB
tail -f /var/log/mongodb/mongod.log
```

### Métriques de performance
- **Base de données**: MongoDB Compass ou MongoDB Atlas
- **Backend**: FastAPI docs automatiques à `/docs`
- **Frontend**: React DevTools

## 🔐 Sécurité

### Bonnes pratiques implémentées
- ✅ Validation des données avec Pydantic
- ✅ Sanitisation des entrées utilisateur
- ✅ CORS configuré correctement
- ✅ Anonymat complet des votes
- ✅ Suppression automatique des données
- ✅ Cryptographie moderne (43.0.0)

### Recommandations additionnelles pour production
- Utiliser HTTPS/TLS
- Configurer un reverse proxy (Nginx)
- Activer l'authentification MongoDB
- Implémenter rate limiting
- Configurer la surveillance des logs

## 🐛 Résolution de problèmes

### Problèmes courants

#### MongoDB ne démarre pas
```bash
# Vérifier les logs
sudo journalctl -u mongod

# Permissions
sudo chown -R mongodb:mongodb /var/lib/mongodb/
sudo chown mongodb:mongodb /tmp/mongodb-27017.sock
```

#### Erreurs Python pip
```bash
# Nettoyer le cache pip
pip cache purge

# Réinstaller les dépendances
pip install --force-reinstall -r requirements.txt
```

#### Erreurs Node.js/Yarn
```bash
# Nettoyer le cache
yarn cache clean

# Supprimer node_modules et réinstaller
rm -rf node_modules package-lock.json
yarn install
```

## 🤝 Contribution

1. Fork le projet
2. Créer une branche feature (`git checkout -b feature/AmazingFeature`)
3. Commit vos changements (`git commit -m 'Add some AmazingFeature'`)
4. Push vers la branche (`git push origin feature/AmazingFeature`)
5. Ouvrir une Pull Request

## 📄 Licence

Ce projet est sous licence MIT. Voir le fichier `LICENSE` pour plus de détails.

## 📞 Support

Pour toute question ou problème :
- Ouvrir une issue GitHub
- Consulter la documentation FastAPI : https://fastapi.tiangolo.com/
- Consulter la documentation React : https://react.dev/

---

**Vote Secret v2.0** - Application moderne de vote anonyme pour assemblées 🗳️
