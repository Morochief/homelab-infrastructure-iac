#!/bin/bash
# ==============================================================================
# docker-setup.sh — Bootstrap Docker + Deploy all stacks in docker-lab LXC
# Se ejecuta automaticamente via Terraform (null_resource provisioner)
# ==============================================================================
set -e

echo ""
echo "=============================================="
echo " 🐳 Homelab Docker Bootstrap"
echo "=============================================="

# ------------------------------------------------------------------------------
# 1. Instalar Docker Engine (metodo oficial)
# ------------------------------------------------------------------------------
echo ""
echo "📦 Instalando Docker Engine..."
apt-get update -qq
apt-get install -y ca-certificates curl gnupg lsb-release

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -qq
apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

systemctl enable docker
systemctl start docker

echo "✅ Docker: $(docker --version)"
echo "✅ Compose: $(docker compose version)"

# ------------------------------------------------------------------------------
# 2. Crear directorios necesarios
# ------------------------------------------------------------------------------
mkdir -p /opt/stacks

# ------------------------------------------------------------------------------
# 3. Desplegar stacks en orden
# ------------------------------------------------------------------------------
echo ""
echo "🚀 Desplegando stacks..."

deploy_stack() {
  local name=$1
  local file="/opt/stacks/${name}.yml"
  echo ""
  echo "  ▶ Desplegando ${name}..."
  if [ -f "$file" ]; then
    docker compose -f "$file" up -d --remove-orphans
    echo "  ✅ ${name} desplegado"
  else
    echo "  ⚠️  Archivo no encontrado: ${file}"
  fi
}

deploy_stack "nginx-proxy-manager"
deploy_stack "adguard"
deploy_stack "vaultwarden"
deploy_stack "uptime-kuma"
deploy_stack "homarr"
deploy_stack "jellyfin"
deploy_stack "qbittorrent"
deploy_stack "arr-stack"

# ------------------------------------------------------------------------------
# 4. Estado final
# ------------------------------------------------------------------------------
echo ""
echo "=============================================="
echo " ✅ Todos los stacks desplegados!"
echo "=============================================="
echo ""
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""
echo "🌐 Accede a Portainer en: http://$(hostname -I | awk '{print $1}'):9000"
echo ""
