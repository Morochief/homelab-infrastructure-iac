# ==============================================================================
# variables.tf — Homelab Infrastructure as Code
# ==============================================================================

variable "proxmox_host" {
  description = "IP del host Proxmox VE bare metal"
  type        = string
  default     = "192.168.100.222"
}

variable "proxmox_node" {
  description = "Nombre del nodo Proxmox (hostname durante la instalacion)"
  type        = string
  default     = "proxmox"
}

variable "proxmox_api_token" {
  description = "Token API en formato 'USER@REALM!TOKENID=SECRET'"
  type        = string
  sensitive   = true
}

variable "proxmox_root_password" {
  description = "Contrasena root de Proxmox (para provisioner SSH)"
  type        = string
  sensitive   = true
}

variable "lxc_ip" {
  description = "IP estatica del contenedor LXC docker-lab"
  type        = string
  default     = "192.168.100.223"
}

variable "gateway_ip" {
  description = "Gateway de la red local"
  type        = string
  default     = "192.168.100.1"
}

variable "lxc_root_password" {
  description = "Contrasena root del contenedor LXC docker-lab"
  type        = string
  sensitive   = true
}

variable "lxc_disk_size" {
  description = "Tamano del disco del LXC en GB"
  type        = number
  default     = 80
}

variable "lxc_cores" {
  description = "Cores del LXC"
  type        = number
  default     = 4
}

variable "lxc_memory_mb" {
  description = "RAM del LXC en MB"
  type        = number
  default     = 8192
}

variable "lxc_swap_mb" {
  description = "Swap del LXC en MB"
  type        = number
  default     = 2048
}

variable "smb_host" {
  description = "IP del servidor Windows con el share SMB"
  type        = string
  default     = "192.168.100.8"
}

variable "smb_share" {
  description = "Nombre del share SMB"
  type        = string
  default     = "Peliculas"
}

variable "smb_user" {
  description = "Usuario del share SMB"
  type        = string
  sensitive   = true
}

variable "smb_password" {
  description = "Contrasena del share SMB"
  type        = string
  sensitive   = true
}

variable "timezone" {
  description = "Zona horaria para los contenedores Docker"
  type        = string
  default     = "America/Asuncion"
}
