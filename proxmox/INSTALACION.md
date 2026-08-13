# 🚀 Guia Completa — Proxmox Bare Metal + Homelab desde Cero

> **Objetivo:** Instalar Proxmox VE en un SSD de 256 GB, configurar el entorno y desplegar
> automáticamente los 13 contenedores Docker con un solo comando de Terraform.
>
> **Desde:** Notebook separada en la misma red local (`192.168.100.x`)  
> **Servidor:** PC con SSD dedicado de 256 GB para Proxmox

---

## 📋 Resumen del proceso

```
FASE 1 → Preparar USB booteable con Proxmox ISO
FASE 2 → Instalar Proxmox en el SSD de 256 GB
FASE 3 → Post-instalación: repos, red, SSH
FASE 4 → Crear token API para Terraform
FASE 5 → Instalar Terraform en la notebook
FASE 6 → Configurar terraform.tfvars con tus credenciales
FASE 7 → terraform apply (crea LXC + instala Docker + despliega stacks)
FASE 8 → Configuración manual post-deploy (AdGuard + NPM + Uptime Kuma)
```

---

## ⚙️ FASE 1 — Preparar el USB booteable

### Requisitos
- USB de mínimo 4 GB
- Herramienta para grabar la ISO: **Rufus** (Windows) o **Balena Etcher** (multiplataforma)

### Pasos

**1. Descargar la ISO de Proxmox VE:**
```
https://www.proxmox.com/en/downloads/proxmox-virtual-environment/iso
```
Descargar la versión más reciente (ej. `proxmox-ve_8.4-1.iso`)

**2. Grabar con Rufus (recomendado en Windows):**
- Abrir Rufus
- Device → seleccionar el USB
- Boot selection → `proxmox-ve_X.X-X.iso`
- Partition scheme → `GPT` (si el PC usa UEFI) o `MBR` (si es BIOS legacy)
- File system → `FAT32`
- Clic en **START** → elegir `Write in ISO Image mode`

---

## 💻 FASE 2 — Instalar Proxmox en el SSD de 256 GB

### Pre-requisitos en el PC servidor
- Conectar el SSD de 256 GB donde irá Proxmox
- Conectar el USB booteable
- Conectar cable de red (Ethernet) al router
- Conectar pantalla y teclado temporalmente

### Pasos de instalación

**1. Entrar al BIOS/UEFI:**
- Al encender, presionar `F2`, `F10`, `F12` o `DEL` (depende del fabricante)
- Configurar el orden de boot: **USB primero**
- Si tiene Secure Boot habilitado → **desactivarlo**
- Si tiene VT-x/AMD-V → **verificar que esté activado** (para virtualización)
- Guardar y reiniciar

**2. Instalador de Proxmox:**
- Seleccionar `Install Proxmox VE (Graphical)`
- **Target Harddisk:** seleccionar el SSD de 256 GB
  > ⚠️ Asegurarse de NO seleccionar el disco con Windows
- **Country:** Paraguay (o el más cercano)
- **Timezone:** America/Asuncion
- **Password:** `TU_PASSWORD_ROOT` (usar la misma que tenías: `Mjjagkaz012.3n3r01995*`)
- **Email:** el tuyo (para notificaciones de Proxmox)

**3. Configuración de red:**
- **Management Interface:** seleccionar la interfaz Ethernet
- **Hostname (FQDN):** `proxmox.lab`
- **IP Address:** `192.168.100.222/24`
- **Gateway:** `192.168.100.1`
- **DNS Server:** `1.1.1.1`

**4. Confirmar y esperar ~5 minutos a que termine la instalación.**

**5. Al terminar → retirar el USB → el sistema reinicia solo.**

---

## 🔧 FASE 3 — Post-instalación en Proxmox

Una vez que el servidor arranca, desde la **notebook** abrís el navegador:

```
https://192.168.100.222:8006
```

> Ignorar la advertencia de certificado SSL → Avanzado → Continuar

Login: `root` / `TU_PASSWORD_ROOT`

### 3.1 — Desactivar repositorio Enterprise (evita errores de apt)

En la **Shell de Proxmox** (Node → proxmox → Shell):

```bash
# Desactivar repo enterprise (requiere suscripción de pago)
echo "# deb https://enterprise.proxmox.com/debian/pve bookworm pve-enterprise" \
  > /etc/apt/sources.list.d/pve-enterprise.list

# Agregar repo community gratuito
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" \
  > /etc/apt/sources.list.d/pve-no-sub.list

# Desactivar repo Ceph enterprise (si existe)
echo "# deb https://enterprise.proxmox.com/debian/ceph-quincy bookworm enterprise" \
  > /etc/apt/sources.list.d/ceph.list 2>/dev/null || true

# Actualizar
apt-get update && apt-get dist-upgrade -y
```

### 3.2 — Instalar herramientas necesarias

```bash
apt-get install -y cifs-utils curl wget git openssh-server
```

### 3.3 — Verificar SSH activo (para que Terraform se conecte)

```bash
systemctl enable ssh
systemctl start ssh
systemctl status ssh
```

Desde la notebook, verificar conectividad SSH:
```bash
# En Windows (PowerShell) o terminal de la notebook:
ssh root@192.168.100.222
```

### 3.4 — Configurar LVM thin pool autoextend (previene el bug del 100%)

```bash
# Abrir configuración LVM
nano /etc/lvm/lvm.conf
```

Buscar la sección `activation {` y agregar debajo:
```
thin_pool_autoextend_threshold = 80
thin_pool_autoextend_percent = 20
```

O ejecutar directamente:
```bash
sed -i '/^[[:space:]]*activation {/a\    thin_pool_autoextend_threshold = 80\n    thin_pool_autoextend_percent = 20' \
  /etc/lvm/lvm.conf
```

---

## 🔑 FASE 4 — Crear Token API para Terraform

Terraform necesita un token API de Proxmox (no usa usuario/contraseña directo).

### En la WebUI de Proxmox:

1. Ir a **Datacenter → Permissions → API Tokens**
2. Clic en **Add**
3. Completar:
   - **User:** `root@pam`
   - **Token ID:** `homelab`
   - **Privilege Separation:** ❌ Desactivar (para que herede todos los permisos de root)
4. Clic en **Add**
5. **⚠️ COPIAR EL TOKEN SECRET AHORA** — solo se muestra una vez

El token tendrá el formato:
```
root@pam!homelab=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

> Guardarlo en un lugar seguro (Vaultwarden cuando esté corriendo).

---

## 🖥️ FASE 5 — Instalar Terraform en la notebook

### Windows (PowerShell como Administrador):

```powershell
# Con Chocolatey (si está instalado):
choco install terraform -y

# Con winget:
winget install HashiCorp.Terraform

# O manual:
# 1. Descargar desde https://developer.hashicorp.com/terraform/downloads
# 2. Extraer terraform.exe
# 3. Moverlo a C:\Windows\System32\ o agregar al PATH
```

Verificar:
```powershell
terraform --version
# Debe mostrar: Terraform v1.x.x
```

### También necesitás SSH disponible en la notebook:

```powershell
# Verificar:
ssh -V
# Si no está: instalar OpenSSH desde Configuración → Apps → Características opcionales
```

---

## ⚙️ FASE 6 — Configurar terraform.tfvars

Desde la notebook, clonar el repo y configurar las variables:

```bash
# Clonar el repositorio (si no lo tenés)
git clone https://github.com/Morochief/homelab-infrastructure-iac.git
cd homelab-infrastructure-iac/proxmox/terraform

# Copiar el template
cp terraform.tfvars.example terraform.tfvars
```

Editar `terraform.tfvars` con tus datos reales:

```hcl
# Proxmox
proxmox_host          = "192.168.100.222"
proxmox_node          = "proxmox"
proxmox_api_token     = "root@pam!homelab=TU-TOKEN-SECRETO-AQUI"
proxmox_root_password = "TU_PASSWORD_ROOT"

# LXC docker-lab
lxc_ip            = "192.168.100.223"
gateway_ip        = "192.168.100.1"
lxc_root_password = "TU_PASSWORD_LXC"
lxc_disk_size     = 80
lxc_cores         = 4
lxc_memory_mb     = 8192
lxc_swap_mb       = 2048

# SMB Share (Windows)
smb_host     = "192.168.100.8"
smb_share    = "Peliculas"
smb_user     = "Morochief"
smb_password = "TU_PASSWORD_SMB"

# General
timezone = "America/Asuncion"
```

> ⚠️ `terraform.tfvars` está en `.gitignore` — nunca se sube al repositorio.

---

## 🚀 FASE 7 — Ejecutar Terraform

```bash
# Desde proxmox/terraform/
cd homelab-infrastructure-iac/proxmox/terraform

# Descargar el provider bpg/proxmox
terraform init

# Revisar qué va a crear (sin aplicar cambios)
terraform plan

# Aplicar — crea el LXC, monta SMB, instala Docker, despliega los 13 contenedores
terraform apply
```

Cuando pregunte `Do you want to perform these actions?` → escribir `yes`

### ⏱️ Tiempo estimado:
| Fase | Tiempo |
|------|--------|
| Descarga template Ubuntu 24.04 | ~2 min |
| Creación del LXC | ~30 seg |
| Configuración CIFS + bind mount | ~1 min |
| Instalación Docker | ~3 min |
| Descarga y despliegue de los 13 stacks | ~10-15 min |
| **Total** | **~15-20 min** |

### Al finalizar, Terraform muestra los outputs:
```
Outputs:
proxmox_url = "https://192.168.100.222:8006"
docker_lab_ip = "192.168.100.223"
services = {
  adguard_home        = "http://192.168.100.223:8082"
  homarr              = "http://192.168.100.223:7575"
  jellyfin            = "http://192.168.100.223:8096"
  jellyseerr          = "http://192.168.100.223:5055"
  nginx_proxy_manager = "http://192.168.100.223:81"
  portainer           = "http://192.168.100.223:9000"
  prowlarr            = "http://192.168.100.223:9696"
  qbittorrent         = "http://192.168.100.223:8083"
  radarr              = "http://192.168.100.223:7878"
  sonarr              = "http://192.168.100.223:8989"
  uptime_kuma         = "http://192.168.100.223:3001"
  vaultwarden         = "http://192.168.100.223:8081"
}
```

---

## 🔧 FASE 8 — Configuración manual post-deploy

Terraform despliega todo, pero estos 3 pasos se hacen una vez manualmente:

### 8.1 — AdGuard Home: Asistente inicial

1. Abrir `http://192.168.100.223:3000` (puerto del wizard)
2. Completar el asistente:
   - **Web Admin interface:** puerto `8082` (importante — este es el que quedó guardado)
   - **DNS server:** puerto `53`
   - Crear usuario `admin`
3. Una vez configurado, acceder en `http://192.168.100.223:8082`

**Agregar DNS Rewrites** (Filtros → Reescrituras DNS → Agregar):

| Dominio | IP destino |
|---------|------------|
| `adguard.lab` | `192.168.100.223` |
| `vault.lab` | `192.168.100.223` |
| `kuma.lab` | `192.168.100.223` |
| `jellyfin.lab` | `192.168.100.223` |
| `torrents.lab` | `192.168.100.223` |
| `prowlarr.lab` | `192.168.100.223` |
| `radarr.lab` | `192.168.100.223` |
| `sonarr.lab` | `192.168.100.223` |
| `seerr.lab` | `192.168.100.223` |

**Configurar el DNS del router** para que apunte a AdGuard:
- En tu router → DNS primario: `192.168.100.223`
- DNS secundario: `1.1.1.1`

### 8.2 — Nginx Proxy Manager: Proxy Hosts

Acceder a `http://192.168.100.223:81`
- Login inicial: `admin@example.com` / `changeme` → cambiar inmediatamente

Crear un **Proxy Host** por cada servicio:

| Domain Name | Forward Host | Forward Port | Opciones |
|-------------|-------------|--------------|----------|
| `vault.lab` | `192.168.100.223` | `8081` | Websockets, Custom SSL |
| `kuma.lab` | `192.168.100.223` | `3001` | Websockets |
| `adguard.lab` | `192.168.100.223` | `8082` | Block Common Exploits |
| `jellyfin.lab` | `192.168.100.223` | `8096` | Websockets |
| `torrents.lab` | `192.168.100.223` | `8083` | Websockets |
| `prowlarr.lab` | `192.168.100.223` | `9696` | Block Common Exploits |
| `radarr.lab` | `192.168.100.223` | `7878` | Block Common Exploits |
| `sonarr.lab` | `192.168.100.223` | `8989` | Block Common Exploits |
| `seerr.lab` | `192.168.100.223` | `5055` | Websockets |

### 8.3 — qBittorrent: Fix de cabeceras HTTP (para que funcione via NPM)

Desde la **Shell del LXC** o via `pct exec 100 -- bash`:

```bash
CONF_FILE=$(find /var/lib/docker/volumes -name "qBittorrent.conf" 2>/dev/null | head -n 1)
echo "Archivo encontrado: $CONF_FILE"
sed -i '/WebUI\\HostHeaderValidation/d' "$CONF_FILE"
sed -i '/WebUI\\CSRFProtection/d' "$CONF_FILE"
sed -i '/\[Preferences\]/a WebUI\\HostHeaderValidation=false\nWebUI\\CSRFProtection=false' "$CONF_FILE"
docker restart qbittorrent
```

### 8.4 — Uptime Kuma: Agregar monitores

Acceder a `http://192.168.100.223:3001` y crear monitores HTTP para cada servicio.

### 8.5 — Jellyseerr: Conectar con Jellyfin

1. Abrir `http://192.168.100.223:5055`
2. Login con la cuenta de Jellyfin
3. Vincular APIs de Radarr y Sonarr

---

## 🛡️ Troubleshooting rápido

| Síntoma | Causa | Solución |
|---------|-------|----------|
| `terraform apply` falla en SSH | Proxmox no tiene SSH activo | `systemctl start ssh` en Proxmox |
| LXC no tiene internet | DNS no configurado en el LXC | Verificar `/etc/resolv.conf` dentro del LXC |
| AdGuard no abre en `:8082` | Puerto interno ≠ mapeo | Usar `8082:8082` no `8082:80` |
| `no space left on device` al descargar imagen | LVM thin pool al 100% | `lvextend -l +100%FREE pve/data` |
| qBittorrent HTTP 401 via proxy | CSRF/HostHeader bloqueado | Ejecutar el fix del paso 8.3 |
| Contenedor no inicia en LXC | `nesting=0` en LXC config | Verificar Features → Nesting activado |
| SMB no monta | Windows no comparte o IP errónea | Verificar share activo y credenciales |

---

## 📊 Arquitectura final (Bare Metal)

```
[ Windows 11 PC — 192.168.100.8 ]
  └── SMB Share: \\192.168.100.8\Peliculas

[ PC Servidor con SSD 256 GB — Proxmox VE Bare Metal ]
  └── IP: 192.168.100.222:8006
      └── LXC CT 100 — docker-lab (192.168.100.223)
          └── Docker Engine
              ├── infrastructure-core  → Portainer (:9000) + NPM (:81)
              ├── security-stack       → AdGuard (:8082) + Vaultwarden (:8081)
              ├── monitoring-stack     → Uptime Kuma (:3001) + Homarr (:7575)
              ├── arr-stack            → Jellyfin + qBittorrent + Prowlarr + Radarr + Sonarr + Flare
              └── jellyseerr           → Jellyseerr (:5055)
```

---

## ✅ Checklist de finalización

- [ ] Proxmox instalado en SSD 256 GB con IP `192.168.100.222`
- [ ] Repositorio community configurado (`pve-no-subscription`)
- [ ] SSH activo en Proxmox
- [ ] Token API creado: `root@pam!homelab=...`
- [ ] `terraform.tfvars` completado (git-ignorado)
- [ ] `terraform init && terraform apply` ejecutado con éxito
- [ ] LXC docker-lab corriendo en `192.168.100.223`
- [ ] 13 contenedores Docker activos (`docker ps`)
- [ ] AdGuard wizard completado (puerto web `8082`)
- [ ] DNS Rewrites configurados en AdGuard
- [ ] DNS del router apuntando a `192.168.100.223`
- [ ] NPM Proxy Hosts configurados para todos los dominios `.lab`
- [ ] qBittorrent fix de cabeceras aplicado
- [ ] Acceso a todos los servicios via dominio `.lab` verificado

---

*Generado para: Morochief/homelab-infrastructure-iac*  
*Última actualización: Agosto 2026*
