#!/bin/bash
# PROPUESTA — DDNS Cloudflare + Split Horizon robusto
# No instalar hasta completar pruebas controladas.
set -u

CONFIG_FILE="/etc/cloudflare-ddns/config"
SPLIT_CONFIG="/etc/dns/apps/Split Horizon/dnsApp.config"
LOG_FILE="/var/log/cloudflare-ddns.log"
LOCK_FILE="/run/cloudflare-ddns.lock"
LAN_IP="192.168.1.121"
API_BASE="https://api.cloudflare.com/client/v4"

umask 077

log() {
    local msg="$(date '+%Y-%m-%d %H:%M:%S') - $1"
    echo "$msg" >> "$LOG_FILE"
    echo "$msg" >&2
}

for cmd in curl jq python3 flock systemctl stat; do
    command -v "$cmd" >/dev/null 2>&1 || { log "ERROR: Dependencia ausente: $cmd"; exit 2; }
done

[ "${EUID:-$(id -u)}" -eq 0 ] || { log "ERROR: Este script debe ejecutarse como root"; exit 2; }

exec 9>"$LOCK_FILE"
flock -n 9 || { log "WARN: Ya existe otra ejecución activa; se omite esta ejecución"; exit 0; }

[ -f "$CONFIG_FILE" ] || { log "ERROR: No existe $CONFIG_FILE"; exit 1; }
[ "$(stat -c '%u' "$CONFIG_FILE")" = "0" ] || { log "ERROR: $CONFIG_FILE no pertenece a root"; exit 1; }
if find "$CONFIG_FILE" -perm /022 -print -quit | grep -q .; then
    log "ERROR: $CONFIG_FILE es escribible por grupo u otros"
    exit 1
fi

# El archivo de configuración es código shell confiable administrado por root.
# shellcheck disable=SC1090
source "$CONFIG_FILE"
[ -n "${CF_API_TOKEN:-}" ] && [ -n "${ZONE_NAME:-}" ] && [ -n "${RECORD_NAME:-}" ] || {
    log "ERROR: Faltan CF_API_TOKEN, ZONE_NAME o RECORD_NAME"
    exit 1
}

validate_ip() {
    python3 - "$1" "$2" <<'PY'
import ipaddress
import sys

version = int(sys.argv[1])
value = sys.argv[2]
try:
    ip = ipaddress.ip_address(value)
except ValueError:
    raise SystemExit(1)
if ip.version != version:
    raise SystemExit(1)
if not ip.is_global:
    raise SystemExit(1)
print(ip.compressed)
PY
}

get_public_ip() {
    local ip_version="$1" ip="" validated="" retry=0 max=5 wait=30
    local services=()

    if [ "$ip_version" = "4" ]; then
        services=("https://api.ipify.org" "https://ifconfig.me/ip" "https://icanhazip.com")
    else
        services=("https://api6.ipify.org" "https://ifconfig.co/ip" "https://icanhazip.com")
    fi

    while [ "$retry" -lt "$max" ]; do
        for service in "${services[@]}"; do
            if [ "$ip_version" = "4" ]; then
                ip=$(curl -4 -fsS --max-time 10 "$service" 2>/dev/null | tr -d '[:space:]') || ip=""
            else
                ip=$(curl -6 -fsS --max-time 10 "$service" 2>/dev/null | tr -d '[:space:]') || ip=""
            fi
            [ -n "$ip" ] || continue
            if validated=$(validate_ip "$ip_version" "$ip" 2>/dev/null); then
                echo "$validated"
                return 0
            fi
        done
        retry=$((retry + 1))
        [ "$retry" -lt "$max" ] && { log "WARN: No se pudo obtener IPv$ip_version. Reintento $retry/$max en ${wait}s..."; sleep "$wait"; }
    done
    return 1
}

cloudflare_errors() {
    jq -r '[.errors[]?.message] | join("; ")' 2>/dev/null
}

get_zone_id() {
    local response zone_id
    response=$(curl -sS --max-time 20 -G "$API_BASE/zones" \
        --data-urlencode "name=$ZONE_NAME" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json") || {
        log "ERROR: No se pudo consultar Zone ID en Cloudflare"
        return 1
    }

    if ! jq -e '.success == true' >/dev/null 2>&1 <<<"$response"; then
        log "ERROR: Cloudflare rechazó Zone ID: $(cloudflare_errors <<<"$response")"
        return 1
    fi

    zone_id=$(jq -r '.result[0].id // empty' <<<"$response")
    [ -n "$zone_id" ] || { log "ERROR: No Zone ID para $ZONE_NAME"; return 1; }
    echo "$zone_id"
}

update_record() {
    local zone_id="$1" record_type="$2" new_ip="$3"
    local fqdn="$RECORD_NAME.$ZONE_NAME" response record_id existing payload

    response=$(curl -sS --max-time 20 -G "$API_BASE/zones/$zone_id/dns_records" \
        --data-urlencode "type=$record_type" \
        --data-urlencode "name=$fqdn" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json") || {
        log "ERROR: No se pudo consultar registro $record_type"
        return 1
    }

    if ! jq -e '.success == true' >/dev/null 2>&1 <<<"$response"; then
        log "ERROR: Cloudflare rechazó consulta $record_type: $(cloudflare_errors <<<"$response")"
        return 1
    fi

    record_id=$(jq -r '.result[0].id // empty' <<<"$response")
    existing=$(jq -r '.result[0].content // empty' <<<"$response")
    [ -n "$record_id" ] || { log "ERROR: Registro $record_type $fqdn no encontrado"; return 1; }

    if [ "$existing" = "$new_ip" ]; then
        log "Cloudflare $record_type: sin cambios ($new_ip)"
        return 0
    fi

    payload=$(jq -nc --arg content "$new_ip" '{content:$content}')
    response=$(curl -sS --max-time 20 -X PATCH "$API_BASE/zones/$zone_id/dns_records/$record_id" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "$payload") || {
        log "ERROR: Falló PATCH del registro $record_type"
        return 1
    }

    if jq -e '.success == true' >/dev/null 2>&1 <<<"$response"; then
        log "Cloudflare $record_type actualizado: $existing -> $new_ip"
        return 0
    fi

    log "ERROR: Cloudflare rechazó PATCH $record_type: $(cloudflare_errors <<<"$response")"
    return 1
}

update_split_horizon() {
    local new_ip="$1"
    [ -f "$SPLIT_CONFIG" ] || { log "ERROR: No existe $SPLIT_CONFIG"; return 1; }

    python3 - "$SPLIT_CONFIG" "$new_ip" "$LAN_IP" <<'PY'
import grp
import json
import os
import pwd
import sys
import tempfile

path, new_ip, lan_ip = sys.argv[1:4]
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)

    groups = data.get("groups")
    if not isinstance(groups, list) or not groups:
        raise ValueError("groups ausente o vacío")

    translations = groups[0].get("externalToInternalTranslation")
    if not isinstance(translations, dict):
        raise ValueError("externalToInternalTranslation inválido")

    managed = [key for key, value in translations.items() if value == lan_ip]
    if translations.get(new_ip) == lan_ip and all(key == new_ip for key in managed):
        raise SystemExit(0)

    for key in managed:
        translations.pop(key, None)
    translations[new_ip] = lan_ip

    directory = os.path.dirname(path)
    fd, tmp = tempfile.mkstemp(prefix=".dnsApp.config.", dir=directory, text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=4)
            f.write("\n")
            f.flush()
            os.fsync(f.fileno())

        uid = pwd.getpwnam("dns-server").pw_uid
        gid = grp.getgrnam("dns-server").gr_gid
        os.chown(tmp, uid, gid)
        os.chmod(tmp, 0o600)

        with open(tmp, "r", encoding="utf-8") as f:
            json.load(f)

        os.replace(tmp, path)
        dir_fd = os.open(directory, os.O_DIRECTORY)
        try:
            os.fsync(dir_fd)
        finally:
            os.close(dir_fd)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
except SystemExit:
    raise
except Exception as exc:
    print(str(exc), file=sys.stderr)
    raise SystemExit(1)

raise SystemExit(10)
PY
}

log "Iniciando actualización DDNS para $RECORD_NAME.$ZONE_NAME"

CURRENT_IPV4=""
CURRENT_IPV6=""
CURRENT_IPV4=$(get_public_ip 4) || log "WARN: IPv4 pública no disponible"
CURRENT_IPV6=$(get_public_ip 6) || log "WARN: IPv6 pública no disponible"

if [ -z "$CURRENT_IPV4" ] && [ -z "$CURRENT_IPV6" ]; then
    log "ERROR: No hay conectividad IPv4 ni IPv6 utilizable"
    exit 1
fi

ZONE_ID=$(get_zone_id) || exit 1
ERRORS=0

if [ -n "$CURRENT_IPV4" ]; then
    log "IPv4 pública actual: $CURRENT_IPV4"
    update_record "$ZONE_ID" "A" "$CURRENT_IPV4" || ERRORS=$((ERRORS + 1))

    update_split_horizon "$CURRENT_IPV4"
    SPLIT_RC=$?
    case "$SPLIT_RC" in
        0)
            log "Split Horizon: sin cambios ($CURRENT_IPV4)"
            ;;
        10)
            log "Split Horizon actualizado: $CURRENT_IPV4 -> $LAN_IP"
            log "Reiniciando dns.service..."
            if systemctl restart dns.service; then
                log "dns.service reiniciado correctamente"
            else
                log "ERROR: No se pudo reiniciar dns.service"
                ERRORS=$((ERRORS + 1))
            fi
            ;;
        *)
            log "ERROR: No se pudo actualizar Split Horizon"
            ERRORS=$((ERRORS + 1))
            ;;
    esac
fi

if [ -n "$CURRENT_IPV6" ]; then
    log "IPv6 pública actual: $CURRENT_IPV6"
    update_record "$ZONE_ID" "AAAA" "$CURRENT_IPV6" || ERRORS=$((ERRORS + 1))
fi

if [ "$ERRORS" -gt 0 ]; then
    log "Proceso completado con $ERRORS error(es)"
    exit 1
fi

log "Proceso completado correctamente"
exit 0
