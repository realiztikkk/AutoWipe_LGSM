#!/usr/bin/env bash

set -Eeuo pipefail

########################################
# Rust AutoWipe - Update Only
########################################

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CONFIG_PATH="$ROOT_DIR/config/wipe_config.json"

########################################
# JSON helpers
########################################

read_json() {
    python3 -c "
import json

with open('$CONFIG_PATH', 'r', encoding='utf-8') as f:
    data = json.load(f)

value = data

for key in '$1'.split('.'):
    value = value[key]

print(value)
"
}

read_json_optional() {
    python3 -c "
import json

with open('$CONFIG_PATH', 'r', encoding='utf-8') as f:
    data = json.load(f)

value = data

try:
    for key in '$1'.split('.'):
        value = value[key]

    print(value)

except Exception:
    print('$2')
"
}

########################################
# Config values
########################################

TIMEZONE="$(read_json timezone)"

LGSM_SCRIPT="$(read_json updates.lgsm_script)"

########################################
# Logs
########################################

LOG_DIR="$ROOT_DIR/logs"

mkdir -p "$LOG_DIR"

TIMESTAMP="$(TZ="$TIMEZONE" date +"%Y%m%d-%H%M%S")"

LOG_FILE="$LOG_DIR/update-only-$TIMESTAMP.log"

########################################
# Logging
########################################

log() {

    echo "[$(TZ="$TIMEZONE" date +"%Y-%m-%d %H:%M:%S")] $*" | tee -a "$LOG_FILE"
}

########################################
# Rust update
########################################

update_rust() {

    ENABLED="$(read_json_optional updates.rust_update_enabled true)"

    if [[ "$ENABLED" != "True" && "$ENABLED" != "true" ]]; then

        log "Rust update disabled."

        return
    fi

    log "Checking/updating Rust server..."

    "$LGSM_SCRIPT" update 2>&1 | tee -a "$LOG_FILE"

    log "Rust update check complete."
}

########################################
# Oxide/uMod update
########################################

update_oxide() {

    ENABLED="$(read_json_optional updates.oxide_update_enabled true)"

    if [[ "$ENABLED" != "True" && "$ENABLED" != "true" ]]; then

        log "Oxide/uMod update disabled."

        return
    fi

    log "Checking/updating Oxide/uMod..."

    "$LGSM_SCRIPT" mods-update 2>&1 | tee -a "$LOG_FILE"

    log "Oxide/uMod update check complete."
}

########################################
# Main
########################################

main() {

    log "======================================="
    log "Rust AutoWipe Update-Only Started"
    log "======================================="

    update_rust

    update_oxide

    log "======================================="
    log "Rust AutoWipe Update-Only Complete"
    log "======================================="
}

main "$@"