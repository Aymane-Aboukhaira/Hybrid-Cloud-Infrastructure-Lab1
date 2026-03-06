# Grafana Dashboards

## Access
URL: `http://192.168.20.30:3000`
Default credentials: admin / admin (change on first login)

## Imported Dashboards

### Node Exporter Full (ID: 1860)
Comprehensive Linux system metrics dashboard.

Import: Dashboards → Import → Enter ID `1860` → Load → Select Prometheus datasource

**Key panels used:**
- CPU usage (per-core and total)
- Memory usage (used/available/cached)
- Disk I/O (reads/writes per second)
- Network throughput (in/out)
- System load average
- Filesystem usage percentage

### Windows Exporter 2024 (ID: 20763)
Windows Server metrics dashboard.

Import: Dashboards → Import → Enter ID `20763` → Load → Select Prometheus datasource

**Key panels used:**
- CPU utilization
- Memory (working set, page file)
- Disk latency and IOPS
- Network adapter throughput
- Windows services status

## Prometheus Datasource Configuration

1. Grafana → Configuration → Data Sources → Add data source
2. Type: Prometheus
3. URL: `http://localhost:9090` (Prometheus is on the same host)
4. Save & Test → should show "Data source is working"

## Planned Enhancements (Month 5)

- **Alerting**: CPU > 80%, RAM > 90%, disk > 85%, target down → email via Postfix (Phase 3)
- **Loki**: Add log aggregation datasource alongside Prometheus
- **Dashboard annotations**: Mark incident events on time-series graphs
