# 📑 Documentation: Multi-Layer Enterprise Homelab & Microservices Architecture

## 📋 Executive Summary

Despliegue de una infraestructura de virtualización anidada, orquestación de contenedores y servicios de red locales desde cero. El proyecto abarca desde la preparación del Kernel del sistema anfitrión (Windows 11) hasta la implementación de un Proxy Inverso con SSL autofirmado, resolución DNS local personalizada, monitoreo en tiempo real con matriz de estados activa y gestor de contraseñas privado, incluyendo la resolución técnica de conflictos de puertos, interfaces IPv6 y políticas de seguridad del navegador.

---

## 🏗️ Architecture Stack

```text
[ Physical Host: Windows 11 ]
       │ (VT-x Enabled / Hyper-V & IPv6 Disabled)
[ Hypervisor L1: Oracle VirtualBox ]
       │ (Bridged Adapter vmbr0: 192.168.100.x)
[ Hypervisor L2: Proxmox VE 8.x ] ─── (IP: 192.168.100.222:8006)
       │ (Unprivileged LXC Container + Nesting)
[ Guest OS: Ubuntu 24.04 LTS ] ─────── (IP: 192.168.100.223)
       │ (Docker Engine v29+ & Portainer CE)
┌──────┴──────────────────────────────────────────────────────────────────┐
[ NGINX Proxy Manager ]  [ AdGuard Home DNS ]  [ Uptime Kuma ]  [ Vaultwarden ]
  Ports: 80, 443, 81       Ports: 53, 8082       Port: 3001       Port: 8081

```

---

## 🛠️ Step-by-Step Implementation

### Phase 1: Host Operating System & Nested Virtualization

#### 1. Disabling Hyper-V Interference

Para permitir que VirtualBox ejecute virtualización de hardware completa para Proxmox VE, se deshabilitaron las capas de aislamiento de Windows en PowerShell (Administrador):

```powershell
# Disable Hyper-V Features
Disable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All

# Disable Virtual Machine Platform & Guard
bcdedit /set hypervisorlaunchtype off
```

#### 2. VirtualBox VM Configuration

* **Name:** `Proxmox-VE`
* **Type:** Linux / Debian (64-bit)
* **RAM:** 4096 MB | **CPU:** 2 Cores
* **Nested VT-x/AMD-V:** Activated (`System ➔ Processor ➔ Enable Nested VT-x/AMD-V`)
* **Network:** Adapter 1 ➔ **Bridged Adapter** (Puente) asignado a la interfaz física.

---

### Phase 2: Proxmox VE Installation & Initial Tuning

#### 1. PVE Base Setup

* **IP Address:** `192.168.100.222/24`
* **Gateway:** `192.168.100.1`
* **FQDN:** `proxmox.home.lab`
* **Root Password:** `<YOUR_ROOT_PASSWORD_HERE>`

#### 2. Community Repositories (No-Subscription)

En la consola de Proxmox PVE:

```bash
# Disable Enterprise Repo
rm -f /etc/apt/sources.list.d/pve-enterprise.list

# Add No-Subscription Repo
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-no-sub.list

# Update Package Index
apt update && apt dist-upgrade -y
```

---

### Phase 3: LXC Container Deployment (Ubuntu 24.04)

#### 1. Container Configuration Parameters

* **CT ID:** `100` | **Hostname:** `docker-lab`
* **Password:** `<YOUR_CONTAINER_PASSWORD_HERE>`
* **Template:** `ubuntu-24.04-standard`
* **Disk:** 8 GiB (local-lvm)
* **CPU:** 1 Core | **Memory:** 1024 MiB RAM | 512 MiB Swap
* **Network:** Bridge `vmbr0`, IPv4: **DHCP** (Asignada: `192.168.100.223`)
* **Options:** **`Nesting=1`** habilitado (Crucial para ejecutar Docker dentro de LXC).

---

### Phase 4: Docker Engine & Portainer CE Installation

#### 1. OS Preparation & Package Installation

En la terminal del contenedor `docker-lab`:

```bash
# Update System Packages & Install Dependencies
apt update && apt install -y curl

# Install Docker via Official Automated Script
curl -fsSL https://get.docker.com | sh

# Enable Docker Service on Boot
systemctl enable --now docker
```

#### 2. Deploying Portainer CE Management UI

```bash
docker run -d \
  -p 9000:9000 \
  --name=portainer \
  --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest
```

---

### Phase 5: Microservices Stack & Advanced Troubleshooting

#### 1. Conflict Resolution: `systemd-resolved` Port 53 Collision

Al desplegar AdGuard Home, el puerto 53 de DNS estaba acaparado por Ubuntu:

```bash
# Disable DNS Stub Listener in Systemd Configuration
sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf

# Re-link resolv.conf & Restart Resolution Service
ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
systemctl restart systemd-resolved
```

#### 2. Conflict Resolution: Port 80 Collision (Nginx Proxy Manager vs AdGuard)

Al intentar levantar Nginx Proxy Manager, ocurrió un conflicto de binding en el puerto 80.

* **Solución:** Re-mapeo del puerto Web Admin de AdGuard Home de `80:80` a `8082:80`, liberando los puertos `80` y `443` para Nginx Proxy Manager.

---

### Phase 6: Stack Definitions (Portainer Docker Compose)

#### Stack 1: AdGuard Home (Network DNS Filter)

```yaml
version: '3.3'
services:
  adguardhome:
    image: adguard/adguardhome:latest
    container_name: adguardhome
    restart: always
    ports:
      - '53:53/tcp'
      - '53:53/udp'
      - '3000:3000/tcp'
      - '8082:80/tcp'
    volumes:
      - adguard_work:/opt/adguardhome/work
      - adguard_conf:/opt/adguardhome/conf

volumes:
  adguard_work:
  adguard_conf:
```

#### Stack 2: Nginx Proxy Manager (Reverse Proxy)

```yaml
version: '3.8'
services:
  app:
    image: 'jc21/nginx-proxy-manager:latest'
    restart: unless-stopped
    ports:
      - '80:80'
      - '81:81'
      - '443:443'
    volumes:
      - npm_data:/data
      - npm_letsencrypt:/etc/letsencrypt

volumes:
  npm_data:
  npm_letsencrypt:
```

#### Stack 3: Uptime Kuma (Service Monitoring)

```yaml
version: '3.3'
services:
  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: uptime-kuma
    restart: always
    dns:
      - 192.168.100.223 # Resolución de dominios .lab internos
    ports:
      - '3001:3001'
    volumes:
      - uptime_kuma_data:/app/data

volumes:
  uptime_kuma_data:
```

#### Stack 4: Vaultwarden (Password Manager with Security Hardening)

```yaml
version: '3.3'
services:
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    restart: always
    environment:
      - SIGNUPS_ALLOWED=false # Hardening: Desactiva el registro tras crear admin
    ports:
      - '8081:80'
    volumes:
      - vaultwarden_data:/data

volumes:
  vaultwarden_data:
```

---

### Phase 7: SSL Certificate Generation & Reverse Proxy Setup

#### 1. OpenSSL Local Certificate Generation

Para solucionar la restricción **`Subtle Crypto API`** de Vaultwarden y clientes móviles de Bitwarden (que exigen HTTPS obligatoriamente):

```bash
mkdir -p /opt/certs && cd /opt/certs
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout vault.key -out vault.crt \
  -subj "/CN=vault.lab/O=Homelab/OU=DevOps"
```

#### 2. Nginx Proxy Manager & Custom SSL Mapping

1. Carga de par de llaves `vault.key` y `vault.crt` en **NPM ➔ Custom Certificates**.
2. Configuración de Hosts en NPM:

| Domain | Forward Host IP | Forward Port | Options Enabled |
| --- | --- | --- | --- |
| `vault.lab` | `192.168.100.223` | `8081` | Websockets, Force SSL (Custom SSL Certificate) |
| `kuma.lab` | `192.168.100.223` | `3001` | Websockets Support |
| `adguard.lab` | `192.168.100.223` | `8082` | Block Common Exploits |

---

### Phase 8: DNS Rewrites & Host Resolution Troubleshooting

#### 1. AdGuard Home DNS Rewrites

En **AdGuard Home ➔ Filtros ➔ Reescrituras DNS**:

* `vault.lab` ➔ `192.168.100.223`
* `kuma.lab` ➔ `192.168.100.223`
* `adguard.lab` ➔ `192.168.100.223`

#### 2. Windows IPv6 Override Troubleshooting

* **Síntoma:** `nslookup vault.lab` devolvía `UnKnown / fe80::1` y `Non-existent domain`.
* **Causa raíz:** Windows utilizaba la pila IPv6 predeterminada antes que el servidor DNS IPv4 asignado.
* **Resolución:**
1. Desactivar **TCP/IPv6** en el adaptador de red (`ncpa.cpl`).
2. Forzar vaciado de memoria caché DNS: `ipconfig /flushdns`.
3. Diagnóstico exitoso mediante `nslookup vault.lab` (Responde: `192.168.100.223`).

---

### Phase 9: Real-Time Monitoring Matrix (Uptime Kuma)

Se implementó la matriz completa de monitoreo con estado **100% OPERATIVO (UP)** e inspección activa:

| Monitor Name | Type | Target URL / Host | Specific Configuration |
| --- | --- | --- | --- |
| **Portainer Panel** | HTTP(s) | `http://192.168.100.223:9000` | Default HTTP Check |
| **Proxmox VE** | HTTP(s) | `https://192.168.100.222:8006` | `Ignore TLS/SSL error` enabled |
| **Proxy Reverse (NPM)** | HTTP(s) | `http://192.168.100.223:81` | Default HTTP Check |
| **Router Principal** | Ping | `192.168.100.1` | ICMP Echo Request |
| **Servidor DNS AdGuard** | HTTP(s) | `http://192.168.100.223:8082` | Internal Web Check |
| **Vaultwarden SSL** | HTTP(s) | `https://vault.lab` | `Ignore TLS/SSL error` enabled |

---

## 🔑 Credential & Service Index (Internal Homelab Audit)

> **Nota de seguridad:** Las contraseñas reales se han reemplazado por placeholders para su publicación en el repositorio.

| Service | Protocol / Access Point | Username | Password / Notes |
| --- | --- | --- | --- |
| **Proxmox VE** | `https://192.168.100.222:8006` | `root` | `<YOUR_PROXMOX_PASSWORD>` |
| **LXC Shell** | Proxmox Console / SSH | `root` | `<YOUR_LXC_PASSWORD>` |
| **Portainer CE** | `http://192.168.100.223:9000` | `admin` | `<YOUR_PORTAINER_PASSWORD>` |
| **AdGuard Home** | `http://adguard.lab` / `:8082` | `admin` | `<YOUR_ADGUARD_PASSWORD>` |
| **Nginx Proxy Mgr** | `http://192.168.100.223:81` | `admin` | `<YOUR_NPM_PASSWORD>` |
| **Uptime Kuma** | `http://kuma.lab` | `admin` | `<YOUR_KUMA_PASSWORD>` |
| **Vaultwarden** | `https://vault.lab` | `admin` | `<YOUR_VAULTWARDEN_PASSWORD>` |
