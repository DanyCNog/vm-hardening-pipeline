packer {
  required_plugins {
    virtualbox = {
      source  = "github.com/hashicorp/virtualbox"
      version = ">= 1.1.0"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = ">= 1.1.0"
    }
  }
}

locals {
  repo_root   = abspath("${path.root}/../..")
  results_dir = "${local.repo_root}/scanning/results/debian13"
}

# Runs provisioner scripts as root with the password, so it keeps working
# after the role removes passwordless sudo (CIS 5.2.4).
local "sudo_exec" {
  expression = "echo '${var.ssh_password}' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
  sensitive  = true
}

source "virtualbox-iso" "debian13" {
  vm_name          = var.vm_name
  output_directory = "output-${var.vm_name}"
  guest_os_type    = "Debian_64"
  headless         = var.headless

  iso_urls = [
    "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-${var.debian_version}-amd64-netinst.iso",
    "https://cdimage.debian.org/cdimage/archive/${var.debian_version}/amd64/iso-cd/debian-${var.debian_version}-amd64-netinst.iso",
  ]
  iso_checksum = "sha256:${var.iso_sha256}"

  cpus      = var.cpus
  memory    = var.memory
  disk_size = var.disk_size

  guest_additions_mode = "disable"

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

  skip_export     = true
  keep_registered = true
}

build {
  name    = "debian13-cis"
  sources = ["source.virtualbox-iso.debian13"]

  # 1. Smoke test of the fresh install
  provisioner "shell" {
    inline = [
      "grep PRETTY_NAME /etc/os-release",
      "hostnamectl --static",
    ]
  }

  # 2. Scanners and scan content
  provisioner "shell" {
    execute_command = local.sudo_exec
    inline = [
      "apt-get update -qq",
      "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq lynis openscap-scanner",
    ]
  }

  provisioner "file" {
    source      = "${local.repo_root}/scanning/linux/scan.sh"
    destination = "/var/tmp/scan.sh"
  }

  provisioner "file" {
    source      = "${local.repo_root}/scanning/content/ssg-debian13-ds.xml"
    destination = "/var/tmp/ssg-debian13-ds.xml"
  }

  provisioner "shell-local" {
    inline = ["mkdir -p ${local.results_dir}"]
  }

  # 3. Baseline scan
  provisioner "shell" {
    execute_command = local.sudo_exec
    inline          = ["bash /var/tmp/scan.sh baseline"]
  }

  provisioner "file" {
    direction   = "download"
    source      = "/var/tmp/scan/baseline.tar.gz"
    destination = "${local.results_dir}/baseline.tar.gz"
  }

  # 4. Hardening with the cis_debian13 role
  provisioner "ansible" {
    playbook_file = "${local.repo_root}/ansible/playbooks/harden-debian13.yml"
    user          = var.ssh_username
    groups        = ["debian13"]
    use_proxy     = false
    ansible_env_vars = [
      "ANSIBLE_CONFIG=${local.repo_root}/ansible/ansible.cfg",
      "ANSIBLE_HOST_KEY_CHECKING=False",
    ]
    extra_arguments = [
      "--extra-vars",
      jsonencode({
        ansible_password        = var.ssh_password
        ansible_become_password = var.ssh_password
      }),
    ]
  }

  # 5. Reboot, so the final scan measures the persisted state
  provisioner "shell" {
    execute_command   = local.sudo_exec
    inline            = ["shutdown -r now"]
    expect_disconnect = true
  }

  # 6. Final scan
  provisioner "shell" {
    pause_before    = "60s"
    execute_command = local.sudo_exec
    inline          = ["bash /var/tmp/scan.sh final"]
  }

  provisioner "file" {
    direction   = "download"
    source      = "/var/tmp/scan/final.tar.gz"
    destination = "${local.results_dir}/final.tar.gz"
  }

  # 7. Remove scan artefacts from the image
  provisioner "shell" {
    execute_command = local.sudo_exec
    inline          = ["rm -rf /var/tmp/scan /var/tmp/scan.sh /var/tmp/ssg-debian13-ds.xml"]
  }

  # 8. Build the before/after report on the host
  post-processor "shell-local" {
    inline = [
      "cd ${local.results_dir}",
      "rm -rf baseline final",
      "tar -xzf baseline.tar.gz",
      "tar -xzf final.tar.gz",
      "mkdir -p ${local.repo_root}/reporting/output",
      "python3 ${local.repo_root}/reporting/generate_report.py --baseline baseline --final final --out ${local.repo_root}/reporting/output/debian13-report.html --title 'Debian 13 hardening report'",
    ]
  }
}
