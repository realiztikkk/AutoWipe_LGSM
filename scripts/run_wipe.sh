#!/usr/bin/env bash

set -Eeuo pipefail

########################################
# Rust AutoWipe
########################################

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CONFIG_PATH="$ROOT_DIR/config/wipe_config.json"
PYTHON_SCRIPT="$ROOT_DIR/src/autowipe.py"

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

read_json_array() {
    python3 -c "
import json

with open('$CONFIG_PATH', 'r', encoding='utf-8') as f:
    data = json.load(f)

value = data

for key in '$1'.split('.'):
    value = value[key]

for item in value:
    print(item)
"
}

########################################
# Config values
########################################

TIMEZONE="$(read_json timezone)"

LGSM_CONFIG="$(read_json paths.lgsm_config)"
SERVER_CFG="$(read_json paths.server_cfg)"
BACKUP_DIR="$(read_json paths.backup_dir)"

LGSM_SCRIPT="$(read_json updates.lgsm_script)"

########################################
# Derived paths
########################################

SERVER_IDENTITY_DIR="$(dirname "$(dirname "$SERVER_CFG")")"

STATE_DIR="$ROOT_DIR/state"
LOG_DIR="$ROOT_DIR/logs"

mkdir -p "$STATE_DIR"
mkdir -p "$LOG_DIR"
mkdir -p "$BACKUP_DIR"

TIMESTAMP="$(TZ="$TIMEZONE" date +"%Y%m%d-%H%M%S")"

LOG_FILE="$LOG_DIR/wipe-$TIMESTAMP.log"

########################################
# Logging
########################################

log() {

    echo "[$(TZ="$TIMEZONE" date +"%Y-%m-%d %H:%M:%S")] $*" | tee -a "$LOG_FILE"
}

########################################
# Backup
########################################

backup_server_identity() {

    BACKUP_FILE="$BACKUP_DIR/server-identity-$TIMESTAMP.tar.gz"

    log "Creating server identity backup..."

    tar -czf "$BACKUP_FILE" "$SERVER_IDENTITY_DIR"

    log "Backup created:"
    log "$BACKUP_FILE"
}

########################################
# Stop server
########################################

stop_server() {

    log "Stopping Rust server..."

    "$LGSM_SCRIPT" stop

    log "Server stopped."
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

    log "Updating Rust server..."

    "$LGSM_SCRIPT" update 2>&1 | tee -a "$LOG_FILE"

    log "Rust update complete."
}

########################################
# Oxide/uMod update
########################################

update_oxide() {

    ENABLED="$(read_json_optional updates.oxide_update_enabled true)"

    if [[ "$ENABLED" != "True" && "$ENABLED" != "true" ]]; then
        log "Oxide update disabled."
        return
    fi

    log "Updating Oxide/uMod..."

    "$LGSM_SCRIPT" mods-update 2>&1 | tee -a "$LOG_FILE"

    log "Oxide/uMod update complete."
}

########################################
# Detect wipe
########################################

detect_wipe() {

    log "Checking wipe schedule..."

    if ! python3 "$PYTHON_SCRIPT" \
        --config "$CONFIG_PATH" \
        --dry-run >> "$LOG_FILE" 2>&1; then

        log "Wipe check failed."

        exit 1
    fi

    if grep -q "No wipe scheduled for today" "$LOG_FILE"; then

        log "No wipe scheduled today."

        exit 0
    fi

    if grep -q "This wipe has already been applied" "$LOG_FILE"; then

        log "This wipe has already been applied. Exiting without destructive actions."

        exit 0
    fi

    log "Wipe scheduled today."
}

########################################
# Apply wipe config
########################################

apply_wipe_config() {

    log "Applying wipe configuration..."

    python3 "$PYTHON_SCRIPT" \
        --config "$CONFIG_PATH" 2>&1 | tee -a "$LOG_FILE"

    log "Configuration updated."
}

########################################
# Delete Rust save files
########################################

wipe_rust_files() {

    log "Deleting Rust save/map/BP files..."

    find "$SERVER_IDENTITY_DIR" -maxdepth 1 -type f \( \
        -name "*.map" -o \
        -name "*.sav" -o \
        -name "*.sav.*" -o \
        -name "player.blueprints*.db" -o \
        -name "player.identities*.db" -o \
        -name "player.tokens*.db" \
    \) -print -delete | tee -a "$LOG_FILE"

    log "Rust wipe files deleted."
}

########################################
# Start server
########################################

start_server() {

    log "Starting Rust server..."

    "$LGSM_SCRIPT" start

    log "Server start command sent."
}

########################################
# Wait for boot
########################################

wait_after_start() {

    WAIT_SECONDS="$(read_json_optional post_start.wait_seconds_after_start 180)"

    log "Waiting $WAIT_SECONDS seconds for server startup..."

    sleep "$WAIT_SECONDS"
}

########################################
# Custom post-start script
########################################

run_custom_post_start_script() {

    ENABLED="$(read_json_optional post_start.custom_script.enabled false)"

    SCRIPT_PATH="$(read_json_optional post_start.custom_script.path '')"

    if [[ "$ENABLED" != "True" && "$ENABLED" != "true" ]]; then

        log "Custom post-start script disabled."

        return
    fi

    if [[ -z "$SCRIPT_PATH" ]]; then

        log "Custom script enabled but path missing."

        return
    fi

    if [[ ! -f "$SCRIPT_PATH" ]]; then

        log "Custom script not found:"
        log "$SCRIPT_PATH"

        return
    fi

    log "Running custom post-start script..."

    bash "$SCRIPT_PATH" 2>&1 | tee -a "$LOG_FILE"

    log "Custom post-start script complete."
}

########################################
# RCON commands
########################################

run_rcon_commands() {

    ENABLED="$(read_json_optional rcon.enabled false)"

    if [[ "$ENABLED" != "True" && "$ENABLED" != "true" ]]; then

        log "RCON commands disabled."

        return
    fi

    if ! command -v mcrcon >/dev/null 2>&1; then

        log "mcrcon is not installed."
        log "Install with:"
        log "sudo apt update && sudo apt install -y mcrcon"

        return
    fi

    HOST="$(read_json rcon.host)"
    PORT="$(read_json rcon.port)"
    PASSWORD="$(read_json rcon.password)"

    COMMAND_DELAY="$(read_json_optional rcon.command_delay_seconds 2)"

    log "Running configured RCON commands..."

    while IFS= read -r COMMAND; do

        [[ -z "$COMMAND" ]] && continue

        log "RCON: $COMMAND"

        mcrcon \
            -H "$HOST" \
            -P "$PORT" \
            -p "$PASSWORD" \
            "$COMMAND" 2>&1 | tee -a "$LOG_FILE"

        sleep "$COMMAND_DELAY"

    done < <(read_json_array post_start.server_commands)

    log "RCON commands complete."
}

########################################
# Main
########################################

main() {

    log "======================================="
    log "Rust AutoWipe Started"
    log "======================================="

    detect_wipe

    backup_server_identity

    stop_server

    update_rust

    update_oxide

    apply_wipe_config

    wipe_rust_files

    start_server

    wait_after_start

    run_custom_post_start_script

    run_rcon_commands

    log "======================================="
    log "Rust AutoWipe Complete"
    log "======================================="
}

main "$@"