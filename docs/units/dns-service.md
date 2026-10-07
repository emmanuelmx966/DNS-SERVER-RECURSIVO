# Unit: dns.service
Servicio systemd principal que ejecuta **Technitium DNS Server v15.6**, núcleo del servidor DNS. Mantiene el proceso en ejecución continua y expone resolución DNS, DoT, DoH, DNSSEC, filtrado, Split Horizon y los dashboards web.
## 📍 Ubicación
- **Archivo**: `/etc/systemd/system/dns.service` · **Creado por**: instalador oficial de Technitium
- **Usuario/Grupo**: `dns-server:dns-server` · **Tipo**: servicio de larga duración
## 🎯 Qué es
Responsable de resolver DNS recursivamente, servir DoT `853`, DoH `443`, validar DNSSEC, aplicar blocklist 1M+, dashboards `5380/53443`, Split Horizon y rate limiting (QPM).
## 📄 Contenido típico del archivo
```ini
[Unit]
Description=Technitium DNS Server
After=network.target
[Service]
Type=notify
User=dns-server
Group=dns-server
WorkingDirectory=/opt/technitium/dns
ExecStart=/usr/bin/dotnet /opt/technitium/dns/DnsServerApp.dll /etc/dns
Restart=on-failure
RestartSec=10
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
```
> El unit real puede variar. Verificar siempre con `sudo systemctl cat dns.service`.
## 🔄 Ciclo de vida
```text
Boot → network.target → dotnet DnsServerApp.dll /etc/dns
  ↓ carga config, zonas, apps, blocklists y PFX
  ↓ escucha 53 / 853 / 443 / 5380 / 53443
  ├── fallo → Restart=on-failure
  └── reboot/stop → systemd lo detiene
```
## 📊 Estado del servicio
| Estado | Significado |
|---|---|
| `active (running)` | ✅ Operativo |
| `inactive (dead)` / `failed` | ⛔ Detenido / ❌ Falló |
| `activating` / `deactivating` | 🔄 Transición |
## 🛠️ Comandos útiles
```bash
sudo systemctl status dns.service; sudo systemctl is-active dns.service; sudo systemctl is-enabled dns.service
sudo systemctl restart dns.service; sudo systemctl stop dns.service; sudo systemctl start dns.service
sudo systemctl enable dns.service; sudo systemctl cat dns.service
sudo journalctl -u dns.service -f; sudo journalctl -u dns.service -n 50
```
## 🔐 Usuario `dns-server`
Usuario de sistema no interactivo que limita el impacto de una eventual vulnerabilidad. Debe poder leer `/etc/dns` y `/etc/technitium`; el PFX debe ser accesible por `dns-server:dns-server`.
Verificación: `id dns-server` y `sudo find /etc/dns /etc/technitium -user dns-server`.
## 🚨 Solución de problemas
- **No arranca**: `sudo journalctl -u dns.service -n 100 --no-pager`; revisar puerto ocupado, PFX ausente y permisos.
- **Running pero no responde**: `sudo ss -tulpn | grep dotnet`; revisar `/etc/dns/` y reiniciar el servicio.
- **Puerto 53 ocupado**: `sudo ss -tulpn | grep :53`; si es `systemd-resolved`, desactivar `DNSStubListener` y reiniciar ambos servicios.
- **Se cae repetidamente**: `sudo journalctl -u dns.service --since "10 minutes ago" | grep -iE "error|fail|crash"` y `sudo dmesg | tail -20`.
## 📌 Relación con otros servicios
`cloudflare-ddns.service` puede reiniciarlo al cambiar Split Horizon; `dns-healthcheck.service` lo reinicia ante fallos; `dns-backup.service` respalda su configuración; `certbot.timer` puede provocar reinicio vía hook tras renovar certificados.
## 📌 Referencias
- Technitium DNS Server: <https://technitium.com/dns/>
- Servicios generales: [`../02-servicios.md`](../02-servicios.md) · Troubleshooting: [`../troubleshooting.md`](../troubleshooting.md)
> Última actualización: 2026-10-07
