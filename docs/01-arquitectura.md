# Arquitectura del Sistema

Este sistema implementa un servidor DNS autónomo y recursivo sobre **Ubuntu Server 24.04 LTS**, ejecutado en el host `cigserver` con IP LAN `192.168.1.121`. Su núcleo es **Technitium DNS Server v15.6**, complementado por servicios systemd para DDNS, supervisión, backups y renovación automática de certificados. La arquitectura proporciona DNS estándar, DoT, DoH, DNSSEC, Split Horizon y filtrado mediante blocklist. Para una visión general del proyecto, consulta el [README principal](../README.md).

## 🎯 Componentes principales

| Componente | Tipo | Función |
|------------|------|---------|
| Technitium DNS Server | Servicio principal | Resuelve DNS recursivamente, sirve DoT/DoH, valida DNSSEC, bloquea dominios |
| cloudflare-ddns | Servicio auxiliar | Mantiene los registros DNS de Cloudflare actualizados con la IP pública |
| dns-healthcheck | Servicio auxiliar | Vigila que Technitium responda correctamente y lo reinicia si falla |
| dns-backup | Servicio auxiliar | Crea backups completos de la configuración |
| certbot | Servicio del sistema | Renueva el certificado SSL de Let's Encrypt |

## 🔄 Diagrama de flujo

```text
Internet
   ↓
Router (192.168.1.254) — Port Forwarding: 53, 443, 853, 53443
   ↓
Servidor DNS (192.168.1.121)
   ├── Technitium (dns.service)
   │    ├── Puerto 53    → DNS estándar (TCP/UDP)
   │    ├── Puerto 853   → DoT
   │    ├── Puerto 443   → DoH
   │    ├── Puerto 5380  → Dashboard HTTP (solo LAN)
   │    └── Puerto 53443 → Dashboard HTTPS
   │
   ├── cloudflare-ddns.timer (cada 15 min)
   │    ├── Actualiza registros A/AAAA en Cloudflare
   │    └── Actualiza Split Horizon en Technitium
   │
   ├── dns-healthcheck.timer (cada 5 min)
   │    └── Verifica endpoints, reinicia si falla
   │
   └── dns-backup.timer (semanal)
        └── Backup de configs → /root/backups/
```

## 🌐 Puertos expuestos

| Puerto | Protocolo | Servicio | Descripción |
|--------|-----------|----------|-------------|
| 53 | TCP + UDP | Technitium | DNS estándar |
| 443 | TCP + UDP | Technitium | DoH |
| 853 | TCP + UDP | Technitium | DoT |
| 53443 | TCP | Technitium | Dashboard HTTPS (remoto) |
| 5380 | TCP | Technitium | Dashboard HTTP (solo LAN) |

## 🔒 Seguridad

- Certificado SSL de Let's Encrypt con renovación automática.
- Validación criptográfica DNSSEC.
- Blocklist de más de 1 millón de dominios.
- Rate limiting (QPM) para reducir abuso.
- Firewall UFW configurado.
- SSH accesible únicamente desde la LAN como configuración recomendada.

## 🎯 Split Horizon

El **Split Horizon** permite que `dns.emmanuel-mx.com` responda de forma distinta según el origen de la consulta. Cuando el cliente está dentro de la LAN, el dominio resuelve a `192.168.1.121`. Cuando la consulta proviene desde fuera de la red local, resuelve a la IP pública vigente. Así, los dispositivos pueden utilizar el mismo nombre de dominio tanto dentro como fuera de la red sin cambiar su configuración.

## 📊 Flujo del DDNS

Cada 15 minutos, `cloudflare-ddns.timer` ejecuta el proceso de actualización:

1. Consulta la IP pública desde 3 fuentes.
2. Compara la IP obtenida con la registrada en Cloudflare.
3. Si cambió, actualiza el registro A.
4. Si cambió, actualiza la configuración de Split Horizon.
5. Si cambió Split Horizon, reinicia `dns.service`.

## 📌 Servidor

- **Hostname**: cigserver
- **IP LAN**: 192.168.1.121
- **Ubuntu Server**: 24.04 LTS
- **Technitium**: v15.6
- **Usuario servicio DNS**: dns-server

> Última actualización: 2026-10-07
