# Servidor DNS Autónomo Recursivo

Este repositorio documenta un servidor DNS personal y autónomo basado en **Technitium DNS Server v15.6**, desplegado sobre Ubuntu Server 24.04 y accesible mediante el dominio propio `dns.emmanuel-mx.com`. La plataforma ofrece resolución DNS recursiva con **DNS-over-TLS (DoT)**, **DNS-over-HTTPS (DoH)**, **DNSSEC**, **Split Horizon** y una **blocklist de más de 1 millón de dominios**. También incorpora actualización **DDNS automática**, supervisión mediante watchdog, copias de seguridad programadas y renovación automática de certificados TLS.

## 📋 Índice de documentación

- [Arquitectura general](docs/01-arquitectura.md) — Visión general del sistema
- [Servicios systemd](docs/02-servicios.md) — Lista completa de servicios y timers
- **Scripts**:
  - [cloudflare-ddns.sh](docs/scripts/cloudflare-ddns.md) — DDNS + Split Horizon
  - [dns-backup.sh](docs/scripts/dns-backup.md) — Backup automático
  - [dns-healthcheck.sh](docs/scripts/dns-healthcheck.md) — Watchdog
- **Units systemd**:
  - [dns.service](docs/units/dns-service.md) — Servicio de Technitium
  - [cloudflare-ddns units](docs/units/cloudflare-ddns-units.md) — Service + Timer DDNS
  - [dns-backup units](docs/units/dns-backup-units.md) — Service + Timer backup
  - [dns-healthcheck units](docs/units/dns-healthcheck-units.md) — Service + Timer watchdog
- [Troubleshooting](docs/troubleshooting.md) — Solución de problemas comunes
- [Recovery](docs/recovery.md) — Recuperación tras desastres

## 🏗️ Arquitectura rápida

```text
Cliente
  │
  ▼
Router
  │
  ▼
Servidor DNS
192.168.1.121
  │
  ▼
Technitium DNS Server
  │
  ├── cloudflare-ddns (cada 15 min)
  ├── dns-healthcheck (cada 5 min)
  └── dns-backup (semanal)
```

## 🚨 Comandos de emergencia

| Acción | Comando |
|--------|---------|
| Ver estado de Technitium | `sudo systemctl status dns.service` |
| Reiniciar Technitium | `sudo systemctl restart dns.service` |
| Ver todos los timers | `sudo systemctl list-timers \| grep -E "cloudflare\|dns-backup\|dns-healthcheck"` |
| Forzar actualización DDNS | `sudo systemctl start cloudflare-ddns.service` |
| Forzar backup | `sudo systemctl start dns-backup.service` |
| Ver logs en vivo (DDNS) | `sudo tail -f /var/log/cloudflare-ddns.log` |
| Ver logs en vivo (Healthcheck) | `sudo tail -f /var/log/dns-healthcheck.log` |

## 🆘 Recuperación de emergencia

Si el servidor falla completamente:

1. Ver [`docs/recovery.md`](docs/recovery.md)
2. Restaurar desde backup: `/root/backups/dns-backup-*.tar.gz`

## 📌 Información del servidor

- **IP LAN**: 192.168.1.121
- **Dominio**: dns.emmanuel-mx.com
- **DNS-over-TLS**: puerto 853
- **DNS-over-HTTPS**: puerto 443
- **Dashboard HTTPS**: puerto 53443
- **Dashboard HTTP (solo LAN)**: puerto 5380

> Última actualización: 2026-10-07
