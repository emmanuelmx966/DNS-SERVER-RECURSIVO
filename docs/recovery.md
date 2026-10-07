# Recovery — Recuperación tras desastres
Guía paso a paso para recuperar el servidor DNS ante fallos críticos, pérdida de conectividad o sustitución del sistema. Identifica el escenario y conserva cualquier backup disponible.
## 🎯 Escenarios cubiertos
| # | Escenario | Gravedad | Tiempo |
|---|---|---|---|
| 1 | `dns.service` caído | 🟡 Baja | 1 min |
| 2 | IP pública cambió | 🟡 Baja | ≤15 min |
| 3 | Certificado expirado | 🟡 Media | 5 min |
| 4 | Disco muerto | 🔴 Alta | 30-60 min |
| 5 | Router reseteado | 🟡 Media | 20 min |
| 6 | Sin acceso SSH | 🔴 Alta | 15-30 min |
## 🟡 1. Se cayó dns.service
**Síntomas**: no hay resolución DNS ni DoT/DoH.
```bash
sudo systemctl status dns.service
sudo journalctl -u dns.service -n 50 --no-pager
sudo systemctl restart dns.service
sudo systemctl is-active dns.service
sudo ss -tulpn | grep -E ":53 |:443 |:853 "
```
`dns-healthcheck.timer` debería recuperarlo automáticamente en ≤10 min.
## 🟡 2. Cambió la IP pública
**Síntomas**: DoT/DoH externo o Split Horizon fallan.
```bash
curl -4 -s https://api.ipify.org; echo
curl -6 -s https://api6.ipify.org; echo
dig @1.1.1.1 dns.emmanuel-mx.com A +short
dig @1.1.1.1 dns.emmanuel-mx.com AAAA +short
sudo systemctl start cloudflare-ddns.service
sleep 5; sudo tail -15 /var/log/cloudflare-ddns.log
```
El timer DDNS sincroniza normalmente cada 15 min.
## 🟡 3. Certificado expirado
**Síntomas**: navegador, DoT o DoH reportan certificado inválido.
```bash
sudo certbot certificates
sudo certbot renew --force-renewal
sudo /etc/letsencrypt/renewal-hooks/deploy/technitium-pfx.sh
sudo systemctl restart dns.service
openssl s_client -connect dns.emmanuel-mx.com:443 -servername dns.emmanuel-mx.com < /dev/null 2>&1 | grep -E "subject|NotAfter"
```
## 🔴 4. Disco muerto
**Requisitos**: backup reciente y Ubuntu Server 24.04+ limpio.
```bash
# 1. Instalar base y detener Technitium
curl -sSL https://download.technitium.com/dns/install.sh | sudo bash
sudo systemctl stop dns.service
# 2. Desde tu PC
# scp dns-backup-YYYY-MM-DD_HHMMSS.tar.gz emmanuel@192.168.1.121:/home/emmanuel/
# 3. Restaurar
sudo tar -xzf /home/emmanuel/dns-backup-YYYY-MM-DD_HHMMSS.tar.gz -C /
sudo chown -R dns-server:dns-server /etc/dns /etc/technitium
sudo chmod 600 /etc/cloudflare-ddns/config
sudo chown root:root /etc/cloudflare-ddns/config
# 4. Reactivar
sudo systemctl daemon-reload
sudo systemctl enable --now dns.service cloudflare-ddns.timer dns-healthcheck.timer dns-backup.timer
sudo systemctl start cloudflare-ddns.service
# 5. Verificar
sudo systemctl list-timers | grep -E "cloudflare|dns-backup|dns-healthcheck"
sudo ss -tulpn | grep -E ":53 |:443 |:853 "
```
## 🟡 5. Router reseteado
**Síntomas**: LAN funciona, pero acceso externo falla.
1. Entrar a `http://192.168.1.254` y abrir NAT / Port Forwarding.
2. Crear hacia `192.168.1.121`: `53 TCP+UDP`, `853 TCP+UDP`, `443 TCP+UDP`, `53443 TCP`.
3. Guardar y verificar desde otra red:
```bash
nc -zv dns.emmanuel-mx.com 53
nc -zv dns.emmanuel-mx.com 853
nc -zv dns.emmanuel-mx.com 443
nc -zv dns.emmanuel-mx.com 53443
```
## 🔴 6. Pérdida de acceso SSH
**Síntomas**: SSH no conecta. **Causas**: servicio, firewall, credenciales o Fail2ban.
```bash
sudo systemctl status ssh; sudo systemctl restart ssh
sudo ss -tulpn | grep :22; sudo ufw status | grep 22
sudo passwd emmanuel
sudo fail2ban-client status sshd
sudo fail2ban-client set sshd unbanip TU_IP
```
## 📋 Checklist de recuperación completa
```bash
# 1. Servicios
systemctl is-active dns.service cloudflare-ddns.timer dns-healthcheck.timer dns-backup.timer certbot.timer
# 2. Puertos
sudo ss -tulpn | grep -E ":53 |:443 |:853 |:5380 |:53443"
# 3. DNS local
dig @127.0.0.1 example.com A +short
# 4. DoT local
kdig +tls @127.0.0.1 example.com A
# 5. DoH local
curl -k -o /dev/null -w "%{http_code}\n" "https://127.0.0.1/dns-query?dns=AAABAAABAAAAAAAAB2V4YW1wbGUDY29tAAABAAE" -H "accept: application/dns-message"
# 6. DNS externo
dig @1.1.1.1 dns.emmanuel-mx.com A +short
# 7. DoT/DoH externo
kdig +tls @dns.emmanuel-mx.com example.com A; kdig +https @dns.emmanuel-mx.com example.com A
# 8. Certificado
echo | openssl s_client -connect dns.emmanuel-mx.com:443 -servername dns.emmanuel-mx.com 2>/dev/null | grep "Verify return"
# 9. Timers
sudo systemctl list-timers | grep -E "cloudflare|dns-backup|dns-healthcheck"
# 10. Logs
sudo tail -5 /var/log/cloudflare-ddns.log; sudo tail -5 /var/log/dns-healthcheck.log
```
Si los 10 pasos pasan, el servidor está recuperado. ✅
## 🎯 Prevención
| Medida | Beneficio |
|---|---|
| Backup semanal + copia externa | Estrategia 3-2-1 |
| UPS en servidor y router | Evita cortes abruptos |
| Prueba trimestral de restore | Valida backups |
| Gestor de contraseñas | Protege SSH, PFX y Cloudflare |
| Fail2ban + healthcheck | Protección y auto-recuperación |
## 📌 Referencias
- [`troubleshooting.md`](troubleshooting.md) · [`02-servicios.md`](02-servicios.md) · [`scripts/`](scripts/)
> Última actualización: 2026-10-07
