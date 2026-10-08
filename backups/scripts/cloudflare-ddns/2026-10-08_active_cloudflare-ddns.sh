#!/bin/bash
# DDNS Cloudflare + Split Horizon auto-update
CONFIG_FILE="/etc/cloudflare-ddns/config"
SPLIT_CONFIG="/etc/dns/apps/Split Horizon/dnsApp.config"
LOG_FILE="/var/log/cloudflare-ddns.log"

[ ! -f "$CONFIG_FILE" ] && { echo "$(date '+%F %T') - ERROR: No existe $CONFIG_FILE" >> "$LOG_FILE"; exit 1; }
source "$CONFIG_FILE"
[ -z "$CF_API_TOKEN" ] || [ -z "$ZONE_NAME" ] || [ -z "$RECORD_NAME" ] && { echo "$(date '+%F %T') - ERROR: Faltan variables" >> "$LOG_FILE"; exit 1; }

log() { local msg="$(date '+%Y-%m-%d %H:%M:%S') - $1"; echo "$msg" >> "$LOG_FILE"; echo "$msg" >&2; }

check_connectivity() {
    local retry=0 max=10 wait=30
    while [ $retry -lt $max ]; do
        ping -c 1 -W 3 1.1.1.1 > /dev/null 2>&1 && return 0
        retry=$((retry + 1))
        [ $retry -lt $max ] && { log "WARN: Sin conectividad. Reintento $retry/$max en ${wait}s..."; sleep $wait; }
    done
    log "ERROR: Sin conectividad tras $max intentos."
    return 1
}

get_public_ip() {
    local ip_version=$1 ip="" retry=0 max=5 wait=30
    local services
    if [ "$ip_version" = "4" ]; then
        services=("https://api.ipify.org" "https://ifconfig.me/ip" "https://icanhazip.com")
    else
        services=("https://api6.ipify.org" "https://ifconfig.co" "https://icanhazip.com")
    fi
    while [ $retry -lt $max ]; do
        for service in "${services[@]}"; do
            [ "$ip_version" = "4" ] && ip=$(curl -4 -s --max-time 10 "$service" 2>/dev/null) || ip=$(curl -6 -s --max-time 10 "$service" 2>/dev/null)
            [ -n "$ip" ] && [[ "$ip" =~ ^[0-9a-fA-F.:]+$ ]] && echo "$ip" && return 0
        done
        retry=$((retry + 1))
        [ $retry -lt $max ] && { log "WARN: No se pudo obtener IPv$ip_version. Reintento $retry/$max en ${wait}s..."; sleep $wait; }
    done
    return 1
}

update_split_horizon() {
    local new_ip="$1"
    [ ! -f "$SPLIT_CONFIG" ] && return 1
    [ -z "$new_ip" ] && return 1

    local old_ip
    old_ip=$(python3 -c "
import json
try:
    with open('$SPLIT_CONFIG') as f: d = json.load(f)
    t = d.get('groups', [{}])[0].get('externalToInternalTranslation', {})
    print(list(t.keys())[0] if t else '')
except: print('')
" 2>/dev/null)

    [ "$old_ip" = "$new_ip" ] && { log "Split Horizon: sin cambios ($new_ip)"; return 0; }

    log "Split Horizon: actualizando $old_ip -> $new_ip"
    python3 <<PYEOF
import json
try:
    with open("$SPLIT_CONFIG", "r") as f: d = json.load(f)
    if "groups" in d and len(d["groups"]) > 0:
        d["groups"][0]["externalToInternalTranslation"] = {"$new_ip": "192.168.1.121"}
    with open("$SPLIT_CONFIG", "w") as f: json.dump(d, f, indent=4)
    exit(0)
except: exit(1)
PYEOF

    [ $? -eq 0 ] && { chown dns-server:dns-server "$SPLIT_CONFIG"; chmod 600 "$SPLIT_CONFIG"; log "Split Horizon actualizado"; return 1; }
    return 0
}

log "Iniciando actualización DDNS para $RECORD_NAME.$ZONE_NAME"
check_connectivity || { log "Abortando."; exit 0; }

ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$ZONE_NAME" -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" | jq -r '.result[0].id')
[ -z "$ZONE_ID" ] || [ "$ZONE_ID" = "null" ] && { log "ERROR: No Zone ID"; exit 1; }

CURRENT_IPV4=$(get_public_ip 4)
if [ -n "$CURRENT_IPV4" ]; then
    log "IPv4 pública actual: $CURRENT_IPV4"
    RECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=A&name=$RECORD_NAME.$ZONE_NAME" -H "Authorization: Bearer $CF_API_TOKEN" | jq -r '.result[0].id')
    if [ -n "$RECORD_ID" ] && [ "$RECORD_ID" != "null" ]; then
        EXISTING=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" -H "Authorization: Bearer $CF_API_TOKEN" | jq -r '.result.content')
        if [ "$EXISTING" != "$CURRENT_IPV4" ]; then
            log "Cloudflare A: $EXISTING -> $CURRENT_IPV4"
            curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" --data "{\"content\":\"$CURRENT_IPV4\"}" > /dev/null
        else
            log "Cloudflare A: sin cambios ($CURRENT_IPV4)"
        fi
    fi
    update_split_horizon "$CURRENT_IPV4"
    [ $? -eq 1 ] && { log "Reiniciando dns.service..."; systemctl restart dns.service; }
fi

CURRENT_IPV6=$(get_public_ip 6)
if [ -n "$CURRENT_IPV6" ]; then
    log "IPv6 pública actual: $CURRENT_IPV6"
    RECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=AAAA&name=$RECORD_NAME.$ZONE_NAME" -H "Authorization: Bearer $CF_API_TOKEN" | jq -r '.result[0].id')
    if [ -n "$RECORD_ID" ] && [ "$RECORD_ID" != "null" ]; then
        EXISTING=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" -H "Authorization: Bearer $CF_API_TOKEN" | jq -r '.result.content')
        if [ "$EXISTING" != "$CURRENT_IPV6" ]; then
            log "Cloudflare AAAA: $EXISTING -> $CURRENT_IPV6"
            curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" --data "{\"content\":\"$CURRENT_IPV6\"}" > /dev/null
        else
            log "Cloudflare AAAA: sin cambios ($CURRENT_IPV6)"
        fi
    fi
fi
log "Proceso completado"
