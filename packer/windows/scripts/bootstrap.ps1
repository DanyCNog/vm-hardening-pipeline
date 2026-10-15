# Runs once at first logon (autounattend FirstLogonCommands).
# Sets up WinRM over HTTPS with NTLM so Packer can manage the VM.
$ErrorActionPreference = 'Stop'
Start-Transcript -Path C:\Windows\Temp\bootstrap.log

# Wait for the network profile, then mark it Private (WinRM firewall rules need it)
for ($i = 0; $i -lt 30; $i++) {
    $profiles = Get-NetConnectionProfile -ErrorAction SilentlyContinue
    if ($profiles) { $profiles | Set-NetConnectionProfile -NetworkCategory Private; break }
    Start-Sleep -Seconds 2
}

Enable-PSRemoting -SkipNetworkProfileCheck -Force

# Lab exception (documented): a workgroup machine managed remotely with a local admin account.
# CIS 'Apply UAC restrictions to local accounts on network logons' expects 0.
New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' `
    -Name LocalAccountTokenFilterPolicy -Value 1 -PropertyType DWord -Force | Out-Null

# HTTPS listener with a self-signed certificate; remove the HTTP listener
$cert = New-SelfSignedCertificate -DnsName $env:COMPUTERNAME `
    -CertStoreLocation Cert:\LocalMachine\My -NotAfter (Get-Date).AddYears(1)
Get-ChildItem WSMan:\localhost\Listener |
    Where-Object { $_.Keys -contains 'Transport=HTTP' } |
    Remove-Item -Recurse -Force
New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * `
    -CertificateThumbPrint $cert.Thumbprint -Force | Out-Null

# No Basic auth, no unencrypted traffic (CIS WinRM Service settings)
Set-Item WSMan:\localhost\Service\Auth\Basic -Value $false
Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value $false
Set-Item WSMan:\localhost\MaxTimeoutms -Value 1800000

# Firewall: HTTPS only
Get-NetFirewallRule | Where-Object Name -like 'WINRM-HTTP-In-TCP*' | Disable-NetFirewallRule
New-NetFirewallRule -Name 'WINRM-HTTPS-In-TCP' -DisplayName 'Windows Remote Management (HTTPS-In)' `
    -Direction Inbound -Protocol TCP -LocalPort 5986 -Action Allow -Profile Any | Out-Null

Stop-Transcript
