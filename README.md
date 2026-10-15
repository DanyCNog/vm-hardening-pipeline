# vm-hardening-pipeline

Builds Debian 13 and Rocky Linux 10 virtual machines from the official ISOs without manual steps, hardens them with Ansible against the matching CIS benchmark, and scans each machine before and after hardening. Each task in the Ansible roles is named after the CIS recommendation it implements.

Status: Debian 13 and Rocky Linux 10 work end to end. Windows Server 2025 is in progress.

## Results

From the last full pipeline run. The final scan runs after a reboot, so it measures what persists.

| | Debian 13 | Rocky Linux 10 |
|---|---|---|
| Benchmark | CIS Debian Linux 13 v1.0.0 | CIS Red Hat Enterprise Linux 10 v1.0.1 |
| OpenSCAP profile | Level 1 Server | Level 1 Server |
| Rules passed | 248 → 350 | 171 → 283 |
| Rules failed | 125 → 41 | 121 → 10 |
| Pass rate | 66.5% → 89.5% | 58.6% → 96.6% |
| OpenSCAP score | 67.6 → 87.4 | 73.7 → 94.2 |
| Lynis hardening index | 64 → 76 | 70 → 76 |

Many of the remaining failures are listed in [docs/EXCEPTIONS.md](docs/EXCEPTIONS.md) with a reason, for example the bootloader password, a separate /tmp partition and remote log upload. The others are open work.

![Debian 13 report](docs/img/report-debian13.png)
![Rocky Linux 10 report](docs/img/report-rocky10.png)

## How it works

~~~
ISO ─► Packer: unattended install (preseed / kickstart)
        ├─ baseline scan: OpenSCAP + Lynis
        ├─ Ansible role (cis_debian13 / cis_rhel10)
        ├─ reboot
        ├─ final scan
        └─ HTML report: before vs after
~~~

Packer checks the ISO against a pinned SHA-256 hash, creates a VirtualBox VM and serves the answer file to the installer. The answer files are templates: Packer fills in the user name and password at build time from `lab.auto.pkrvars.hcl`, which Git ignores. After the install, the same `packer build` runs the scans, the Ansible role and the reboot, downloads the results and generates the report on the host.

The Debian scan uses the CIS profile built from ComplianceAsCode. Rocky Linux uses the `scap-security-guide` package that ships with the distribution. One scan script handles both and picks the datastream and profile on its own.

## What the scans showed

- ComplianceAsCode's Debian content only reads `/etc/ssh/sshd_config`, not the drop-in files in `sshd_config.d`. The first report had 18 SSH rules failing on a server that already refused root logins. The role now writes a managed block at the top of `sshd_config`, which is also where sshd takes the first value from.
- The kernel module checks look for `firewire-core` and `usb-storage` with a hyphen. modprobe accepts the underscore spelling, the checks do not.
- Debian ships `* hard core infinity` in `/etc/security/limits.d/10-coredump-debian.conf`. The role comments that line out, because the scanner fails if any file sets a value other than 0.
- On Debian 13 the kernel resets some network sysctl values when an interface comes up. A oneshot unit re-applies `/etc/sysctl.d` once the network is online. Rocky Linux 10 passed the same checks without it.
- On Rocky the SSH ciphers, MACs and key exchange come from the system crypto policy. The role sets `DEFAULT:NO-SSHCBC:NO-SSHWEAKCIPHERS:NO-SSHWEAKMACS:NO-WEAKMAC` instead of listing algorithms in `sshd_config`.
- PAM on Rocky runs from a custom authselect profile with `with-faillock`, `with-pwhistory` and `without-nullok`. Nothing in `/etc/pam.d` is edited by hand.

## Other details

- The Debian SSH server prefers `mlkem768x25519-sha256`, the hybrid post-quantum key exchange in OpenSSH 10 (CIS 5.1.13).
- The installers give the admin user passwordless sudo for the first Ansible run. The roles remove it, but only after checking that the user is still in the `sudo` (Debian) or `wheel` (Rocky) group. If the check fails, the play stops.
- A second run of either playbook reports `changed=0`.
- VirtualBox on a host with Linux 6.12 or newer can fail with `VERR_VMX_IN_VMX_ROOT_MODE`, because KVM claims the CPU virtualization extensions when its module loads. `options kvm enable_virt_at_load=0` in `/etc/modprobe.d` fixes it without unloading KVM.

## Requirements

- Linux host with VirtualBox 7.x (developed on Kali Linux with VirtualBox 7.2)
- Packer 1.16 or newer, with the `virtualbox` and `ansible` plugins (`packer init` installs them)
- Ansible with the `ansible.posix` and `community.general` collections
- For the Debian scan: the ComplianceAsCode datastream, built with `./build_product debian13 --datastream-only` and copied to `scanning/content/`

Each Linux VM gets 2 vCPUs, 2 GB of RAM and a 20 GB dynamically allocated disk.

## Usage

~~~bash
cd packer/rocky        # or packer/debian
cp lab.auto.pkrvars.hcl.example lab.auto.pkrvars.hcl   # then set ssh_password
packer init .
packer build .
~~~

The report is written to `reporting/output/`.

## Repository layout

~~~
packer/debian/          Packer template, variables, preseed template
packer/rocky/           Packer template, variables, kickstart template
ansible/roles/          cis_debian13 and cis_rhel10 roles
scanning/linux/         Scan script (Lynis + OpenSCAP)
reporting/              Before/after report generator
docs/EXCEPTIONS.md      Recommendations not applied, with reasons
windows-hardening/      Windows Server work (in progress)
~~~

## Roadmap

- [x] Unattended Debian 13 build and CIS role
- [x] Unattended Rocky Linux 10 build and CIS role
- [x] Before/after scans with an HTML report
- [ ] Windows Server 2025 (Packer, HardeningKitty)
- [ ] One command for the whole pipeline, plus CI checks

## Disclaimer

For lab use. The code references CIS recommendation IDs but does not include benchmark text, which CIS licenses separately. This project is not affiliated with CIS.

## Author

Dany Nogueira. Cybersecurity analyst working on CIS hardening and compliance automation. GitHub: [DanyCNog](https://github.com/DanyCNog)
