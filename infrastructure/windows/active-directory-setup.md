# Active Directory Setup — DC01

## Overview

Windows Server 2022 running on VLAN 10 (Management) at 192.168.10.10. DC01 is the domain controller for `lab.local` and provides AD DS, DNS, and DHCP for the lab environment.

## Domain Configuration

| Parameter | Value |
|---|---|
| Domain | lab.local |
| NetBIOS | LAB |
| Forest/Domain level | Windows Server 2016 |
| DC hostname | DC01 |
| IP | 192.168.10.10 |
| DNS | Self (127.0.0.1 primary) |

## Installation Steps

### 1. Set Static IP
Network & Internet Settings → Change adapter options → IPv4:
- IP: 192.168.10.10
- Mask: 255.255.255.0
- Gateway: 192.168.10.1
- DNS: 127.0.0.1 (points to itself)

### 2. Install AD DS Role
```powershell
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
```

### 3. Promote to Domain Controller
```powershell
Install-ADDSForest `
    -DomainName "lab.local" `
    -DomainNetbiosName "LAB" `
    -ForestMode "WinThreshold" `
    -DomainMode "WinThreshold" `
    -InstallDns:$true `
    -Force:$true
```

### 4. Install DHCP Role
```powershell
Install-WindowsFeature DHCP -IncludeManagementTools
Add-DhcpServerv4Scope -Name "Lab VLAN 10" -StartRange 192.168.10.50 -EndRange 192.168.10.99 -SubnetMask 255.255.255.0
```

### 5. Enable RDP
```powershell
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
```

### 6. Install Windows Exporter (Prometheus)
Download from: https://github.com/prometheus-community/windows_exporter/releases

```powershell
# Install as Windows service
windows_exporter-x.x.x-amd64.exe --collectors.enabled "cpu,memory,logical_disk,net,os,service" install
Start-Service windows_exporter
```

Exposes metrics on port 9182. Add Windows Firewall rule to allow inbound 9182/TCP from Prometheus (192.168.20.30).

## LDAP Integration Notes

For Guacamole LDAP authentication:
- LDAP server: 192.168.10.10
- LDAP port: 389
- User base DN: `CN=Users,DC=lab,DC=local`
- Username attribute: `sAMAccountName`
- Bind account: domain administrator credentials

Users in Active Directory can log into Guacamole directly with their AD credentials.

## Planned Phase 2 — NPS/RADIUS

Install the Network Policy Server role to enable RADIUS authentication:
```powershell
Install-WindowsFeature NPAS -IncludeManagementTools
```

NPS will act as a RADIUS server, with Guacamole, pfSense, and Proxmox configured as RADIUS clients. This replaces the current LDAP integration with the enterprise-standard RADIUS protocol.
