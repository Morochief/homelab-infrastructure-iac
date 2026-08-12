# ==============================================================================
# outputs.tf — Homelab Infrastructure as Code
# ==============================================================================

output "proxmox_url" {
  description = "URL de la WebUI de Proxmox VE"
  value       = "https://${var.proxmox_host}:8006"
}

output "docker_lab_ip" {
  description = "IP del contenedor LXC docker-lab"
  value       = var.lxc_ip
}

output "services" {
  description = "URLs de acceso a todos los servicios del homelab"
  value = {
    portainer             = "http://${var.lxc_ip}:9000"
    nginx_proxy_manager   = "http://${var.lxc_ip}:81"
    adguard_home          = "http://${var.lxc_ip}:8082"
    vaultwarden           = "http://${var.lxc_ip}:8081"
    uptime_kuma           = "http://${var.lxc_ip}:3001"
    homarr                = "http://${var.lxc_ip}:7575"
    jellyfin              = "http://${var.lxc_ip}:8096"
    qbittorrent           = "http://${var.lxc_ip}:8083"
    prowlarr              = "http://${var.lxc_ip}:9696"
    radarr                = "http://${var.lxc_ip}:7878"
    sonarr                = "http://${var.lxc_ip}:8989"
    flaresolverr          = "http://${var.lxc_ip}:8191"
    jellyseerr            = "http://${var.lxc_ip}:5055"
  }
}
