# Units: dns-healthcheck
Par `service` + `timer` que ejecuta el watchdog cada 5 minutos para verificar que Technitium responda correctamente y permitir el reinicio automático de `dns.service` cuando se detectan fallos persistentes.
## 📍 Ubicación
| Archivo | Ruta |
|---------|------|
| Service | `/etc/systemd/system/dns-healthcheck.service` |
| Timer | `/etc/systemd/system/dns-healthcheck.timer` |
| Script | `/usr/local/bin/dns-healthcheck.sh` |
| Estado | `/var/lib/dns-healthcheck.state` |
| Log | `/var/log/dns-healthcheck.log` |

## 📄 dns-healthcheck.service
```ini
[Unit]
Description=Technitium DNS Healthcheck
After=dns.service
Wants=dns.service
[Service]
Type=oneshot
ExecStart=/usr/local/bin/dns-healthcheck.sh
User=root
StandardOutput=journal
StandardError=journal
```
`root` permite reiniciar `dns.service`. `After=dns.service` ordena el healthcheck después de Technitium.
## 📄 dns-healthcheck.timer
```ini
[Unit]
Description=Run DNS Healthcheck every 5 minutes
Requires=dns-healthcheck.service
[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Persistent=true
RandomizedDelaySec=30s
Unit=dns-healthcheck.service
[Install]
WantedBy=timers.target
```
Primera ejecución tras 2 minutos; después cada 5 minutos. `Persistent=true` recupera ejecuciones perdidas y el retraso aleatorio evita picos sincronizados.

## 🛠️ Comandos útiles
```bash
sudo systemctl status dns-healthcheck.timer
sudo systemctl start dns-healthcheck.service
sudo tail -f /var/log/dns-healthcheck.log
sudo cat /var/lib/dns-healthcheck.state 2>/dev/null || echo "0"
sudo systemctl list-timers | grep healthcheck
```
> Última actualización: 2026-10-07
