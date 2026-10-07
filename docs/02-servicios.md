# Servicios Systemd

El sistema se compone de varios servicios y timers de **systemd** que trabajan de forma coordinada para mantener operativo Technitium DNS Server, actualizar el DDNS, supervisar la disponibilidad, generar backups y renovar certificados TLS automáticamente.

## 📊 Resumen de servicios

| Servicio | Tipo | Frecuencia | Función |
|----------|------|------------|---------|
| dns.service | Servicio | Continuo | Technitium DNS Server (núcleo del sistema) |
| cloudflare-ddns.service | Servicio oneshot | Bajo demanda | Actualiza IP en Cloudflare |
| cloudflare-ddns.timer | Timer | Cada 15 min | Dispara el servicio DDNS |
| dns-backup.service | Servicio oneshot | Bajo demanda | Crea backup completo |
| dns-backup.timer | Timer | Semanal (lunes 00:05) | Dispara el backup |
| dns-healthcheck.service | Servicio oneshot | Bajo demanda | Verifica estado del sistema |
| dns-healthcheck.timer | Timer | Cada 5 min | Dispara el healthcheck |
| certbot.timer | Timer del sistema | 2 veces al día | Verifica renovación SSL |

## 🔧 Descripción detallada

### dns.service
**Qué es**: Servicio principal que ejecuta Technitium DNS Server.  
**Archivo**: `/etc/systemd/system/dns.service` · **Usuario**: `dns-server`  
**Función**: Resolver DNS recursivamente, servir DoT/DoH, validar DNSSEC y bloquear dominios.
```bash
sudo systemctl status dns.service
sudo systemctl restart dns.service
sudo journalctl -u dns.service -f
```

### cloudflare-ddns.service + .timer
**Qué es**: Actualiza los registros DNS de Cloudflare cuando cambia la IP pública y actualiza Split Horizon en Technitium.  
**Archivos**: `/etc/systemd/system/cloudflare-ddns.service`, `/etc/systemd/system/cloudflare-ddns.timer`  
**Frecuencia**: Cada 15 minutos (+5 min tras boot). · **Log**: `/var/log/cloudflare-ddns.log`
```bash
sudo systemctl start cloudflare-ddns.service
sudo systemctl list-timers | grep cloudflare
sudo tail -f /var/log/cloudflare-ddns.log
```

### dns-healthcheck.service + .timer
**Qué es**: Watchdog que verifica que Technitium responda en 5 endpoints; tras 2 fallos consecutivos reinicia `dns.service`.  
**Archivos**: `/etc/systemd/system/dns-healthcheck.service`, `/etc/systemd/system/dns-healthcheck.timer`  
**Frecuencia**: Cada 5 minutos (+2 min tras boot). · **Log**: `/var/log/dns-healthcheck.log`
```bash
sudo systemctl start dns-healthcheck.service
sudo tail -f /var/log/dns-healthcheck.log
```

### dns-backup.service + .timer
**Qué es**: Crea un backup completo de la configuración del servidor DNS.  
**Archivos**: `/etc/systemd/system/dns-backup.service`, `/etc/systemd/system/dns-backup.timer`  
**Frecuencia**: Semanal (lunes ~00:05). · **Destino**: `/root/backups/` · **Retención**: 30 días · **Log**: `/var/log/dns-backup.log`
```bash
sudo systemctl start dns-backup.service
sudo ls -lh /root/backups/
sudo tail -f /var/log/dns-backup.log
```

### certbot.timer
**Qué es**: Timer del sistema que renueva el certificado SSL de Let's Encrypt.  
**Frecuencia**: 2 veces al día; verifica si faltan menos de 30 días para expirar.  
**Función**: Emitir un nuevo certificado y ejecutar el hook para regenerar el PFX.
```bash
sudo systemctl status certbot.timer
sudo certbot renew --dry-run
sudo certbot certificates
```

## 🔍 Ver todos los servicios de una vez
```bash
sudo systemctl list-timers
sudo systemctl list-timers | grep -E "cloudflare|dns-backup|dns-healthcheck"
systemctl list-units --type=service --state=running | grep -E "dns|cloudflare"
```

## 🎯 Orden de arranque al encender el servidor
1. El sistema operativo inicia.
2. `dns.service` arranca Technitium.
3. `cloudflare-ddns.timer` se activa → primera ejecución tras 5 min.
4. `dns-healthcheck.timer` se activa → primera ejecución tras 2 min.
5. `dns-backup.timer` se activa → próxima ejecución programada.
6. `certbot.timer` se activa → próxima ejecución programada.

## 📌 Referencias
- Units systemd: [`units/`](units/)
- Scripts: [`scripts/`](scripts/)
- Troubleshooting: [`troubleshooting.md`](troubleshooting.md)

> Última actualización: 2026-10-07
