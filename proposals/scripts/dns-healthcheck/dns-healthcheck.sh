#!/bin/bash
# PROPUESTA — Healthcheck robusto para Technitium DNS Server
# No instalar hasta completar pruebas controladas.
set -u

LOG_FILE="/var/log/dns-healthcheck.log"
STATE_FILE="/var/lib/dns-healthcheck.state"
LOCK_FILE="/run/dns-healthcheck.lock"
MAX_FAILURES=2
TIMEOUT=5
POST_RESTART_WAIT=10

umask 077

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

for cmd in systemctl timeout dig kdig curl flock; do
    command -v "$cmd" >/dev/null 2>&1 || { log "ERROR: Dependencia ausente: $cmd"; exit 2; }
done

[ "${EUID:-$(id -u)}" -eq 0 ] || { log "ERROR: Este script debe ejecutarse como root"; exit 2; }

exec 9>"$LOCK_FILE"
flock -n 9 || { log "WARN: Ya existe otra ejecución del healthcheck activa"; exit 0; }

check_service_active() {
    systemctl is-active --quiet dns.service
}

check_dns_53() {
    timeout "$TIMEOUT" dig @127.0.0.1 example.com A +short >/dev/null 2>&1
}

check_dot_853() {
    timeout "$TIMEOUT" kdig +tls @127.0.0.1 example.com A >/dev/null 2>&1
}

check_doh_443() {
    local result
    result=$(timeout "$TIMEOUT" curl -k -s -o /dev/null -w "%{http_code}" \
        "https://127.0.0.1/dns-query?dns=AAABAAABAAAAAAAAB2V4YW1wbGUDY29tAAABAAE" \
        -H "accept: application/dns-message" 2>/dev/null) || return 1
    [ "$result" = "200" ]
}

check_dashboard_5380() {
    local result
    result=$(timeout "$TIMEOUT" curl -s -o /dev/null -w "%{http_code}" \
        "http://127.0.0.1:5380/" 2>/dev/null) || return 1
    [ "$result" = "200" ] || [ "$result" = "302" ] || [ "$result" = "307" ]
}

check_dashboard_53443() {
    local result
    result=$(timeout "$TIMEOUT" curl -k -s -o /dev/null -w "%{http_code}" \
        "https://127.0.0.1:53443/" 2>/dev/null) || return 1
    [ "$result" = "200" ]
}

FAILED_NAMES=()

run_all_checks() {
    FAILED_NAMES=()
    check_dns_53 || FAILED_NAMES+=("DNS-53")
    check_dot_853 || FAILED_NAMES+=("DoT-853")
    check_doh_443 || FAILED_NAMES+=("DoH-443")
    check_dashboard_5380 || FAILED_NAMES+=("Dashboard-5380")
    check_dashboard_53443 || FAILED_NAMES+=("Dashboard-53443")
    [ "${#FAILED_NAMES[@]}" -eq 0 ]
}

read_fail_count() {
    local value=0
    if [ -f "$STATE_FILE" ]; then
        value=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
    fi
    [[ "$value" =~ ^[0-9]+$ ]] || value=0
    echo "$value"
}

write_fail_count() {
    printf '%s\n' "$1" > "$STATE_FILE"
    chmod 600 "$STATE_FILE"
}

clear_state() {
    rm -f "$STATE_FILE"
}

if ! check_service_active; then
    log "ALERTA: dns.service NO está activo"
    log "Acción: Iniciando dns.service..."
    if ! systemctl start dns.service; then
        log "ERROR: No se pudo iniciar dns.service"
        exit 1
    fi
    sleep 5
    if ! check_service_active; then
        log "ERROR: dns.service sigue inactivo tras start"
        exit 1
    fi
    log "INFO: dns.service iniciado; validando todos los endpoints"
fi

if run_all_checks; then
    log "OK: Todos los checks pasaron (53, 853, 443, 5380, 53443)"
    clear_state
    exit 0
fi

log "WARN: Checks fallidos: ${FAILED_NAMES[*]}"

FAIL_COUNT=$(read_fail_count)
FAIL_COUNT=$((FAIL_COUNT + 1))
write_fail_count "$FAIL_COUNT"
log "WARN: Ciclos consecutivos con fallo: $FAIL_COUNT/$MAX_FAILURES"

if [ "$FAIL_COUNT" -lt "$MAX_FAILURES" ]; then
    exit 0
fi

log "ALERTA: Umbral alcanzado. Reiniciando dns.service..."
if ! systemctl restart dns.service; then
    log "ERROR: Falló el reinicio de dns.service"
    exit 1
fi

log "INFO: dns.service reiniciado; esperando ${POST_RESTART_WAIT}s para revalidar"
sleep "$POST_RESTART_WAIT"

if ! check_service_active; then
    log "ERROR: dns.service NO está activo tras reinicio"
    exit 1
fi

if run_all_checks; then
    log "OK: Recuperación confirmada; los 5 checks pasan tras reinicio"
    clear_state
    exit 0
fi

# Se conserva el contador para no ocultar una recuperación fallida.
write_fail_count "$MAX_FAILURES"
log "CRITICAL: Persisten fallos tras reinicio: ${FAILED_NAMES[*]}"
exit 1
