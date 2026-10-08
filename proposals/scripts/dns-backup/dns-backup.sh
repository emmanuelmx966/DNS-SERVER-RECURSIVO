#!/bin/bash
# PROPUESTA — Backup robusto para Technitium DNS Server
# No instalar hasta completar pruebas controladas.
set -u

BACKUP_DIR="/root/backups"
RETENTION_DAYS=30
LOG_FILE="/var/log/dns-backup.log"
LOCK_FILE="/run/dns-backup.lock"

umask 077

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

for cmd in tar sha256sum flock find mktemp getent id; do
    command -v "$cmd" >/dev/null 2>&1 || { log "ERROR: Dependencia ausente: $cmd"; exit 2; }
done

[ "${EUID:-$(id -u)}" -eq 0 ] || { log "ERROR: Este script debe ejecutarse como root"; exit 2; }

exec 9>"$LOCK_FILE"
flock -n 9 || { log "WARN: Ya existe otra ejecución de backup activa"; exit 0; }

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

ARCHIVE_PATHS=(
    "etc/dns"
    "etc/technitium"
    "etc/cloudflare-ddns"
    "usr/local/bin/cloudflare-ddns.sh"
    "usr/local/bin/dns-backup.sh"
    "usr/local/bin/dns-healthcheck.sh"
    "etc/systemd/system/cloudflare-ddns.service"
    "etc/systemd/system/cloudflare-ddns.timer"
    "etc/systemd/system/dns.service"
    "etc/systemd/system/dns-backup.service"
    "etc/systemd/system/dns-backup.timer"
    "etc/systemd/system/dns-healthcheck.service"
    "etc/systemd/system/dns-healthcheck.timer"
    "etc/letsencrypt"
    "etc/netplan"
    "etc/hosts"
)

for path in "${ARCHIVE_PATHS[@]}"; do
    if [ ! -e "/$path" ]; then
        log "ERROR: Ruta requerida ausente: /$path"
        exit 1
    fi
done

FECHA=$(date +%F_%H%M%S)
FINAL_FILE="$BACKUP_DIR/dns-backup-$FECHA.tar.gz"
PARTIAL_FILE="$FINAL_FILE.partial"
CHECKSUM_FILE="$FINAL_FILE.sha256"
META_DIR=$(mktemp -d "$BACKUP_DIR/.metadata.XXXXXX")
TAR_ERROR=$(mktemp "$BACKUP_DIR/.tar-error.XXXXXX")

cleanup() {
    rm -rf "$META_DIR" "$TAR_ERROR"
}
trap cleanup EXIT

find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.partial' -mtime +1 -delete 2>/dev/null || true

{
    echo "DNS SERVER RECOVERY METADATA"
    echo "Generated: $(date --iso-8601=seconds)"
    echo "Hostname: $(hostname)"
    echo
    echo "=== OS ==="
    cat /etc/os-release 2>/dev/null || true
    echo
    echo "=== Required users ==="
    getent passwd dns-server 2>/dev/null || true
    getent passwd emmanuel 2>/dev/null || true
    echo
    echo "=== Required groups ==="
    getent group dns-server 2>/dev/null || true
    getent group emmanuel 2>/dev/null || true
    echo
    echo "=== IDs ==="
    id dns-server 2>/dev/null || true
    id emmanuel 2>/dev/null || true
    echo
    echo "=== Script SHA-256 ==="
    sha256sum \
        /usr/local/bin/cloudflare-ddns.sh \
        /usr/local/bin/dns-backup.sh \
        /usr/local/bin/dns-healthcheck.sh 2>/dev/null || true
} > "$META_DIR/recovery-metadata.txt"
chmod 600 "$META_DIR/recovery-metadata.txt"

log "Iniciando backup: $FINAL_FILE"

if ! tar -C / -czf "$PARTIAL_FILE" \
    "${ARCHIVE_PATHS[@]}" \
    -C "$META_DIR" recovery-metadata.txt \
    2>"$TAR_ERROR"; then
    log "ERROR: No se pudo crear backup"
    while IFS= read -r line; do log "tar: $line"; done < "$TAR_ERROR"
    rm -f "$PARTIAL_FILE"
    exit 1
fi

if ! tar -tzf "$PARTIAL_FILE" >/dev/null 2>"$TAR_ERROR"; then
    log "ERROR: Backup corrupto o ilegible"
    while IFS= read -r line; do log "tar: $line"; done < "$TAR_ERROR"
    rm -f "$PARTIAL_FILE"
    exit 1
fi

mv "$PARTIAL_FILE" "$FINAL_FILE"
chmod 600 "$FINAL_FILE"

(
    cd "$BACKUP_DIR" || exit 1
    sha256sum "$(basename "$FINAL_FILE")" > "$(basename "$CHECKSUM_FILE")"
) || {
    log "ERROR: No se pudo generar SHA-256"
    rm -f "$FINAL_FILE" "$CHECKSUM_FILE"
    exit 1
}
chmod 600 "$CHECKSUM_FILE"

SIZE=$(du -h "$FINAL_FILE" | cut -f1)
log "Backup creado y verificado: $FINAL_FILE ($SIZE)"
log "SHA-256: $(cut -d' ' -f1 "$CHECKSUM_FILE")"

ELIMINADOS=$(find "$BACKUP_DIR" -maxdepth 1 -type f \
    \( -name 'dns-backup-*.tar.gz' -o -name 'dns-backup-*.tar.gz.sha256' \) \
    -mtime +"$RETENTION_DAYS" -print -delete | wc -l)
[ "$ELIMINADOS" -gt 0 ] && log "Archivos de backups antiguos eliminados: $ELIMINADOS"

log "Backup completado correctamente"
exit 0
