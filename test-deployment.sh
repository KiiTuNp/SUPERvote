#!/bin/bash

# Test deployment script for fixed Docker configuration

set -e

echo "🔧 Testing SUPERvote deployment with fixed configuration..."

# Stop any existing containers
echo "Stopping existing containers..."
docker compose -f docker-compose.fixed.yml down --remove-orphans 2>/dev/null || true

# Clean up old images
echo "Cleaning up old images..."
docker system prune -f

# Create necessary directories
echo "Creating directories..."
mkdir -p logs/{nginx,backend,frontend} ssl data

# Use fixed Dockerfiles
echo "Setting up fixed Dockerfiles..."
cp frontend/Dockerfile.fixed frontend/Dockerfile.production
cp backend/Dockerfile.fixed backend/Dockerfile.production

# Build and start services
echo "Building and starting services..."
docker compose -f docker-compose.fixed.yml build --no-cache

echo "Starting services..."
docker compose -f docker-compose.fixed.yml up -d

# Wait for services to start
echo "Waiting for services to start..."
sleep 30

# Check service status
echo "Checking service status..."
docker compose -f docker-compose.fixed.yml ps

# Test health endpoints
echo "Testing health endpoints..."
echo "Backend health:"
curl -f http://localhost:8001/api/health 2>/dev/null && echo "✅ Backend healthy" || echo "❌ Backend not responding"

echo "Frontend health:"
curl -f http://localhost:3000 2>/dev/null && echo "✅ Frontend healthy" || echo "❌ Frontend not responding"

echo ""
echo "🎉 Deployment test complete!"
echo "Frontend: http://localhost:3000"
echo "Backend API: http://localhost:8001"
echo ""
echo "To stop: docker compose -f docker-compose.fixed.yml down"