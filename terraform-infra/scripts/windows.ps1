<powershell>
# Disable Windows Update service
Stop-Service -Name wuauserv -Force
Set-Service -Name wuauserv -StartupType Disabled

# Disable automatic updates via registry
New-Item -Path "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\WindowsUpdate\\AU" -Force
Set-ItemProperty -Path "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\WindowsUpdate\\AU" `
  -Name NoAutoUpdate -Value 1 -Type DWord

# Log intentional vulnerable state
"Intentional vulnerable state configured" | Out-File C:\\vuln-lab.txt
</powershell>