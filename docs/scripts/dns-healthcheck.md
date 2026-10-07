# Script: dns-healthcheck.sh
Este script actúa como watchdog de Technitium DNS Server: verifica múltiples endpoints locales cada 5 minutos y reinicia `dns.service` automáticamente cuando detecta fallos persistentes, evitando reaccionar ante errores aislados.
## 📍 Ubicación
- **Script**: `/usr/local/bin/dns-healthcheck.sh`
- **Log**: `/var/log/dns-healthcheck.log`
- **Estado**: `/var/lib/dns-healthcheck.state` (contador de fallos)
- **Ejecutado por**: `dns-healthcheck.timer` (cada 5 minutos)
- **Usuario**: root
## 🎯 Qué hace
1. Verifica que `dns.service` esté activo; si no, intenta arrancarlo.
2. Ejecuta 5 checks contra endpoints de Technitium.
3. Persiste el número de fallos consecutivos.
4. Reinicia `dns.service` al alcanzar 2 fallos consecutivos.
5. Registra todo en `/var/log/dns-healthcheck.log`.
## 🔍 Los 5 checks
| # | Check | Puerto | Método |
|---|-------|--------|--------|
| 1 | DNS estándar | 53 | `dig @127.0.0.1 example.com A +short` |
| 2 | DNS-over-TLS | 853 | `kdig +tls @127.0.0.1 example.com A` |
| 3 | DNS-over-HTTPS | 443 | `curl -k https://127.0.0.1/dns-query?dns=...` |
| 4 | Dashboard HTTP | 5380 | `curl http://127.0.0.1:5380/` |
| 5 | Dashboard HTTPS | 53443 | `curl -k https://127.0.0.1:53443/` |
Cada check tiene un timeout de 5 segundos.
## 🧠 Lógica de decisión
```text
Inicio
  ↓
[1] ¿dns.service activo?
  ├── NO → systemctl start dns.service → exit
  └── SÍ → ejecutar 5 checks
  ↓
[2] ¿Todos OK?
  ├── SÍ → borrar contador → exit
  └── NO → leer estado e incrementar contador
  ↓
[3] ¿Contador ≥ 2?
  ├── NO → log "Fallos consecutivos: 1/2" → exit
  └── SÍ → systemctl restart dns.service
  ↓
[4] Esperar 10 s y verificar
  ├── OK → borrar contador → log "OK tras reinicio"
  └── ERROR → log "dns.service NO activo tras reinicio"
  ↓
Fin
```
## ⚙️ Por qué existe este servicio
Tras un reinicio real, Technitium arrancó pero su servidor HTTPS interno (Kestrel) no cargó correctamente: el puerto 443 aceptaba TCP, pero fallaba el handshake TLS. DoT en 853 seguía funcionando, mientras DoH en 443 fallaba y los monitores HTTPS externos reportaban caída.
Un `sudo systemctl restart dns.service` corregía el problema inmediatamente; este watchdog automatiza esa recuperación.
## 📊 Log
**Funcionamiento normal:**
```text
2026-10-07 14:15:03 - OK: Todos los checks pasaron (53, 853, 443, 5380, 53443)
```
**Fallo aislado (1/2):**
```text
2026-10-07 14:30:03 - WARN: Checks fallidos: DoH-443
2026-10-07 14:30:03 - WARN: Fallos consecutivos: 1/2
```
**Fallo persistente → reinicio:**
```text
2026-10-07 14:35:03 - WARN: Fallos consecutivos: 2/2
2026-10-07 14:35:03 - ALERTA: Umbral alcanzado. Reiniciando dns.service...
2026-10-07 14:35:24 - OK: dns.service activo tras reinicio
```
## 🛠️ Comandos útiles
```bash
sudo systemctl status dns-healthcheck.timer
sudo systemctl start dns-healthcheck.service
sudo tail -f /var/log/dns-healthcheck.log
sudo tail -20 /var/log/dns-healthcheck.log
sudo cat /var/lib/dns-healthcheck.state 2>/dev/null || echo "0 (sin fallos)"
sudo systemctl list-timers | grep healthcheck
```
## 🚨 Solución de problemas
### Reinicia dns.service constantemente
```bash
dig @127.0.0.1 example.com A +short
kdig +tls @127.0.0.1 example.com A
curl -k -o /dev/null -w "%{http_code}\n" "https://127.0.0.1/dns-query?dns=AAABAAABAAAAAAAAB2V4YW1wbGUDY29tAAABAAE" -H "accept: application/dns-message"
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:5380/
curl -k -s -o /dev/null -w "%{http_code}\n" https://127.0.0.1:53443/
```
### El watchdog no se ejecuta
Verificar con `sudo systemctl status dns-healthcheck.timer` y habilitar con `sudo systemctl enable --now dns-healthcheck.timer`.
### Falsos positivos
Si hay carga alta, cambiar `MAX_FAILURES=2` por `MAX_FAILURES=3` en `/usr/local/bin/dns-healthcheck.sh`.
### El contador se queda pegado
Verificar `/var/lib/dns-healthcheck.state` y borrar con `sudo rm -f /var/lib/dns-healthcheck.state` si corresponde.
## 🎯 Buenas prácticas
1. No eliminar el script: es parte de la auto-recuperación.
2. Revisar el log semanalmente y diagnosticar reinicios frecuentes.
3. Mantener umbral 2 en sistemas estables; usar 3 solo ante falsos positivos comprobados.
## 🎯 Ventajas
- ✅ Evita reinicios por fallos aislados y actúa ante fallos persistentes.
- ✅ Verifica cinco endpoints, persiste estado y se integra con systemd para auto-recuperación.
## 📌 Referencias
- Unit systemd: [`../units/dns-healthcheck-units.md`](../units/dns-healthcheck-units.md)
- Servicios generales: [`../02-servicios.md`](../02-servicios.md)
- Troubleshooting: [`../troubleshooting.md`](../troubleshooting.md)
> Última actualización: 2026-10-07
