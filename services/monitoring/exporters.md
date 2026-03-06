# Monitoring Exporters

## node-exporter (Linux VMs)

Deployed as a Podman container on centos-vm1 and centos-vm2.

```yaml
# /opt/node-exporter/docker-compose.yml
version: '3.8'
services:
  node_exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    ports:
      - "9100:9100"
    restart: unless-stopped
```

```bash
cd /opt/node-exporter && podman-compose up -d
```

**Metrics collected**: CPU usage, memory, disk I/O, network throughput, filesystem usage, system load, running processes.

## windows-exporter (DC01)

Installed as a Windows Service on DC01. Download from [windows_exporter releases](https://github.com/prometheus-community/windows_exporter/releases).

```powershell
# Install with specific collectors
windows_exporter-x.x.x-amd64.exe `
    --collectors.enabled "cpu,memory,logical_disk,net,os,service,process" `
    install

Start-Service windows_exporter
```

**Firewall rule** (allow Prometheus to scrape):
```powershell
New-NetFirewallRule -DisplayName "Prometheus windows-exporter" `
    -Direction Inbound -Protocol TCP -LocalPort 9182 `
    -RemoteAddress 192.168.20.30 -Action Allow
```

**Metrics collected**: CPU per-core, memory (working set, committed), disk (IOPS, latency), network, Windows services state, process list.

## Prometheus Target Status

All targets verified UP after VLAN migration with updated IPs in `prometheus.yml`:

| Target | URL | Status |
|---|---|---|
| prometheus | localhost:9090 | ✅ UP |
| centos-vm1 | 192.168.30.20:9100 | ✅ UP |
| centos-vm2 | 192.168.20.30:9100 | ✅ UP |
| windows-dc01 | 192.168.10.10:9182 | ✅ UP |

## Troubleshooting Target Down

```bash
# Test connectivity from centos-vm2 to target
curl http://192.168.30.20:9100/metrics | head -20

# Check firewalld on CentOS target
firewall-cmd --list-all

# Check Windows Firewall on DC01
Get-NetFirewallRule -DisplayName "*exporter*" | Select-Object DisplayName,Enabled,Direction
```
