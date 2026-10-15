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

## Scanner findings that are not configuration gaps

| Platform | CIS ID | Finding | Explanation |
|---|---|---|---|
| Debian 13 | 3.3.1.13 | `net.ipv4.conf.default.rp_filter` | systemd ships the value 2 in `/usr/lib/sysctl.d/50-default.conf`. The role sets 1 in `/etc/sysctl.d`, which wins at runtime, and the runtime check passes. Vendor files are not edited. |
| Debian 13 | 5.3.3.1.1, 5.3.3.1.2 | pam_faillock layout | Configured with pam-auth-update profiles. The ComplianceAsCode check expects a different line layout in `common-auth`. Lockout behaviour still to be tested. |
| Debian 13 | 6.1.2.x | rsyslog | journald is the single logging system (6.1.1.x). The rsyslog recommendations are the alternative path in the benchmark. |
| Both | Debian 6.1.1.2.2, 6.1.1.2.3 / RHEL 6.2.2.1.3 | systemd-journal-upload | Needs a remote log collector, which the lab does not have. |
| Rocky 10 | 1.2.1.1 | Red Hat GPG key | Rocky packages are signed with Rocky keys. The RHEL content looks for the Red Hat key. |
| Rocky 10 | 5.4.2.4 | root password | root is locked by design (`rootpw --lock` in the kickstart). |
| Rocky 10 | 6.3.x | auditd rules | Level 2 in the RHEL 10 benchmark. auditd is active by default; the rule set is planned. |

## Windows Server 2025

Settings are applied with HardeningKitty from a tailored copy of the CIS finding list. The audit always uses the official list, so the items below still show as failed in the report. The list of exceptions lives in `windows-hardening/exceptions.txt`.

| Setting | Status | Explanation |
|---|---|---|
| Deny access to this computer from the network (local accounts in Administrators) | Exception | The lab has no domain. Packer manages the VM over WinRM with a local administrator account, which this setting blocks. In a domain, management uses domain accounts and the setting applies. |
| Apply UAC restrictions to local accounts on network logons | Exception | Same reason. Without `LocalAccountTokenFilterPolicy = 1`, a local administrator gets a filtered token over WinRM and cannot manage the machine. |
| Allow remote server management through WinRM / Allow Remote Shell Access (Level 2) | Not applied | Would close the channel Packer uses. Listed so they are never applied by accident if the list includes them. |
| WinRM transport | By design | HTTPS with a self-signed certificate and NTLM. Basic authentication and unencrypted traffic are disabled, as CIS requires. |

### Windows Server 2025: remaining checks after hardening

| Group | Count | Explanation |
|---|---|---|
| Domain Controller only checks | 12 | The HardeningKitty list includes items marked (DC). They do not apply to a member server. |
| User rights assignments | 13 | Not changed by HailMary in this run, including the documented exception for network logon. Open work. |
| Site specific values | 4 | Renaming the Administrator and Guest accounts and the logon message text and title need values chosen by the organisation. |
| Credential Guard, force logoff | 2 | Credential Guard needs virtualization based security in the VM. Open work. |
