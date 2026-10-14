# VM Hardening Pipeline

Automated, reproducible pipeline that turns an installation ISO into a hardened virtual machine and proves it with before/after security scans.

**Status:** 🚧 Work in progress

## How it works

~~~
ISO ──► Packer builds VM (unattended install)
          ├─► Baseline scan
          ├─► Hardening (Ansible / PowerShell)
          ├─► Final scan
          └─► HTML report: before vs after
~~~

## Stack

| Layer | Tool |
|---|---|
| Image build | Packer + VirtualBox |
| Linux hardening | Ansible |
| Windows hardening | PowerShell (local policy) |
| Linux audit | Lynis, OpenSCAP |
| Windows audit | HardeningKitty |

## Target platforms

- Debian 13
- Rocky Linux 9 (RHEL-compatible)
- Windows Server (Evaluation)

## Roadmap

- [x] Project structure
- [x] Debian 13 unattended build
- [x] Debian CIS-based hardening
- [ ] Before/after scan + HTML report
- [ ] Rocky Linux
- [ ] Windows Server
- [ ] Single-command orchestration + CI

## Disclaimer

Lab use only. Controls reference CIS Benchmark IDs; benchmark text is not redistributed (CIS licensing). Not affiliated with CIS.

## Author

Dany Nogueira — Cybersecurity Analyst · CIS hardening & compliance automation
