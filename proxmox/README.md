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

A continuación se detallan las definiciones completas en YAML de **cada uno de los Stacks individuales** desplegados actualmente en Portainer CE:

### 1. Nginx Proxy Manager (`nginx-proxy-manager`)
```yaml
version: '3.8'
services:
  app:
    image: 'jc21/nginx-proxy-manager:latest'
    restart: unless-stopped
    ports:
      - '80:80'      # Tráfico HTTP web normal
      - '81:81'      # Panel de administración de NPM
      - '443:443'    # Tráfico HTTPS cifrado
    volumes:
      - npm_data:/data
      - npm_letsencrypt:/etc/letsencrypt

volumes:
  npm_data:
  npm_letsencrypt:
```

### 2. AdGuard Home (`adguard`)
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
      - '8082:80/tcp'      # <--- Cambiado de 80:80 a 8082:80
    volumes:
      - adguard_work:/opt/adguardhome/work
      - adguard_conf:/opt/adguardhome/conf

volumes:
  adguard_work:
  adguard_conf:
```

### 3. Vaultwarden (`vaultwarden`)
```yaml
version: '3.3'
services:
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    restart: always
    ports:
      - '8081:80'
    volumes:
      - vaultwarden_data:/data

volumes:
  vaultwarden_data:
```

### 4. Uptime Kuma (`uptime-kuma`)
```yaml
version: '3.3'
services:
  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: uptime-kuma
    restart: always
    dns:
      - 192.168.100.223   # <--- Le enseña a Uptime Kuma a consultar a AdGuard
    ports:
      - '3001:3001'
    volumes:
      - uptime_kuma_data:/app/data

volumes:
  uptime_kuma_data:
```

### 5. Homarr (`homarr`)
```yaml
version: '3.3'
services:
  homarr:
    container_name: homarr
    image: ghcr.io/ajnart/homarr:latest
    restart: unless-stopped
    environment:
      - DISABLE_IMAGE_OPTIMIZATION=true  # 👈 Agrega esta línea
    ports:
      - '7575:7575'
    volumes:
      - homarr_configs:/app/data/configs
      - homarr_icons:/app/public/icons
      - homarr_data:/data

volumes:
  homarr_configs:
  homarr_icons:
  homarr_data:
```

### 6. Jellyfin (`jellyfin`)
```yaml
version: '3.5'
services:
  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: jellyfin
    restart: unless-stopped
    ports:
      - '8096:8096'
    volumes:
      - jellyfin_config:/config
      - jellyfin_cache:/cache
      - /mnt/win_media:/media # 👈 Esta línea conecta los dibujos de Windows con Jellyfin

volumes:
  jellyfin_config:
  jellyfin_cache:
```

### 7. qBittorrent (`qbittorrent`)
```yaml
version: '3.8'
services:
  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:latest
    container_name: qbittorrent
    environment:
      - PUID=0
      - PGID=0
      - TZ=America/Asuncion
      - WEBUI_PORT=8080
      - TORRENTING_PORT=6881
    volumes:
      - qbittorrent_config:/config
      - /mnt/win_media:/downloads # 👈 Guarda directo en el disco de Windows
    ports:
      - '8083:8080'  # 👈 Puerto 8083 hacia afuera (Web UI)
      - '6881:6881'  # Puerto de tráfico P2P
      - '6881:6881/udp'
    restart: unless-stopped

volumes:
  qbittorrent_config:
```

### 8. Arr Stack (`arr-stack`)
```yaml
version: '3.8'
services:
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

  jellyseerr:
    image: fallenbagel/jellyseerr:latest
    container_name: jellyseerr
    environment:
      - LOG_LEVEL=info
      - TZ=America/Asuncion
    ports:
      - '5055:5055'
    volumes:
      - jellyseerr_config:/app/config
    restart: unless-stopped

volumes:
  prowlarr_config:
  radarr_config:
  sonarr_config:
  jellyseerr_config:
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

Reescrituras locales completas (DNS Rewrites) configuradas en AdGuard Home para resolución `*.lab` apuntando a la IP `192.168.100.223`:

| Domain Endpoint | Proxy Forward IP | Port | SSL Configuration | NPM Features Enabled | Role |
| --- | --- | --- | --- | --- | --- |
| `adguard.lab` | `192.168.100.223` | `8082` | HTTP Only | Block Common Exploits | DNS Sinkhole |
| `homarr.lab` | `192.168.100.223` | `7575` | Custom Certificate | Websockets | Dashboard |
| `jellyfin.lab` | `192.168.100.223` | `8096` | HTTP Only | Websockets | Media Server |
| `kuma.lab` | `192.168.100.223` | `3001` | HTTP Only | Websockets | Telemetry UI |
| `prowlarr.lab` | `192.168.100.223` | `9696` | HTTP Only | Block Common Exploits | Indexer Aggregator |
| `radarr.lab` | `192.168.100.223` | `7878` | HTTP Only | Block Common Exploits | Movies Automation |
| `seerr.lab` | `192.168.100.223` | `5055` | Custom Certificate | Websockets | Media Requests |
| `sonarr.lab` | `192.168.100.223` | `8989` | HTTP Only | Block Common Exploits | Series Automation |
| `torrents.lab` | `192.168.100.223` | `8083` | HTTP Only | Websockets | qBittorrent Client |
| `vault.lab` | `192.168.100.223` | `8081` | Custom Certificate | Websockets | Password Manager |

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
