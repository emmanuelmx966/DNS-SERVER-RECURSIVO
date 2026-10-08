#!/bin/bash
# Backup automático del servidor DNS
BACKUP_DIR="/root/backups"
RETENTION_DAYS=30
LOG_FILE="/var/log/dns-backup.log"

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"; }

log "Iniciando backup..."

FECHA=$(date +%F_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/dns-backup-$FECHA.tar.gz"

if tar -czf "$BACKUP_FILE" \
    /etc/dns \
    /etc/technitium \
    /etc/cloudflare-ddns \
    /usr/local/bin/cloudflare-ddns.sh \
    /etc/systemd/system/cloudflare-ddns.service \
    /etc/systemd/system/cloudflare-ddns.timer \
    /etc/systemd/system/dns.service \
    /etc/systemd/system/dns-backup.service \
    /etc/systemd/system/dns-backup.timer \
    /etc/systemd/system/dns-healthcheck.service \
    /etc/systemd/system/dns-healthcheck.timer \
    /usr/local/bin/dns-backup.sh \
    /usr/local/bin/dns-healthcheck.sh \
    /etc/letsencrypt/live \
    /etc/letsencrypt/renewal \
    /etc/letsencrypt/renewal-hooks \
    /etc/netplan \
    /etc/hosts \
    2>/dev/null; then

    SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    log "Backup creado: $BACKUP_FILE ($SIZE)"

    if tar -tzf "$BACKUP_FILE" > /dev/null 2>&1; then
        log "Backup verificado correctamente"
    else
        log "ERROR: Backup corrupto"
        exit 1
    fi
else
    log "ERROR: No se pudo crear backup"
    exit 1
fi

ELIMINADOS=$(find "$BACKUP_DIR" -name "dns-backup-*.tar.gz" -mtime +$RETENTION_DAYS -delete -print | wc -l)
[ "$ELIMINADOS" -gt 0 ] && log "Backups antiguos eliminados: $ELIMINADOS"

log "Backup completado"
