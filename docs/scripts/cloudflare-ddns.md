# Script: cloudflare-ddns.sh
Este script mantiene actualizada la IP pública del servidor en Cloudflare y sincroniza el Split Horizon de Technitium cuando detecta un cambio. Se ejecuta automáticamente mediante systemd cada 15 minutos y registra cada operación para facilitar auditoría y diagnóstico.
## 📍 Ubicación
- **Script**: `/usr/local/bin/cloudflare-ddns.sh`
- **Config**: `/etc/cloudflare-ddns/config`
- **Log**: `/var/log/cloudflare-ddns.log`
- **Ejecutado por**: `cloudflare-ddns.timer` (cada 15 minutos)
- **Usuario**: root
## 🎯 Qué hace
En cada ejecución:
1. **Verifica conectividad** → ping a `1.1.1.1` con reintentos.
2. **Obtiene IPv4 pública** → consulta 3 servicios alternativos.
3. **Obtiene IPv6 pública** → consulta 3 servicios alternativos.
4. **Actualiza Cloudflare A** → si la IPv4 cambió.
5. **Actualiza Cloudflare AAAA** → si la IPv6 cambió.
6. **Actualiza Split Horizon** → si la IPv4 cambió.
7. **Reinicia `dns.service`** → solo si Split Horizon cambió.
## 🔄 Flujo detallado
```text
Inicio
  ↓
[1] Verificar conectividad (máx. 10 reintentos, 30 s entre cada uno)
[2] Obtener IPv4 (api.ipify.org, ifconfig.me, icanhazip.com)
[3] Obtener IPv6 (api6.ipify.org, ifconfig.co, icanhazip.com)
[4] Consultar Cloudflare → obtener Zone ID
[5] Comparar IPv4 con registro A
  ├── Cambió → PATCH para actualizar
  └── Igual   → log "sin cambios"
[6] Actualizar Split Horizon si IPv4 cambió
  ├── Cambió → modificar dnsApp.config + reiniciar dns.service
  └── Igual   → log "sin cambios"
[7] Comparar IPv6 con registro AAAA
  ├── Cambió → PATCH para actualizar
  └── Igual   → log "sin cambios"
  ↓
Fin
```
## 🔐 Configuración
Archivo: `/etc/cloudflare-ddns/config` (**permisos 600**).
- **CF_API_TOKEN**: Token de Cloudflare restringido a `Zone:DNS:Edit`.
- **ZONE_NAME**: Dominio raíz, por ejemplo `emmanuel-mx.com`.
- **RECORD_NAME**: Subdominio, por ejemplo `dns`.
## 📊 Log
Archivo: `/var/log/cloudflare-ddns.log`
```text
2026-10-07 14:15:06 - Iniciando actualización DDNS para dns.emmanuel-mx.com
2026-10-07 14:15:07 - IPv4 pública actual: 189.223.90.73
2026-10-07 14:15:07 - Cloudflare A: sin cambios (189.223.90.73)
2026-10-07 14:15:07 - Split Horizon: sin cambios (189.223.90.73)
2026-10-07 14:15:08 - IPv6 pública actual: 2806:290:8833:7ecb:5281:40ff:feb6:7fd6
2026-10-07 14:15:08 - Cloudflare AAAA: sin cambios (2806:290:8833:7ecb:...)
2026-10-07 14:15:08 - Proceso completado
```
Cuando la IP cambia:
```text
2026-10-07 14:15:07 - IPv4 pública actual: 189.223.90.74
2026-10-07 14:15:08 - Cloudflare A: 189.223.90.73 -> 189.223.90.74
2026-10-07 14:15:08 - Split Horizon: actualizando 189.223.90.73 -> 189.223.90.74
2026-10-07 14:15:09 - Split Horizon config actualizado correctamente
2026-10-07 14:15:09 - Reiniciando dns.service para aplicar Split Horizon...
2026-10-07 14:15:11 - dns.service reiniciado
```
## 🛠️ Comandos útiles
```bash
sudo systemctl status cloudflare-ddns.timer
sudo systemctl start cloudflare-ddns.service
sudo tail -f /var/log/cloudflare-ddns.log
sudo tail -20 /var/log/cloudflare-ddns.log
sudo systemctl list-timers | grep cloudflare
```
## 🚨 Solución de problemas
### No actualiza Cloudflare
**Síntoma**: `ERROR: No Zone ID`. **Causa**: token inválido o restringido incorrectamente.
```bash
curl -s -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "Authorization: Bearer $(grep CF_API_TOKEN /etc/cloudflare-ddns/config | cut -d'\"' -f2)" | jq
```
Debe devolver `"status": "active"`.
### No se puede conectar
**Síntoma**: `WARN: Sin conectividad`. **Causa**: sin Internet. **Solución**: verificar la red; el script reintenta 10 veces.
### Split Horizon no se actualiza
**Síntoma**: indica "sin cambios" aunque la IP cambió. **Causa**: `dnsApp.config` inexistente o con permisos incorrectos.
```bash
sudo ls -la "/etc/dns/apps/Split Horizon/dnsApp.config"
sudo cat "/etc/dns/apps/Split Horizon/dnsApp.config" | python3 -m json.tool
```
### No se ejecuta el timer
**Síntoma**: el log no crece. **Causa**: timer deshabilitado.
```bash
sudo systemctl status cloudflare-ddns.timer
sudo systemctl enable --now cloudflare-ddns.timer
```
## 📌 Referencias
- Unit systemd: [`../units/cloudflare-ddns-units.md`](../units/cloudflare-ddns-units.md)
- Servicios generales: [`../02-servicios.md`](../02-servicios.md)
- Troubleshooting: [`../troubleshooting.md`](../troubleshooting.md)
> Última actualización: 2026-10-07
