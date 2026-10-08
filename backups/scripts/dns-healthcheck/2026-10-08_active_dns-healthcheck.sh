#!/bin/bash
# Healthcheck para Technitium DNS Server
set -u

LOG_FILE="/var/log/dns-healthcheck.log"
STATE_FILE="/var/lib/dns-healthcheck.state"
MAX_FAILURES=2
TIMEOUT=5

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"; }

check_service_active() { systemctl is-active --quiet dns.service; }

check_dns_53() {
    timeout $TIMEOUT dig @127.0.0.1 example.com A +short > /dev/null 2>&1
}

check_dot_853() {
    timeout $TIMEOUT kdig +tls @127.0.0.1 example.com A > /dev/null 2>&1
}

check_doh_443() {
    local result
    result=$(timeout $TIMEOUT curl -k -s -o /dev/null -w "%{http_code}" \
        "https://127.0.0.1/dns-query?dns=AAABAAABAAAAAAAAB2V4YW1wbGUDY29tAAABAAE" \
        -H "accept: application/dns-message" 2>/dev/null)
    [ "$result" = "200" ]
}

check_dashboard_5380() {
    local result
    result=$(timeout $TIMEOUT curl -s -o /dev/null -w "%{http_code}" \
        "http://127.0.0.1:5380/" 2>/dev/null)
    [ "$result" = "200" ] || [ "$result" = "302" ] || [ "$result" = "307" ]
}

check_dashboard_53443() {
    local result
    result=$(timeout $TIMEOUT curl -k -s -o /dev/null -w "%{http_code}" \
        "https://127.0.0.1:53443/" 2>/dev/null)
    [ "$result" = "200" ]
}

if ! check_service_active; then
    log "ALERTA: dns.service NO está activo"
    log "Acción: Iniciando dns.service..."
    systemctl start dns.service
    sleep 5
    if check_service_active; then
        log "OK: dns.service iniciado correctamente"
    else
        log "ERROR: No se pudo iniciar dns.service"
    fi
    exit 0
fi

FAILED_CHECKS=()
FAILED_NAMES=()

check_dns_53 || { FAILED_CHECKS+=(53); FAILED_NAMES+=("DNS-53"); }
check_dot_853 || { FAILED_CHECKS+=(853); FAILED_NAMES+=("DoT-853"); }
check_doh_443 || { FAILED_CHECKS+=(443); FAILED_NAMES+=("DoH-443"); }
check_dashboard_5380 || { FAILED_CHECKS+=(5380); FAILED_NAMES+=("Dashboard-5380"); }
check_dashboard_53443 || { FAILED_CHECKS+=(53443); FAILED_NAMES+=("Dashboard-53443"); }

if [ ${#FAILED_CHECKS[@]} -eq 0 ]; then
    log "OK: Todos los checks pasaron (53, 853, 443, 5380, 53443)"
    rm -f "$STATE_FILE"
    exit 0
fi

log "WARN: Checks fallidos: ${FAILED_NAMES[*]}"

FAIL_COUNT=0
[ -f "$STATE_FILE" ] && FAIL_COUNT=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
FAIL_COUNT=$((FAIL_COUNT + 1))
echo "$FAIL_COUNT" > "$STATE_FILE"

log "WARN: Fallos consecutivos: $FAIL_COUNT/$MAX_FAILURES"

if [ "$FAIL_COUNT" -ge "$MAX_FAILURES" ]; then
    log "ALERTA: Umbral alcanzado. Reiniciando dns.service..."
    if systemctl restart dns.service; then
        log "INFO: dns.service reiniciado"
        sleep 10
        rm -f "$STATE_FILE"
        if check_service_active; then
            log "OK: dns.service activo tras reinicio"
        else
            log "ERROR: dns.service NO activo tras reinicio"
        fi
    else
        log "ERROR: Falló el reinicio"
    fi
fi
exit 0
