# Units: dns-backup

Par `service` + `timer` que ejecuta semanalmente el script de backup para proteger la configuración completa del servidor DNS y conservar copias verificables en `/root/backups/`.

## 📍 Ubicación
| Archivo | Ruta |
|---------|------|
| Service | `/etc/systemd/system/dns-backup.service` |
| Timer | `/etc/systemd/system/dns-backup.timer` |
| Script | `/usr/local/bin/dns-backup.sh` |
| Backups | `/root/backups/` |
| Log | `/var/log/dns-backup.log` |

## 📄 dns-backup.service
```ini
[Unit]
Description=DNS Server Automatic Backup
[Service]
Type=oneshot
ExecStart=/usr/local/bin/dns-backup.sh
User=root
StandardOutput=journal
StandardError=journal
```
`Type=oneshot`: ejecuta el backup una vez. `root` es necesario para leer todas las rutas críticas de configuración.

## 📄 dns-backup.timer
```ini
[Unit]
Description=Run DNS backup weekly
[Timer]
OnCalendar=weekly
Persistent=true
RandomizedDelaySec=30min
[Install]
WantedBy=timers.target
```
`OnCalendar=weekly`: ejecución semanal. `Persistent=true`: recupera una ejecución perdida tras arrancar. `RandomizedDelaySec=30min`: añade un retraso aleatorio de hasta 30 minutos.

## 🛠️ Comandos útiles
```bash
sudo systemctl status dns-backup.timer
sudo systemctl start dns-backup.service
sudo ls -lh /root/backups/
sudo tail -f /var/log/dns-backup.log
sudo systemctl list-timers | grep dns-backup
```
> Última actualización: 2026-10-07
