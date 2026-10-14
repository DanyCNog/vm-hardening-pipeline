# vm-hardening-pipeline

Builds a Debian 13 virtual machine from the official ISO without manual steps and hardens it against the CIS Debian Linux 13 Benchmark v1.0.0 with Ansible. Every task in the hardening role is named after the CIS recommendation it implements, so each change can be traced back to the benchmark.

Status: the unattended build and the hardening role work. Lynis and OpenSCAP scans before and after hardening are in progress. Rocky Linux and Windows Server come later.

## How the build works

Packer downloads the Debian 13 netinst ISO and checks it against a SHA-256 hash pinned in `packer/debian/variables.pkr.hcl`. It then creates a VirtualBox VM, types the boot command and serves a preseed file from a temporary HTTP server on the host. The Debian installer reads its answers from that file and finishes without input. When the VM comes back up, Packer logs in over SSH, runs a short smoke test and shuts it down.

The preseed file is a template. Packer fills in the user name and password at build time from `lab.auto.pkrvars.hcl`, which Git ignores, so the password is never committed.

The Ansible role `cis_debian13` then applies the hardening. During development it runs against a snapshot of the built VM, which makes changes quick to test and easy to roll back.

## Benchmark coverage

The role covers Level 1 Server recommendations and a few Level 2 items, mostly the auditd controls in section 6.2.

| Area | CIS recommendations |
|---|---|
| Unused filesystem and network protocol kernel modules | 1.1.1.1 to 1.1.1.5, 1.1.1.9, 1.1.1.10, 3.2.1 to 3.2.6 |
| AppArmor enabled at boot, bootloader config permissions | 1.3.1.1, 1.3.1.2, 1.4.2 |
| Kernel and process hardening (sysctl, core dumps) | 1.5.1 to 1.5.5, 1.5.8 to 1.5.11 |
| Login banners without OS details | 1.6.1 to 1.6.6 |
| Network services and insecure clients removed | 2.1.1 to 2.1.20, 2.2.1 to 2.2.6 |
| cron access and permissions | 2.4.1.1 to 2.4.1.9 |
| IPv4 and IPv6 network parameters | 3.3.1.1 to 3.3.1.18, 3.3.2.1 to 3.3.2.8 |
| UFW firewall, inbound denied by default | 4.1.1 to 4.1.3, 4.1.5 |
| SSH server configuration | 5.1.1 to 5.1.23 |
| sudo and su | 5.2.2 to 5.2.7 |
| Password quality, lockout, aging, shell timeout, umask | 5.3.1.3, 5.3.2.2, 5.3.2.3, 5.3.3.1.1, 5.3.3.1.2, 5.3.3.2.1 to 5.3.3.2.8, 5.4.1.1 to 5.4.1.5, 5.4.3.2, 5.4.3.3 |
| auditd, log retention and audit rules | 6.2.1.1 to 6.2.1.4, 6.2.2.1, 6.2.2.2, selected 6.2.3.x |
| AIDE file integrity database | 6.3.1 |

Recommendations that are not applied are listed in [docs/EXCEPTIONS.md](docs/EXCEPTIONS.md), each with a reason. Two examples are the bootloader password and halting the system when audit storage fills up.

## Notes from building it

- SSH key exchange prefers `mlkem768x25519-sha256`, the hybrid post-quantum algorithm in OpenSSH 10 (CIS 5.1.13). Clients without it fall back to `curve25519-sha256`.
- On Debian 13 the kernel resets some network sysctl values when an interface comes up. The role adds a oneshot systemd service that re-applies `/etc/sysctl.d` once the network is online, so 3.3.1.16 and 3.3.1.17 still hold after a reboot.
- The installer gives the admin user passwordless sudo because Ansible needs it on the first run. The role removes it (5.2.4), but first checks that the user is still in the `sudo` group. If the check fails, the play stops instead of leaving the system without an administrator.
- A second run of the playbook reports `changed=0`.
- VirtualBox on a host with Linux 6.12 or newer can fail with `VERR_VMX_IN_VMX_ROOT_MODE`, because KVM now enables the CPU virtualization extensions as soon as its module loads. Adding `options kvm enable_virt_at_load=0` to a file in `/etc/modprobe.d` fixes it without unloading KVM.

## Requirements

- Linux host with VirtualBox 7.x (developed on Kali Linux with VirtualBox 7.2)
- Packer 1.16 or newer
- Ansible with the `ansible.posix` and `community.general` collections

The VM gets 2 vCPUs, 2 GB of RAM and a 20 GB dynamically allocated disk.

## Usage

Build the base VM:

~~~bash
cd packer/debian
cp lab.auto.pkrvars.hcl.example lab.auto.pkrvars.hcl   # then set ssh_password
packer init .
packer build .
~~~

Apply the hardening:

~~~bash
ssh-keygen -t ed25519 -f ~/.ssh/lab_ed25519 -C "vm-hardening-lab" -N ""
VBoxManage modifyvm debian13-base --natpf1 "ssh-dev,tcp,127.0.0.1,2222,,22"
VBoxManage startvm debian13-base --type headless
ssh-copy-id -i ~/.ssh/lab_ed25519.pub -p 2222 labadmin@127.0.0.1

cd ansible
ansible-galaxy collection install -r requirements.yml
ansible-playbook playbooks/harden-debian13.yml -K
~~~

The port forward only listens on 127.0.0.1. The `-K` flag asks for the sudo password, which Ansible needs once the role has removed passwordless sudo.

## Repository layout

~~~
packer/debian/        Packer template, variables and preseed template
ansible/              Inventory, playbook and the cis_debian13 role
docs/EXCEPTIONS.md    Recommendations not applied, with reasons
scanning/             Scan scripts (in progress)
reporting/            Before/after report generator (in progress)
windows-hardening/    Windows Server hardening (planned)
~~~

## Roadmap

- [x] Unattended Debian 13 build
- [x] CIS hardening role for Debian 13
- [ ] Lynis and OpenSCAP scans before and after hardening, with an HTML report
- [ ] Rocky Linux (RHEL compatible)
- [ ] Windows Server
- [ ] One command for the whole pipeline, plus CI checks

## Disclaimer

For lab use. The code references CIS recommendation IDs but does not include benchmark text, which CIS licenses separately. This project is not affiliated with CIS.

## Author

Dany Nogueira. Cybersecurity analyst working on CIS hardening and compliance automation. GitHub: [DanyCNog](https://github.com/DanyCNog)
