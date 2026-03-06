# NFS Share Configuration

## OMV NFS Setup

In OMV Web UI:
1. Services → NFS → Enable NFS
2. Shares → Add:
   - Shared folder: lab-share
   - Client: 192.168.20.0/24 (SERVICES VLAN — centos-vm2 backup access)
   - Privilege: Read/Write
   - Extra options: `sync,no_subtree_check`

## centos-vm1 Persistent Mount

```bash
# /etc/fstab entry
192.168.40.40:/srv/.../lab-share  /mnt/nas  nfs  defaults,_netdev  0  0
```

```bash
# Mount manually (first time)
sudo mkdir -p /mnt/nas
sudo mount -a

# Verify
df -h | grep nas
```

The `_netdev` option tells systemd to wait for network before mounting — prevents boot failures if NAS is not yet available.
