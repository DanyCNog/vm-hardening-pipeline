# vm-hardening-pipeline

![ci](https://github.com/DanyCNog/vm-hardening-pipeline/actions/workflows/ci.yml/badge.svg)

Builds Debian 13, Rocky Linux 10 and Windows Server 2025 virtual machines from the official ISOs without manual steps, hardens them against the matching CIS benchmark, and scans each machine before and after. One command runs the whole pipeline for a platform: `make debian`, `make rocky` or `make windows`.

## Results

From the last full pipeline run. The final scan runs after a reboot, so it measures what persists.

| | Debian 13 | Rocky Linux 10 | Windows Server 2025 |
|---|---|---|---|
| Benchmark | CIS Debian Linux 13 v1.0.0 | CIS Red Hat Enterprise Linux 10 v1.0.1 | CIS Windows Server 2025 v1.0.0 |
| Hardening | Ansible role `cis_debian13` | Ansible role `cis_rhel10` | HardeningKitty, tailored list |
| Scanner | OpenSCAP + Lynis | OpenSCAP + Lynis | HardeningKitty |
| Checks passed | 248 → 350 | 171 → 283 | 147 → 465 |
| Checks failed | 125 → 41 | 121 → 10 | 351 → 33 |
| Pass rate | 66.5% → 89.5% | 58.6% → 96.6% | 29.5% → 93.4% |
| Scanner score | OpenSCAP 67.6 → 87.4 | OpenSCAP 73.7 → 94.2 | HardeningKitty 3.47 → 5.76 (1 to 6) |
| Lynis hardening index | 64 → 76 | 70 → 76 | n/a |

The remaining failures are explained in [docs/EXCEPTIONS.md](docs/EXCEPTIONS.md). Some are lab exceptions with a reason (bootloader password, a separate /tmp partition, remote management of a workgroup server). Twelve of the Windows ones are Domain Controller checks that do not apply to a member server. The rest are open work.

![Debian 13 report](docs/img/report-debian13.png)
![Rocky Linux 10 report](docs/img/report-rocky10.png)
![Windows Server 2025 report](docs/img/report-ws2025.png)

## How it works

~~~
ISO ─► Packer: unattended install (preseed / kickstart / autounattend.xml)
        ├─ baseline scan
        ├─ hardening (Ansible role, or HardeningKitty on Windows)
        ├─ reboot
        ├─ final scan
        └─ HTML report: before vs after
~~~

Packer checks each ISO against a pinned SHA-256 hash, creates a VirtualBox VM and hands the installer an answer file. The answer files are templates: Packer fills in the user name and password at build time from `lab.auto.pkrvars.hcl`, which Git ignores. The same `packer build` then runs the scans and the hardening, reboots, downloads the results and calls `reporting/make_report.sh` on the host.

On Windows, Packer talks to the VM over WinRM on HTTPS with NTLM. Basic authentication and unencrypted traffic are off from the first boot. HardeningKitty applies a tailored copy of the CIS list, the official list minus the exceptions in `windows-hardening/exceptions.txt`, after saving the previous values for rollback. The audit always uses the official list, so exceptions still count as failures in the report.

## What the scans showed

- ComplianceAsCode's Debian content only reads `/etc/ssh/sshd_config`, not the drop-in files in `sshd_config.d`. The first report had 18 SSH rules failing on a server that already refused root logins. The role now writes a managed block at the top of `sshd_config`, which is also where sshd takes the first value from.
- The kernel module checks look for `firewire-core` and `usb-storage` with a hyphen. modprobe accepts the underscore spelling, the checks do not.
- Debian ships `* hard core infinity` in `/etc/security/limits.d/10-coredump-debian.conf`. The role comments that line out, because the scanner fails if any file sets a value other than 0.
- On Debian 13 the kernel resets some network sysctl values when an interface comes up. A oneshot unit re-applies `/etc/sysctl.d` once the network is online. Rocky Linux 10 passed the same checks without it.
- On Rocky the SSH ciphers, MACs and key exchange come from the system crypto policy. The role sets `DEFAULT:NO-SSHCBC:NO-SSHWEAKCIPHERS:NO-SSHWEAKMACS:NO-WEAKMAC` instead of listing algorithms in `sshd_config`. PAM runs from a custom authselect profile; nothing in `/etc/pam.d` is edited by hand.
- On a Windows server outside a domain, two CIS settings block exactly what Packer needs: network logon and a full admin token for local administrator accounts. They are kept out of the applied list and documented, but still audited.
- Windows PowerShell 5.1 writes zip files with backslashes as path separators. `reporting/extract_zip.py` normalises them and refuses entries that would land outside the target folder (zip slip).

## Other details

- The Debian SSH server prefers `mlkem768x25519-sha256`, the hybrid post-quantum key exchange in OpenSSH 10 (CIS 5.1.13).
- The Linux installers give the admin user passwordless sudo for the first Ansible run. The roles remove it, but only after checking that the user is still in the `sudo` (Debian) or `wheel` (Rocky) group. If the check fails, the play stops.
- A second run of either playbook reports `changed=0`.
- VirtualBox on a host with Linux 6.12 or newer can fail with `VERR_VMX_IN_VMX_ROOT_MODE`, because KVM claims the CPU virtualization extensions when its module loads. `options kvm enable_virt_at_load=0` in `/etc/modprobe.d` fixes it without unloading KVM.

## Requirements

- Linux host with VirtualBox 7.x (developed on Kali Linux with VirtualBox 7.2), 16 GB of RAM recommended
- Packer 1.16 or newer (`packer init` installs the plugins)
- Ansible with the `ansible.posix` and `community.general` collections
- Debian scan: the ComplianceAsCode datastream, built with `./build_product debian13 --datastream-only` and copied to `scanning/content/`
- Windows: the Windows Server 2025 Evaluation ISO in `packer/windows/iso/ws2025-eval.iso`, and HardeningKitty v.0.9.4 cloned and zipped in `~/build/`

## Usage

~~~bash
cp packer/rocky/lab.auto.pkrvars.hcl.example packer/rocky/lab.auto.pkrvars.hcl   # set a password
make            # list the targets
make rocky      # build, scan, harden, reboot, scan, report
make reports    # rebuild the HTML reports from saved results
make check      # unit tests and static checks, same as CI
~~~

Reports are written to `reporting/output/`.

## Repository layout

~~~
packer/{debian,rocky,windows}/  Packer templates and installer answer files
ansible/roles/                  cis_debian13 and cis_rhel10 roles
windows-hardening/              Exceptions, list tailoring and the HardeningKitty step
scanning/{linux,windows}/       Scan scripts
reporting/                      Report generators, zip extraction, make_report.sh
tests/                          Unit tests for the report and list tools
docs/EXCEPTIONS.md              What is not applied, and why
Makefile                        One command per platform
.github/workflows/ci.yml        Static checks on every push
~~~

## Possible next steps

- Bootloader password and separate partitions on Linux
- User rights assignments on Windows, and a domain-joined variant where the management exceptions go away
- An Ubuntu 24.04 pipeline

## Disclaimer

For lab use. The code references CIS recommendation IDs but does not include benchmark text, which CIS licenses separately. HardeningKitty finding lists are downloaded at build time and not redistributed here. This project is not affiliated with CIS.

## Author

Dany Nogueira. Cybersecurity analyst working on CIS hardening and compliance automation. GitHub: [DanyCNog](https://github.com/DanyCNog)
