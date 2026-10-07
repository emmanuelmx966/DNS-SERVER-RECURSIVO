# Script: dns-backup.sh
Este script crea automáticamente un backup completo de la configuración crítica del servidor DNS. Se ejecuta semanalmente mediante systemd, verifica la integridad del archivo generado, aplica una retención de 30 días y registra todas las operaciones.
## 📍 Ubicación
- **Script**: `/usr/local/bin/dns-backup.sh`
- **Destino backups**: `/root/backups/`
- **Log**: `/var/log/dns-backup.log`
- **Ejecutado por**: `dns-backup.timer` (semanal, lunes ~00:05)
- **Usuario**: root
## 🎯 Qué hace
1. Crea `/root/backups/` si no existe (permisos 700).
2. Genera `dns-backup-YYYY-MM-DD_HHMMSS.tar.gz`.
3. Comprime todos los archivos de configuración críticos.
4. Verifica integridad del backup mediante lectura del `tar.gz`.
5. Elimina backups con más de 30 días.
6. Registra todo el proceso en `/var/log/dns-backup.log`.
## 📦 Qué respalda
| Ruta | Contenido |
|------|-----------|
| `/etc/dns/` | Config de Technitium: zonas, apps y blocklists |
| `/etc/technitium/` | Certificado PFX |
| `/etc/cloudflare-ddns/` | Token y configuración de Cloudflare |
| `/usr/local/bin/cloudflare-ddns.sh` | Script DDNS |
| `/usr/local/bin/dns-backup.sh` | Script de backup |
| `/usr/local/bin/dns-healthcheck.sh` | Script watchdog |
| `/etc/systemd/system/cloudflare-ddns.service` | Unit DDNS |
| `/etc/systemd/system/cloudflare-ddns.timer` | Timer DDNS |
| `/etc/systemd/system/dns-backup.service` | Unit backup |
| `/etc/systemd/system/dns-backup.timer` | Timer backup |
| `/etc/systemd/system/dns-healthcheck.service` | Unit watchdog |
| `/etc/systemd/system/dns-healthcheck.timer` | Timer watchdog |
| `/etc/systemd/system/dns.service` | Unit Technitium |
| `/etc/letsencrypt/live/` | Certificados Let's Encrypt |
| `/etc/letsencrypt/renewal/` | Configuración de renovación |
| `/etc/letsencrypt/renewal-hooks/` | Hook de regeneración del PFX |
| `/etc/netplan/` | Configuración de red/IP estática |
| `/etc/hosts` | Hosts locales |
## 🔄 Flujo detallado
```text
Inicio → crear /root/backups/ → generar nombre del archivo
  ↓
Crear tar.gz con rutas configuradas
  ├── OK → verificar integridad con tar -tzf
  └── ERROR → log + exit 1
  ↓
Verificación
  ├── OK → "Backup verificado correctamente"
  └── ERROR → "Backup corrupto" + exit 1
  ↓
Eliminar backups >30 días → log "Backup completado" → Fin
```
## 📊 Log
```text
2026-10-12 00:05:30 - Iniciando backup...
2026-10-12 00:05:45 - Backup creado: /root/backups/dns-backup-2026-10-12_000530.tar.gz (48M)
2026-10-12 00:05:45 - Backup verificado correctamente
2026-10-12 00:05:45 - Backups antiguos eliminados: 1
2026-10-12 00:05:45 - Backup completado
```
## 💾 Tamaño típico
- **Backup normal**: ~50 MB comprimido · **Retención**: 30 días (~4-5 backups) · **Espacio estimado**: ~250 MB/mes.
## 🔄 Cómo restaurar desde backup
Escenario: fallo de disco o migración a otro servidor.
```bash
# 1. Instalar Technitium en Ubuntu Server limpio
curl -sSL https://download.technitium.com/dns/install.sh | sudo bash
# 2. Detener el servicio
sudo systemctl stop dns.service
# 3. Restaurar
sudo tar -xzf dns-backup-YYYY-MM-DD_HHMMSS.tar.gz -C /
# 4. Ajustar permisos
sudo chown -R dns-server:dns-server /etc/dns /etc/technitium
sudo chmod 600 /etc/cloudflare-ddns/config
# 5. Recargar systemd y habilitar servicios
sudo systemctl daemon-reload
sudo systemctl enable --now dns.service cloudflare-ddns.timer dns-backup.timer dns-healthcheck.timer
```
**Tiempo estimado**: ~15 minutos.
## 🛠️ Comandos útiles
```bash
sudo systemctl status dns-backup.timer
sudo systemctl start dns-backup.service
sudo ls -lh /root/backups/ && sudo du -sh /root/backups/
sudo tail -f /var/log/dns-backup.log
sudo systemctl list-timers | grep dns-backup
sudo tar -tzf /root/backups/dns-backup-YYYY-MM-DD_HHMMSS.tar.gz >/dev/null && echo "OK"
```
## 🚨 Solución de problemas
- **No se crean backups**: revisar `sudo systemctl status dns-backup.timer` y `sudo journalctl -u dns-backup.service -n 20`.
- **Backup corrupto**: comprobar espacio con `df -h /root`; eliminar manualmente archivos antiguos si es necesario.
- **No rota backups**: revisar permisos y ejecutar `sudo find /root/backups -name "dns-backup-*.tar.gz" -mtime +30 -delete`.
- **Permission denied**: recrear con `sudo mkdir -p /root/backups && sudo chmod 700 /root/backups && sudo chown root:root /root/backups`.
## 🎯 Buenas prácticas
1. Aplicar estrategia **3-2-1**: mantener copias fuera del servidor (PC por `scp`, USB y almacenamiento externo/nube).
2. Probar una restauración al menos una vez al mes en VM o entorno aislado.
3. Si hay capacidad suficiente, ampliar `RETENTION_DAYS=30` a `90` y validar el siguiente backup programado.
## 📌 Referencias
- Unit systemd: [`../units/dns-backup-units.md`](../units/dns-backup-units.md)
- Servicios generales: [`../02-servicios.md`](../02-servicios.md)
- Recovery: [`../recovery.md`](../recovery.md)
> Última actualización: 2026-10-07
