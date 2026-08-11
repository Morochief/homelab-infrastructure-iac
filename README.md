# 📑 Documentation V2.1: Multi-Layer Enterprise Homelab, Automation Pipeline & Microservices Architecture

## 📋 Executive Summary

Despliegue integral, orquestación y resolución de incidentes (*Troubleshooting*) de una infraestructura de virtualización anidada (*Nested Virtualization*), orquestación de microservicios en Docker, almacenamiento distribuido SMB/CIFS, y un pipeline de automatización multimedia (Stack *Arr*).

El proyecto abarca desde la preparación a bajo nivel del Kernel del anfitrión (Windows 11), pasando por hipervisores L1 (VirtualBox) y L2 (Proxmox VE), hasta el montaje de volúmenes compartidos en contenedores LXC no privilegiados mediante **Bind Mounts**. Incorpora proxies inversos con terminación SSL, telemetría en tiempo real, gestión de credenciales cifradas y bypass de protecciones Anti-DDoS (Cloudflare) mediante simulación de navegador (FlareSolverr).

---

## 🏗️ Architecture Stack Diagram

```text
[ Physical Host: Windows 11 (24GB RAM) ] ──────── (IP Static: 192.168.100.8)
       │ (SMB Share: \\192.168.100.8\Peliculas)
[ Hypervisor L1: Oracle VirtualBox ] ──────────── (Resources: 4 vCores, 16GB RAM)
       │ (Bridged Adapter vmbr0: 192.168.100.x)
[ Hypervisor L2: Proxmox VE 8.x/9.x ] ─────────── (IP: 192.168.100.222:8006)
       │ (CIFS Mounted: /mnt/win_media)
       │ ─── Bind Mount (pct set 100 -mp0) ───┐
[ Guest OS: LXC CT 100 (Ubuntu 24.04) ] ◄─────┘   (IP: 192.168.100.223, 8GB RAM, 4 vCores)
       │ (Internal Directory: /mnt/win_media)
       │ (Docker Engine & Portainer CE)
┌──────┴──────────────────────────────────────────────────────────────────────────────┐
│                                INFRASTRUCTURE TIER                                  │
│ [ NGINX Proxy Mgr ]  [ AdGuard Home ]  [ Uptime Kuma ]  [ Vaultwarden ]  [ Homarr ] │
│   Ports: 80, 443, 81   Ports: 53, 8082   Port: 3001       Port: 8081      Port: 7575 │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                MEDIA & AUTOMATION TIER                              │
│ [ Jellyfin ]  [ qBittorrent ]  [ Prowlarr ]  [ Radarr ]  [ Sonarr ]  [ FlareSolverr ]
│ Port: 8096      Port: 8083      Port: 9696    Port: 7878  Port: 8989    Port: 8191  │
│      │               │               │             │           │             │      │
└──────┴───────────────┴───────────────┴─────────────┴───────────┴─────────────┴──────┘
       └────────────────── Docker Volume: /mnt/win_media:/media ◄─────────────────────┘
```

---

## 🛠️ Phase 1: Host Operating System & Network Hardening

### 1. Disabling Hyper-V Interference

Para asegurar que VirtualBox ejecute virtualización de hardware completa (`VT-x/AMD-V`) y evitar la interceptación de subprocesos por parte de Windows:

```powershell
# Disable Hyper-V Features & Guard
Disable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
bcdedit /set hypervisorlaunchtype off
```

### 2. Network Hardening: Windows Static IP Assignment Fix

Conflicto `MSFT_NetIPAddress already exists / Error 87` resuelto mediante Netsh Engine para sobrescribir el lease DHCP:

```powershell
# 1. Convert DHCP lease to Static IP
netsh interface ipv4 set address name="Ethernet 2" static 192.168.100.8 255.255.255.0 192.168.100.1

# 2. Assign Primary DNS (AdGuard LXC) & Secondary DNS
Set-DnsClientServerAddress -InterfaceAlias "Ethernet 2" -ServerAddresses ("192.168.100.223", "1.1.1.1")
```

---

## ⚙️ Phase 2: Proxmox VE (L2) Optimization & Storage Provisioning

### 1. Enterprise Repository Fix (401 Unauthorized Bypass)

```bash
# Disable Enterprise repos and enable Community No-Subscription
grep -rl "enterprise.proxmox.com" /etc/apt/ | xargs sed -i 's/^/#/'
echo "deb http://download.proxmox.com/debian/pve trixie pve-no-subscription" > /etc/apt/sources.list.d/pve-no-sub.list
apt update && apt dist-upgrade -y
```

### 2. LXC Container Deployment & Hot Disk Extension

Contenedor no privilegiado configurado con `Nesting=1` y `CIFS=1`. Expansión de disco en caliente tras volcado de logs (`no space left on device`):

```bash
pct resize 100 rootfs +15G
docker system prune -a --volumes -f
```

---

## 📁 Phase 3: High-Performance Storage Architecture (SMB + LXC Bind Mount)

Resolución de error `permission denied` en LXC no privilegiado al intentar montaje directo. Se implementó un montaje a nivel de hipervisor pasado por Bind Mount.

```bash
# 1. Mount SMB Share on Proxmox Host (SMB 3.0)
mkdir -p /mnt/win_media
mount -t cifs //192.168.100.8/Peliculas /mnt/win_media -o username=Morochief,password="Bc135603.",iocharset=utf8,vers=3.0

# 2. Bind Mount Share into LXC Container (CT 100)
pct set 100 -mp0 /mnt/win_media,mp=/mnt/win_media

# 3. Persistence in Proxmox /etc/fstab
//192.168.100.8/Peliculas /mnt/win_media cifs username=Morochief,password=Bc135603.,iocharset=utf8,vers=3.0 0 0
```

---

## 🚨 Phase 4: Compute Scaling & Kernel Panic Mitigation (Troubleshooting)

### Incident Report: `nmi_backtrace_stall_check` (CPU Hard Lockup)

* **Síntoma:** Colapso total del Proxmox L2 al reproducir un archivo `.webm` en Jellyfin. Caída de red y congelamiento del servidor.
* **Root Cause:** El contenedor LXC forzó transcodificación por software (FFmpeg) de un formato no soportado. Esto saturó los 5 vCores sobreprovisionados en VirtualBox, causando colisión de hilos con el host Windows y un `Kernel Panic` por falta de respuesta del CPU (`CPU stall`).
* **Resolución (Resource Tuning):**
1. Reajuste de vCores en VirtualBox a **4 CPUs** (evitando la zona roja de colisión).
2. Ajuste de memoria del Hypervisor L1 a **16 GB RAM** (dejando 8 GB para el host).
3. Reasignación de recursos en CT 100 (LXC): `8 GB RAM`, `2 GB Swap`, `4 Cores`.

---

## 🛳️ Phase 5: Complete Microservices Declarative Stacks (Docker Compose)

A continuación se detallan las definiciones completas en YAML de **cada uno de los Stacks** desplegados en Portainer CE:

### Stack 1: Core Management & Reverse Proxy Tier (`infrastructure-core`)

```yaml
version: '3.8'
services:
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    ports:
      - '9000:9000'
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    restart: unless-stopped

  nginx-proxy-manager:
    image: jc21/nginx-proxy-manager:latest
    container_name: nginx-proxy-manager-app-1
    ports:
      - '80:80'
      - '81:81'
      - '443:443'
    volumes:
      - npm_data:/data
      - npm_letsencrypt:/etc/letsencrypt
    restart: unless-stopped

volumes:
  portainer_data:
  npm_data:
  npm_letsencrypt:
```

---

### Stack 2: Security & Network Tier (`security-stack`)

```yaml
version: '3.8'
services:
  adguardhome:
    image: adguard/adguardhome:latest
    container_name: adguardhome
    ports:
      - '53:53/tcp'
      - '53:53/udp'
      - '8082:80'
      - '3000:3000'
    volumes:
      - adguard_work:/opt/adguardhome/work
      - adguard_conf:/opt/adguardhome/conf
    restart: unless-stopped

  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    environment:
      - WEBSOCKET_ENABLED=true
    ports:
      - '8081:80'
    volumes:
      - vaultwarden_data:/data
    restart: unless-stopped

volumes:
  adguard_work:
  adguard_conf:
  vaultwarden_data:
```

---

### Stack 3: Observability & Dashboard Tier (`monitoring-stack`)

```yaml
version: '3.8'
services:
  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: uptime-kuma
    ports:
      - '3001:3001'
    volumes:
      - uptime_kuma_data:/app/data
    restart: unless-stopped

  homarr:
    image: ghcr.io/ajnart/homarr:latest
    container_name: homarr
    ports:
      - '7575:7575'
    volumes:
      - homarr_configs:/app/data/configs
      - homarr_icons:/app/public/icons
      - homarr_data:/data
    restart: unless-stopped

volumes:
  uptime_kuma_data:
  homarr_configs:
  homarr_icons:
  homarr_data:
```

---

### Stack 4: Media Processing & Automation Pipeline (`arr-stack`)

```yaml
version: '3.8'
services:
  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: jellyfin
    ports:
      - '8096:8096'
    volumes:
      - jellyfin_config:/config
      - /mnt/win_media:/media
    restart: unless-stopped

  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:latest
    container_name: qbittorrent
    environment:
      - PUID=0
      - PGID=0
      - TZ=America/Asuncion
    ports:
      - '6881:6881'
      - '6881:6881/udp'
      - '8083:8080'
    volumes:
      - qbittorrent_config:/config
      - /mnt/win_media:/downloads
    restart: unless-stopped

  prowlarr:
    image: lscr.io/linuxserver/prowlarr:latest
    container_name: prowlarr
    environment:
      - PUID=0
      - PGID=0
      - TZ=America/Asuncion
    ports:
      - '9696:9696'
    volumes:
      - prowlarr_config:/config
    restart: unless-stopped

  radarr:
    image: lscr.io/linuxserver/radarr:latest
    container_name: radarr
    environment:
      - PUID=0
      - PGID=0
      - TZ=America/Asuncion
    ports:
      - '7878:7878'
    volumes:
      - radarr_config:/config
      - /mnt/win_media:/media
    restart: unless-stopped

  sonarr:
    image: lscr.io/linuxserver/sonarr:latest
    container_name: sonarr
    environment:
      - PUID=0
      - PGID=0
      - TZ=America/Asuncion
    ports:
      - '8989:8989'
    volumes:
      - sonarr_config:/config
      - /mnt/win_media:/media
    restart: unless-stopped

  flaresolverr:
    image: ghcr.io/flaresolverr/flaresolverr:latest
    container_name: flaresolverr
    environment:
      - LOG_LEVEL=info
      - TZ=America/Asuncion
    ports:
      - '8191:8191'
    restart: unless-stopped

volumes:
  jellyfin_config:
  qbittorrent_config:
  prowlarr_config:
  radarr_config:
  sonarr_config:
```

---

## 🛡️ Phase 6: WebUI Hardening & Proxy Resolution

### Incident Report: qBittorrent HTTP 401 Unauthorized via NPM

* **Problema:** Nginx Proxy Manager devolvía `Unauthorized` al acceder mediante `torrents.lab`.
* **Root Cause:** qBittorrent bloquea cabeceras HTTP de proxy inverso por defecto y previene CSRF.
* **Resolución (Bash Script Injection):** Búsqueda y parcheo del `qBittorrent.conf` en el volumen de Docker.

```bash
CONF_FILE=$(find /var/lib/docker/volumes -name "qBittorrent.conf" 2>/dev/null | head -n 1)
sed -i '/WebUI\\HostHeaderValidation/d' "$CONF_FILE"
sed -i '/WebUI\\CSRFProtection/d' "$CONF_FILE"
sed -i '/\[Preferences\]/a WebUI\\HostHeaderValidation=false\nWebUI\\CSRFProtection=false' "$CONF_FILE"
docker restart qbittorrent
```

---

## 🌐 Phase 7: API Integration & Anti-DDoS Circumvention (FlareSolverr)

Para evadir los desafíos JavaScript de Cloudflare (`Blocked by CloudFlare Protection`) en indexadores Torrent de nivel Tier-1 (ej. 1337x):

1. **Despliegue de FlareSolverr:** Integrado en el Stack en el puerto `8191`.
2. **Vinculación en Prowlarr:** Configurado como *Indexer Proxy* (`http://flaresolverr:8191`).
3. **Sincronización de API (Full Sync):** Las *API Keys* de Radarr y Sonarr inyectadas en Prowlarr para actualización de Indexers en tiempo real (Zero-touch configuration).
4. **qBittorrent Mapped:** Configurado como Download Client primario en Radarr/Sonarr.

---

## 🗺️ Phase 8: Domain Routing & SSL Mapping Matrix (NPM + AdGuard)

Reescrituras locales completas en AdGuard Home para resolución `*.lab` apuntando a la IP `192.168.100.223`.

| Domain Endpoint | Proxy Forward IP | Port | NPM Features Enabled | Role |
| --- | --- | --- | --- | --- |
| `vault.lab` | `192.168.100.223` | `8081` | Websockets, Custom SSL | Password Manager |
| `kuma.lab` | `192.168.100.223` | `3001` | Websockets | Telemetry UI |
| `adguard.lab` | `192.168.100.223` | `8082` | Block Common Exploits | DNS Sinkhole |
| `jellyfin.lab` | `192.168.100.223` | `8096` | Websockets | Media Server |
| `torrents.lab` | `192.168.100.223` | `8083` | Websockets | qBittorrent Client |
| `prowlarr.lab` | `192.168.100.223` | `9696` | Block Common Exploits | Indexer Aggregator |
| `radarr.lab` | `192.168.100.223` | `7878` | Block Common Exploits | Movies Automation |
| `sonarr.lab` | `192.168.100.223` | `8989` | Block Common Exploits | Series Automation |

---

## 📈 Phase 9: Real-Time Monitoring Matrix (Uptime Kuma)

| Monitor Name | Type | Target URL / Endpoint | Configuration Profile |
| --- | --- | --- | --- |
| **Proxmox VE Hypervisor** | HTTP(s) | `https://192.168.100.222:8006` | Ignore TLS/SSL Error |
| **Portainer Engine** | HTTP(s) | `http://192.168.100.223:9000` | Standard HTTP Check |
| **Proxy Reverse (NPM)** | HTTP(s) | `http://192.168.100.223:81` | Standard HTTP Check |
| **Router Default Gateway** | Ping | `192.168.100.1` | ICMP Echo Request |
| **Vaultwarden Backend** | HTTP(s) | `https://vault.lab` | Ignore TLS/SSL Error |
| **Jellyfin Streaming** | HTTP(s) | `http://jellyfin.lab` | HTTP Response Check |
| **Automation Prowlarr** | HTTP(s) | `http://prowlarr.lab` | HTTP Response Check |
| **Automation Radarr** | HTTP(s) | `http://radarr.lab` | HTTP Response Check |
| **Automation Sonarr** | HTTP(s) | `http://sonarr.lab` | HTTP Response Check |

---

## 🔑 Credential & Service Index (Master Audit)

| Service Name | Web Endpoint | Master User | Password/Key | Role / Description |
| --- | --- | --- | --- | --- |
| **Proxmox VE** | `https://192.168.100.222:8006` | `root` | `Mjjagkaz012.3n3r01995*` | L2 Virtualization Hypervisor |
| **LXC Shell** | SSH / PVE Console | `root` | `Mjjagkaz012.3n3r01995*` | Docker Host Environment |
| **Windows SMB** | `\\192.168.100.8\Peliculas` | `Morochief` | `Bc135603.` | L0 Physical Storage Server |
| **Portainer CE** | `http://192.168.100.223:9000` | `admin` | `Mjjagkaz012.3n3r01995*` | Container Orchestrator |
| **AdGuard Home** | `http://adguard.lab` | `admin` | `Mjjagkaz012.3n3r01995*` | Network DNS / Rewriter |
| **Nginx Proxy** | `http://192.168.100.223:81` | `admin` | `Mjjagkaz012.3n3r01995*` | Reverse Proxy Router |
| **Uptime Kuma** | `http://kuma.lab` | `admin` | *(Custom Master)* | Sensor Matrix |
| **Vaultwarden** | `https://vault.lab` | `root` | `Mjjagkaz012.3n3r01995*` | Password Cipher Manager |
| **Jellyfin** | `http://jellyfin.lab` | `root` | `Mjjagkaz012.3n3r01995*` | Media Streaming Platform |
| **qBittorrent** | `http://torrents.lab` | `admin` | `Mjjagkaz012.3n3r01995*` | Torrent Client Daemon |
| **Prowlarr** | `http://prowlarr.lab` | `admin` | `Mjjagkaz012.3n3r01995*` | Tracker Aggregator |
| **Radarr** | `http://radarr.lab` | `admin` | `Mjjagkaz012.3n3r01995*` | Movies Logic & Automation |
| **Sonarr** | `http://sonarr.lab` | `admin` | `Mjjagkaz012.3n3r01995*` | Series Logic & Automation |
