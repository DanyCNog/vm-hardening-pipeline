packer {
  required_plugins {
    virtualbox = {
      source  = "github.com/hashicorp/virtualbox"
      version = ">= 1.1.0"
    }
  }
}

locals {
  repo_root   = abspath("${path.root}/../..")
  results_dir = "${local.repo_root}/scanning/results/ws2025"
  hk_zip      = pathexpand("~/build/HardeningKitty.zip")
}

source "virtualbox-iso" "ws2025" {
  vm_name          = var.vm_name
  output_directory = "output-${var.vm_name}"
  guest_os_type    = var.guest_os_type
  firmware         = "bios"
  headless         = var.headless

  iso_url      = var.iso_path
  iso_checksum = "sha256:${var.iso_sha256}"

  cpus                 = var.cpus
  memory               = var.memory
  disk_size            = var.disk_size
  hard_drive_interface = "sata"
  iso_interface        = "sata"
  gfx_controller       = "vboxsvga"
  gfx_vram_size        = 128
  guest_additions_mode = "disable"

  # Windows Setup reads autounattend.xml from the root of any CD/DVD
  cd_label = "UNATTEND"
  cd_content = {
    "autounattend.xml" = templatefile("${path.root}/answer/autounattend.pkrtpl", {
      username    = var.admin_username
      password    = var.admin_password
      hostname    = var.vm_name
      image_index = var.image_index
    })
    "bootstrap.ps1" = file("${path.root}/scripts/bootstrap.ps1")
  }

  boot_wait    = "2s"
  boot_command = ["<spacebar>"]

  communicator   = "winrm"
  winrm_username = var.admin_username
  winrm_password = var.admin_password
  winrm_use_ssl  = true
  winrm_insecure = true
  winrm_use_ntlm = true
  winrm_timeout  = "2h"

  shutdown_command = "shutdown /s /t 10 /f /d p:4:1 /c \"Packer shutdown\""
  shutdown_timeout = "15m"

  skip_export     = true
  keep_registered = true
}

build {
  name    = "ws2025-cis"
  sources = ["source.virtualbox-iso.ws2025"]

  # 1. Smoke test of the fresh install
  provisioner "powershell" {
    inline = [
      "Get-CimInstance Win32_OperatingSystem | Format-List Caption, Version, BuildNumber",
      "whoami",
      "(Get-NetConnectionProfile).NetworkCategory",
      "New-Item -ItemType Directory -Force -Path C:\\Tools | Out-Null",
    ]
  }

  # 2. HardeningKitty and the scan script
  provisioner "file" {
    source      = local.hk_zip
    destination = "C:/Tools/HardeningKitty.zip"
  }

  provisioner "file" {
    source      = "${local.repo_root}/scanning/windows/scan.ps1"
    destination = "C:/Tools/scan.ps1"
  }

  provisioner "powershell" {
    inline = [
      "Expand-Archive -Path C:\\Tools\\HardeningKitty.zip -DestinationPath C:\\Tools -Force",
      "Remove-Item C:\\Tools\\HardeningKitty.zip",
      "if (-not (Test-Path C:\\Tools\\HardeningKitty\\HardeningKitty.psm1)) { throw 'HardeningKitty module not found' }",
    ]
  }

  provisioner "shell-local" {
    inline = ["mkdir -p ${local.results_dir}"]
  }

  # 3. Baseline scan
  provisioner "powershell" {
    inline = ["& C:\\Tools\\scan.ps1 -Phase baseline"]
  }

  provisioner "file" {
    direction   = "download"
    source      = "C:/scan/baseline.zip"
    destination = "${local.results_dir}/baseline.zip"
  }

  # Phase 6B adds: hardening, reboot, final scan, report

  post-processor "shell-local" {
    inline = [
      "cd ${local.results_dir}",
      "rm -rf baseline",
      "unzip -oq baseline.zip",
      "ls -l baseline",
    ]
  }
}
