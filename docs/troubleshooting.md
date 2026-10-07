# Troubleshooting — Solución de problemas
Guía práctica para diagnosticar y resolver los problemas más comunes del servidor DNS. Empieza por el diagnóstico rápido para confirmar servicios, puertos, timers y logs antes de aplicar cambios.
## 🚨 Diagnóstico rápido
```bash
systemctl is-active dns.service cloudflare-ddns.timer dns-healthcheck.timer dns-backup.timer
sudo ss -tulpn | grep -E ":53 |:443 |:853 |:5380 |:53443"
sudo systemctl list-timers | grep -E "cloudflare|dns-backup|dns-healthcheck"
sudo tail -20 /var/log/dns-healthcheck.log; sudo tail -20 /var/log/cloudflare-ddns.log
```
## 📋 Problemas comunes
### 1. DoT / DoH no responden desde fuera
**Síntomas**: `kdig +tls`/`+https` falla; NsLookup.io reporta caída. **Causa**: `dns.service` no escucha en 853/443 o el PFX no cargó.
```bash
sudo ss -tulpn | grep -E ":853 |:443 "
sudo journalctl -u dns.service --since "10 minutes ago" | grep -iE "tls|https|cert|error"
sudo systemctl restart dns.service; sleep 5; sudo ss -tulpn | grep -E ":853 |:443 "
```
### 2. No resuelve desde fuera, pero sí desde LAN
**Síntomas**: LAN funciona; datos móviles fallan. **Causa**: Cloudflare conserva una IP pública antigua.
```bash
curl -4 -s https://api.ipify.org; echo; dig @1.1.1.1 dns.emmanuel-mx.com A +short
sudo systemctl start cloudflare-ddns.service; sudo tail -10 /var/log/cloudflare-ddns.log
```
### 3. Split Horizon no traduce
**Síntomas**: LAN resuelve `dns.emmanuel-mx.com` a la IP pública. **Causa**: `dnsApp.config` tiene una traducción desactualizada.
```bash
sudo cat "/etc/dns/apps/Split Horizon/dnsApp.config" | python3 -m json.tool
curl -4 -s https://api.ipify.org; echo; sudo systemctl start cloudflare-ddns.service
```
### 4. Certificado SSL expirado
**Síntomas**: navegador o `kdig +tls` reportan certificado inválido. **Causa**: Certbot o el hook del PFX falló.
```bash
sudo certbot certificates; sudo certbot renew --force-renewal
sudo cat /etc/letsencrypt/renewal-hooks/deploy/technitium-pfx.sh
sudo /etc/letsencrypt/renewal-hooks/deploy/technitium-pfx.sh; sudo systemctl restart dns.service
```
### 5. No hay backups recientes
**Síntomas**: `/root/backups/` está vacío o sin archivos recientes. **Causa**: timer deshabilitado o fallo del script.
```bash
sudo systemctl status dns-backup.timer; sudo systemctl start dns-backup.service
sudo tail -20 /var/log/dns-backup.log; sudo ls -lh /root/backups/
sudo systemctl enable --now dns-backup.timer
```
### 6. Healthcheck reinicia dns.service constantemente
**Síntomas**: reinicios cada 5 min. **Causa**: uno de los 5 checks falla persistentemente.
```bash
sudo tail -20 /var/log/dns-healthcheck.log
dig @127.0.0.1 example.com A +short
kdig +tls @127.0.0.1 example.com A
curl -k -o /dev/null -w "%{http_code}\n" "https://127.0.0.1/dns-query?dns=AAABAAABAAAAAAAAB2V4YW1wbGUDY29tAAABAAE" -H "accept: application/dns-message"
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:5380/
curl -k -s -o /dev/null -w "%{http_code}\n" https://127.0.0.1:53443/
```
### 7. Puerto 53 ocupado por otro servicio
**Síntomas**: `dns.service` falla con `address already in use`. **Causa**: normalmente `systemd-resolved` ocupa el 53.
```bash
sudo ss -tulpn | grep :53; sudo nano /etc/systemd/resolved.conf
# Cambiar DNSStubListener=yes por DNSStubListener=no
sudo systemctl restart systemd-resolved; sudo systemctl restart dns.service
```
### 8. No se puede conectar al dashboard HTTPS
**Síntomas**: `:53443` externo falla, pero `http://192.168.1.121:5380` funciona. **Causa**: falta Port Forwarding TCP 53443.
```bash
nc -zv dns.emmanuel-mx.com 53443
# Router 192.168.1.254 → NAT/Port Forwarding → 53443 TCP → 192.168.1.121
```
### 9. Dispositivos no pueden resolver con DoT/DoH
**Síntomas**: un dispositivo pierde navegación con DNS privado. **Causa**: resolución circular o configuración del cliente.
```bash
dig @1.1.1.1 dns.emmanuel-mx.com A +short
kdig +tls @dns.emmanuel-mx.com example.com A; kdig +https @dns.emmanuel-mx.com example.com A
```
Android: DNS privado → `dns.emmanuel-mx.com`; iOS: perfil DoH/DoT; Windows: DNS manual + DoH personalizado.
### 10. Log DDNS muestra errores constantes
**Síntomas**: `ERROR`/`WARN` repetidos. **Causas**: token inválido, sin conectividad o config ausente/permisos incorrectos.
```bash
curl -s -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" -H "Authorization: Bearer $(grep CF_API_TOKEN /etc/cloudflare-ddns/config | cut -d'"' -f2)" | jq
sudo ls -la /etc/cloudflare-ddns/config; ping -c 2 1.1.1.1
```
## 🛠️ Diagnóstico general
```bash
echo "=== Servicios ==="; systemctl is-active dns.service cloudflare-ddns.timer dns-healthcheck.timer dns-backup.timer certbot.timer
echo "=== Puertos ==="; sudo ss -tulpn | grep -E ":53 |:443 |:853 |:5380 |:53443"
echo "=== IPs ==="; echo "Local: 192.168.1.121"; echo "Pública: $(curl -4 -s https://api.ipify.org)"; echo "Cloudflare: $(dig @1.1.1.1 dns.emmanuel-mx.com A +short)"
echo "=== Logs ==="; sudo tail -5 /var/log/dns-healthcheck.log; sudo tail -5 /var/log/cloudflare-ddns.log
echo "=== Certificado ==="; sudo certbot certificates 2>/dev/null | grep -E "Expiry|Domains"
echo "=== Backups ==="; sudo ls -lh /root/backups/ | tail -3
```
## 🚑 Si todo falla
1. Reiniciar Technitium: `sudo systemctl restart dns.service`.
2. Reiniciar servidor: `sudo reboot`.
3. Restaurar desde backup: [`recovery.md`](recovery.md).
## 📌 Referencias
- Arquitectura: [`01-arquitectura.md`](01-arquitectura.md) · Servicios: [`02-servicios.md`](02-servicios.md) · Recovery: [`recovery.md`](recovery.md)
> Última actualización: 2026-10-07
