#!/usr/bin/env bash

set -Eeuo pipefail

########################################
# Rust AutoWipe Installer
########################################

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CONFIG_EXAMPLE="$PROJECT_DIR/config/wipe_config.example.json"
CONFIG_FILE="$PROJECT_DIR/config/wipe_config.json"

STATE_DIR="$PROJECT_DIR/state"
LOG_DIR="$PROJECT_DIR/logs"

########################################
# Banner
########################################

echo
echo "======================================="
echo "Rust AutoWipe Installer"
echo "======================================="
echo

########################################
# Create directories
########################################

mkdir -p "$STATE_DIR"
mkdir -p "$LOG_DIR"

echo "[OK] Created runtime directories."

########################################
# Create live config
########################################

if [[ ! -f "$CONFIG_FILE" ]]; then

    cp "$CONFIG_EXAMPLE" "$CONFIG_FILE"

    echo "[OK] Created:"
    echo "     config/wipe_config.json"

else

    echo "[INFO] Existing config found:"
    echo "       config/wipe_config.json"

fi

########################################
# Permissions
########################################

chmod +x "$PROJECT_DIR/src/autowipe.py"
chmod +x "$PROJECT_DIR/scripts/run_wipe.sh"
chmod +x "$PROJECT_DIR/scripts/update_only.sh"
chmod +x "$PROJECT_DIR/scripts/install.sh"

echo "[OK] Executable permissions applied."

########################################
# Dependency checks
########################################

echo
echo "Checking dependencies..."
echo

########################################
# Python
########################################

if command -v python3 >/dev/null 2>&1; then

    echo "[OK] python3 found:"
    python3 --version

else

    echo "[ERROR] python3 not found."
    echo "Install Python 3.10+ before continuing."

    exit 1
fi

########################################
# mcrcon
########################################

if command -v mcrcon >/dev/null 2>&1; then

    echo "[OK] mcrcon found."

else

    echo "[WARNING] mcrcon not installed."
    echo
    echo "Install with:"
    echo
    echo "sudo apt update && sudo apt install -y mcrcon"
    echo
fi

########################################
# Finish
########################################

echo
echo "======================================="
echo "Install Complete"
echo "======================================="
echo

echo "Next Steps:"
echo

echo "1. Edit your live config:"
echo
echo "   nano config/wipe_config.json"
echo

echo "2. Test wipe detection:"
echo
echo "   python3 src/autowipe.py --config config/wipe_config.json --dry-run"
echo

echo "3. Test a specific wipe date:"
echo
echo "   python3 src/autowipe.py --config config/wipe_config.json --target-datetime \"2026-06-04T11:10:00-07:00\" --dry-run"
echo

echo "4. Test hotfix/update-only mode:"
echo
echo "   scripts/update_only.sh"
echo

echo "5. Run a manual wipe test:"
echo
echo "   scripts/run_wipe.sh"
echo

echo "6. Add cron job:"
echo
echo "   crontab -e"
echo

echo "Recommended cron:"
echo

echo "*/5 * * * * /data1/rustserver monitor > /dev/null 2>&1"
echo "15 * * * * /opt/rust-autowipe/scripts/update_only.sh >> /opt/rust-autowipe/logs/update-only-cron.log 2>&1"
echo "5 11 * * * /opt/rust-autowipe/scripts/run_wipe.sh >> /opt/rust-autowipe/logs/cron.log 2>&1"

echo
echo "Rust AutoWipe is ready."
echo