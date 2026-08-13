# ==============================================================================
# main.tf — Homelab Infrastructure as Code
# Proyecto: Morochief/homelab-infrastructure-iac
# Proveedor: bpg/proxmox (~> 0.78)
# ==============================================================================

terraform {
  required_version = ">= 1.5"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.78"
    }
  }
}

provider "proxmox" {
  endpoint  = "https://${var.proxmox_host}:8006/"
  api_token = var.proxmox_api_token
  insecure  = true  # self-signed cert de Proxmox
}

# ------------------------------------------------------------------------------
# 1. Descargar template Ubuntu 24.04 LXC
# ------------------------------------------------------------------------------
resource "proxmox_virtual_environment_download_file" "ubuntu_template" {
  content_type = "vztmpl"
  datastore_id = "local"
  node_name    = var.proxmox_node
  url          = "http://download.proxmox.com/images/system/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
  overwrite    = false
}

# ------------------------------------------------------------------------------
# 2. Crear contenedor LXC docker-lab (CT 100)
# ------------------------------------------------------------------------------
resource "proxmox_virtual_environment_container" "docker_lab" {
  description   = "Docker Lab — Homelab Microservices Host"
  node_name     = var.proxmox_node
  vm_id         = 100
  unprivileged  = true
  start_on_boot = true
  tags          = ["docker", "homelab", "infrastructure"]

  initialization {
    hostname = "docker-lab"

    ip_config {
      ipv4 {
        address = "${var.lxc_ip}/24"
        gateway = var.gateway_ip
      }
    }

    dns {
      servers = ["1.1.1.1", "8.8.8.8"]
      domain  = "lab"
    }

    user_account {
      password = var.lxc_root_password
    }
  }

  cpu {
    architecture = "amd64"
    cores        = var.lxc_cores
  }

  memory {
    dedicated = var.lxc_memory_mb
    swap      = var.lxc_swap_mb
  }

  disk {
    datastore_id = "local-lvm"
    size         = var.lxc_disk_size
  }

  network_interface {
    name     = "eth0"
    bridge   = "vmbr0"
    firewall = false
  }

  operating_system {
    template_file_id = proxmox_virtual_environment_download_file.ubuntu_template.id
    type             = "ubuntu"
  }

  features {
    nesting = true   # requerido para Docker dentro de LXC
    fuse    = true   # requerido para overlay filesystem
  }

  started = true

  depends_on = [proxmox_virtual_environment_download_file.ubuntu_template]
}

# ------------------------------------------------------------------------------
# 3. Configurar host Proxmox: CIFS + bind mount al LXC
#    (requiere SSH habilitado en Proxmox)
# ------------------------------------------------------------------------------
resource "null_resource" "proxmox_host_setup" {
  depends_on = [proxmox_virtual_environment_container.docker_lab]

  connection {
    type     = "ssh"
    user     = "root"
    password = var.proxmox_root_password
    host     = var.proxmox_host
    timeout  = "3m"
  }

  provisioner "remote-exec" {
    inline = [
      # Instalar cifs-utils
      "apt-get update -qq && apt-get install -y cifs-utils",

      # Crear punto de montaje
      "mkdir -p /mnt/win_media",

      # Montar share SMB (ignorar error si ya esta montado)
      "mountpoint -q /mnt/win_media || mount -t cifs //${var.smb_host}/${var.smb_share} /mnt/win_media -o username=${var.smb_user},password=${var.smb_password},iocharset=utf8,vers=3.0,uid=0,gid=0 || true",

      # Persistir en fstab
      "grep -q 'win_media' /etc/fstab || echo '//${var.smb_host}/${var.smb_share} /mnt/win_media cifs username=${var.smb_user},password=${var.smb_password},iocharset=utf8,vers=3.0,uid=0,gid=0,_netdev 0 0' >> /etc/fstab",

      # LVM thin pool autoextend (evita el problema del 100% que tuvimos)
      "grep -q 'thin_pool_autoextend_threshold' /etc/lvm/lvm.conf || sed -i '/^activation {/a \\    thin_pool_autoextend_threshold = 80\\n    thin_pool_autoextend_percent = 20' /etc/lvm/lvm.conf || true",

      # Configurar bind mount en el LXC
      "pct stop 100 --skiplock || true",
      "sleep 5",
      "pct set 100 -mp0 /mnt/win_media,mp=/mnt/win_media",
      "pct start 100",
      "sleep 20",

      "echo '✅ Proxmox host setup completo'"
    ]
  }
}

# ------------------------------------------------------------------------------
# 4. Provisionar docker-lab: instalar Docker + desplegar todos los stacks
# ------------------------------------------------------------------------------
resource "null_resource" "docker_lab_setup" {
  depends_on = [null_resource.proxmox_host_setup]

  connection {
    type     = "ssh"
    user     = "root"
    password = var.lxc_root_password
    host     = var.lxc_ip
    timeout  = "10m"
  }

  # Copiar todos los stacks al LXC
  provisioner "file" {
    source      = "${path.module}/../stacks/"
    destination = "/opt/stacks/"
  }

  # Copiar script de bootstrap
  provisioner "file" {
    source      = "${path.module}/scripts/docker-setup.sh"
    destination = "/tmp/docker-setup.sh"
  }

  # Ejecutar bootstrap
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/docker-setup.sh",
      "bash /tmp/docker-setup.sh"
    ]
  }
}
