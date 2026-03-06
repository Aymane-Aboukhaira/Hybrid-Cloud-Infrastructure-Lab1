# OpenMediaVault NAS Setup

## Overview

OpenMediaVault (OMV) deployed on VLAN 40 (Storage) at 192.168.40.40. Provides centralized file storage for the lab via SMB (Windows/admin access) and NFS (Linux VM access).

## Installation

OMV installed from official ISO. Post-install configuration via web UI at `http://192.168.40.40`.

## Storage Configuration

- Data disk: 30GB virtual disk
- Filesystem: ext4
- Mount point: `/srv/dev-disk-by-uuid-be8ecdd8-c168-4aac-9f39-7bb51bc81584`
- Share name: `lab-share`

## Firewall (ufw)

```bash
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # OMV web UI
sudo ufw allow 443/tcp   # HTTPS
sudo ufw allow 139/tcp   # SMB
sudo ufw allow 445/tcp   # SMB
sudo ufw allow 111/tcp   # NFS portmapper
sudo ufw allow 2049/tcp  # NFS
sudo ufw enable
```

## Recovery After VLAN Migration

After moving to VLAN 40 (192.168.40.40):
1. Update static IP in OMV web UI (Network → Interfaces)
2. Update NFS export allowed networks if using subnet restrictions
3. Update `/etc/fstab` on centos-vm1 to use new OMV IP
