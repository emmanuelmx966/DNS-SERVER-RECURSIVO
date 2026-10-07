# Units: cloudflare-ddns
Par `service` + `timer` que ejecuta el script DDNS cada 15 minutos para mantener actualizados los registros de Cloudflare y el Split Horizon de Technitium.
## 📍 Ubicación
| Archivo | Ruta |
|---------|------|
| Service | `/etc/systemd/system/cloudflare-ddns.service` |
| Timer | `/etc/systemd/system/cloudflare-ddns.timer` |
| Script | `/usr/local/bin/cloudflare-ddns.sh` |
| Log | `/var/log/cloudflare-ddns.log` |

## 📄 cloudflare-ddns.service
```ini
[Unit]
Description=Cloudflare DDNS Update
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/bin/cloudflare-ddns.sh
User=root
StandardOutput=journal
StandardError=journal
```
`Type=oneshot`: ejecuta el script una vez y termina. `root` es necesario para modificar Split Horizon y reiniciar `dns.service`.

## 📄 cloudflare-ddns.timer
```ini
[Unit]
Description=Run Cloudflare DDNS every 15 minutes
Requires=cloudflare-ddns.service
[Timer]
OnBootSec=5min
OnUnitActiveSec=15min
Unit=cloudflare-ddns.service
[Install]
WantedBy=timers.target
```
`OnBootSec=5min`: primera ejecución tras 5 minutos. `OnUnitActiveSec=15min`: siguientes ejecuciones cada 15 minutos.

## 🛠️ Comandos útiles
```bash
sudo systemctl status cloudflare-ddns.timer
sudo systemctl start cloudflare-ddns.service
sudo systemctl list-timers | grep cloudflare
sudo tail -f /var/log/cloudflare-ddns.log
sudo systemctl enable --now cloudflare-ddns.timer
sudo systemctl disable --now cloudflare-ddns.timer
```
> Última actualización: 2026-10-07
