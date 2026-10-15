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
  hk_list     = pathexpand("~/build/HardeningKitty/lists/finding_list_cis_microsoft_windows_server_2025_24h2_1.0.0_machine.csv")
  tailored    = "${local.repo_root}/windows-hardening/build/cis_ws2025_tailored.csv"
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

  # 0. Tailored list on the host (official list minus documented exceptions)
  provisioner "shell-local" {
    inline = [
      "mkdir -p ${local.results_dir}",
      "python3 ${local.repo_root}/windows-hardening/tailor_list.py --in ${local.hk_list} --exceptions ${local.repo_root}/windows-hardening/exceptions.txt --out ${local.tailored}",
    ]
  }

  # 1. Smoke test of the fresh install
  provisioner "powershell" {
    inline = [
      "Get-CimInstance Win32_OperatingSystem | Format-List Caption, Version, BuildNumber",
      "whoami",
      "(Get-NetConnectionProfile).NetworkCategory",
      "New-Item -ItemType Directory -Force -Path C:\\Tools | Out-Null",
    ]
  }

  # 2. Tools: HardeningKitty, scan and hardening scripts, tailored list
  provisioner "file" {
    source      = local.hk_zip
    destination = "C:/Tools/HardeningKitty.zip"
  }

  provisioner "file" {
    source      = "${local.repo_root}/scanning/windows/scan.ps1"
    destination = "C:/Tools/scan.ps1"
  }

  provisioner "file" {
    source      = "${local.repo_root}/windows-hardening/harden.ps1"
    destination = "C:/Tools/harden.ps1"
  }

  provisioner "file" {
    source      = local.tailored
    destination = "C:/Tools/cis_ws2025_tailored.csv"
    generated   = true
  }

  provisioner "powershell" {
    inline = [
      "Expand-Archive -Path C:\\Tools\\HardeningKitty.zip -DestinationPath C:\\Tools -Force",
      "Remove-Item C:\\Tools\\HardeningKitty.zip",
      "if (-not (Test-Path C:\\Tools\\HardeningKitty\\HardeningKitty.psm1)) { throw 'HardeningKitty module not found' }",
    ]
  }

  # 3. Baseline scan (official CIS list)
  provisioner "powershell" {
    inline = ["& C:\\Tools\\scan.ps1 -Phase baseline"]
  }

  provisioner "file" {
    direction   = "download"
    source      = "C:/scan/baseline.zip"
    destination = "${local.results_dir}/baseline.zip"
  }

  # 4. Hardening (tailored list), with a backup for rollback
  provisioner "powershell" {
    inline = ["& C:\\Tools\\harden.ps1"]
  }

  provisioner "file" {
    direction   = "download"
    source      = "C:/scan/backup-before-hardening.csv"
    destination = "${local.results_dir}/backup-before-hardening.csv"
  }

  # 5. Reboot, so the final scan measures the persisted state
  provisioner "windows-restart" {
    restart_timeout = "30m"
  }

  # 6. Final scan (official CIS list: exceptions are still measured)
  provisioner "powershell" {
    inline = ["& C:\\Tools\\scan.ps1 -Phase final"]
  }

  provisioner "file" {
    direction   = "download"
    source      = "C:/scan/final.zip"
    destination = "${local.results_dir}/final.zip"
  }

  # 7. Remove tools and scan artefacts from the image
  provisioner "powershell" {
    inline = ["Remove-Item C:\\Tools, C:\\scan -Recurse -Force"]
  }

  # 8. Report on the host
  post-processor "shell-local" {
    inline = ["${local.repo_root}/reporting/make_report.sh windows"]
  }
}
