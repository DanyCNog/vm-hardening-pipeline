# Documented Exceptions — CIS Debian 13 Benchmark v1.0.0

| CIS ID | Control | Status | Justification |
|---|---|---|---|
| 1.1.2.x | Separate partitions (/var, /var/log, /home, ...) | Deferred | Requires partition layout at install time (preseed expert recipe). Planned. |
| 1.1.2.1.4 | noexec on /tmp | Exception | Packer uploads and executes provisioning scripts in /tmp. |
| 1.3.1.3 | All AppArmor profiles enforcing (L2) | Not applied | May break applications; profiles reviewed case by case. |
| 1.3.1.4 | apparmor_restrict_unprivileged_unconfined | Not applied | Kernel parameter availability to be validated on Debian 13. |
| 1.4.1 | Bootloader password | Exception | Unattended lab boots; console access is protected at hypervisor level. |
| 4.1.4 | UFW default deny outgoing (L2) | Not applied | Requires a per-destination egress allowlist (APT mirrors, NTP). |
| 5.3.2.4 / 5.3.3.3.x | pam_pwhistory | Deferred | Requires a dedicated pam-auth-update profile. Planned. |
| 6.2.2.3 / 6.2.2.4 | Halt/single-user when audit logs are full (L2) | Exception | Would halt the lab VM (20 GB disk). Production: apply with log forwarding. |
| 6.2.3.36 | Immutable audit rules (L2) | Not applied | Kept mutable in lab to allow iteration without reboots. |
| — | SSH PasswordAuthentication kept enabled | By design | Required by the Packer SSH communicator during the build. Not a CIS control. |
