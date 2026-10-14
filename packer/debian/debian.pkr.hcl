packer {
  required_plugins {
    virtualbox = {
      source  = "github.com/hashicorp/virtualbox"
      version = ">= 1.1.0"
    }
  }
}

source "virtualbox-iso" "debian13" {
  vm_name       = var.vm_name
  guest_os_type = "Debian_64"
  headless      = var.headless

  # Versão e hash fixados = build reproduzível
  iso_urls = [
    "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-${var.debian_version}-amd64-netinst.iso",
    "https://cdimage.debian.org/cdimage/archive/${var.debian_version}/amd64/iso-cd/debian-${var.debian_version}-amd64-netinst.iso",
  ]
  iso_checksum = "sha256:${var.iso_sha256}"

  cpus      = var.cpus
  memory    = var.memory
  disk_size = var.disk_size

  guest_additions_mode = "disable"

  # Preseed gerado no momento do build: a password nunca fica no repositório
  http_content = {
    "/preseed.cfg" = templatefile("${path.root}/http/preseed.pkrtpl", {
      username = var.ssh_username
      password = var.ssh_password
      hostname = var.vm_name
    })
  }

  boot_wait = "5s"
  boot_command = [
    "<esc><wait>",
    "auto preseed/url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg ",
    "netcfg/get_hostname=${var.vm_name} netcfg/get_domain=lab.local",
    "<enter>",
  ]

  communicator = "ssh"
  ssh_username = var.ssh_username
  ssh_password = var.ssh_password
  ssh_timeout  = "45m"

  shutdown_command = "echo '${var.ssh_password}' | sudo -S shutdown -P now"

  # Poupa disco: não exporta OVA, deixa a VM registada no VirtualBox
  skip_export     = true
  keep_registered = true
}

build {
  name    = "debian13-base"
  sources = ["source.virtualbox-iso.debian13"]

  provisioner "shell" {
    inline = [
      "echo '===== SMOKE TEST ====='",
      "grep PRETTY_NAME /etc/os-release",
      "hostnamectl --static",
      "ip -brief address",
      "df -h /",
      "sudo -n true && echo 'sudo: OK'",
    ]
  }
}
