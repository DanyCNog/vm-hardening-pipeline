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
  results_dir = "${local.repo_root}/scanning/results/rocky10"
}

local "sudo_exec" {
  expression = "echo '${var.ssh_password}' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
  sensitive  = true
}

source "virtualbox-iso" "rocky10" {
  vm_name          = var.vm_name
  output_directory = "output-${var.vm_name}"
  guest_os_type    = "RedHat_64"
  headless         = var.headless

  iso_urls = [
    "https://download.rockylinux.org/pub/rocky/${var.rocky_version}/isos/x86_64/Rocky-${var.rocky_version}-x86_64-minimal.iso",
    "https://dl.rockylinux.org/vault/rocky/${var.rocky_version}/isos/x86_64/Rocky-${var.rocky_version}-x86_64-minimal.iso",
  ]
  iso_checksum = "sha256:${var.iso_sha256}"

  cpus      = var.cpus
  memory    = var.memory
  disk_size = var.disk_size

  guest_additions_mode = "disable"

  # Anaconda loads ks.cfg automatically from a volume labelled OEMDRV
  cd_label = "OEMDRV"
  cd_content = {
    "ks.cfg" = templatefile("${path.root}/kickstart/ks.pkrtpl", {
      username = var.ssh_username
      password = var.ssh_password
      hostname = var.vm_name
    })
  }

  # Select "Install Rocky Linux" instead of the default "Test this media & install"
  boot_wait    = "5s"
  boot_command = ["<up><enter>"]

  communicator = "ssh"
  ssh_username = var.ssh_username
  ssh_password = var.ssh_password
  ssh_timeout  = "45m"

  shutdown_command = "echo '${var.ssh_password}' | sudo -S shutdown -P now"

  skip_export     = true
  keep_registered = true
}

build {
  name    = "rocky10-cis"
  sources = ["source.virtualbox-iso.rocky10"]

  # 1. Smoke test of the fresh install
  provisioner "shell" {
    inline = [
      "cat /etc/rocky-release",
      "hostnamectl --static",
      "getenforce",
    ]
  }

  # 2. Scanners (Lynis comes from EPEL; SCAP content ships with the distribution)
  provisioner "shell" {
    execute_command = local.sudo_exec
    inline = [
      "dnf install -y -q epel-release",
      "dnf install -y -q lynis openscap-scanner scap-security-guide tar",
    ]
  }

  provisioner "file" {
    source      = "${local.repo_root}/scanning/linux/scan.sh"
    destination = "/var/tmp/scan.sh"
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

  # 4. Hardening with the cis_rhel10 role
  provisioner "ansible" {
    playbook_file = "${local.repo_root}/ansible/playbooks/harden-rocky10.yml"
    user          = var.ssh_username
    groups        = ["rocky10"]
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
    inline          = ["rm -rf /var/tmp/scan /var/tmp/scan.sh"]
  }

  # 8. Build the before/after report on the host
  post-processor "shell-local" {
    inline = [
      "cd ${local.results_dir}",
      "rm -rf baseline final",
      "tar -xzf baseline.tar.gz",
      "tar -xzf final.tar.gz",
      "mkdir -p ${local.repo_root}/reporting/output",
      "python3 ${local.repo_root}/reporting/generate_report.py --baseline baseline --final final --out ${local.repo_root}/reporting/output/rocky10-report.html --title 'Rocky Linux 10 hardening report' --profile-label 'CIS RHEL 10 Level 1 Server'",
    ]
  }
}
