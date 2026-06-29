# Rust AutoWipe

A LinuxGSM-focused Rust wipe automation tool.

Built for Rust server owners who want predictable wipe-day automation without modifying LinuxGSM internals.

## Features

- Scheduled wipe profiles
- Daily safe-check mode for cron/systemd
- Procedural map support
- Custom map URL support
- Per-wipe seed, world size, description, and header image
- Rust server update through LinuxGSM
- Oxide/uMod update through LinuxGSM `mods-update`
- Separate hotfix/update-only script
- Safe config backups before editing
- Rust map/save/player/BP file deletion
- Post-start RCON commands
- Optional post-start custom script
- State file prevents duplicate wipe application
- AutoWipe-managed LGSM launch parameter block

## Project Structure

```text
rust-autowipe/
├── README.md
├── .gitignore
├── config/
│   └── wipe_config.example.json
├── src/
│   └── autowipe.py
├── scripts/
│   ├── run_wipe.sh
│   ├── update_only.sh
│   └── install.sh
├── state/
│   └── .gitkeep
└── logs/
```

## How It Works

Rust AutoWipe is designed to be called by cron or systemd once per day near wipe time.

Example wipe cron:

```cron
5 19 * * * /opt/rust-autowipe/scripts/run_wipe.sh >> /opt/rust-autowipe/logs/cron.log 2>&1
```

The wipe script checks your configured wipe profiles.

If today is not a wipe date, it exits safely.

If today is a wipe date that has already been applied, it exits safely without stopping the server or deleting files.

If today is a new wipe date, it:

1. Backs up server config and identity files.
2. Stops the Rust server.
3. Updates Rust through LinuxGSM.
4. Updates Oxide/uMod through LinuxGSM `mods-update`.
5. Applies the configured wipe profile.
6. Updates LGSM map launch parameters.
7. Updates `server.cfg` description, header image, seed, and world size.
8. Deletes Rust map/save/player/BP files.
9. Starts the server.
10. Waits for the server to boot.
11. Optionally runs a user-defined custom script.
12. Runs configured RCON commands.
13. Writes state so the same wipe is not applied twice.

Separate from wipe execution, `update_only.sh` performs scheduled Rust hotfix checks and Oxide/uMod updates without wiping the server.

## Why Not Modify LinuxGSM Internals?

Some setups modify LinuxGSM module files to run Oxide updates automatically.

This project avoids that.

LinuxGSM should stay stock.

Rust AutoWipe owns the wipe/update process instead.

Recommended cron after setup:

```cron
# Keep server online
*/5 * * * * /home/rustserver/rustserver monitor > /dev/null 2>&1

# Rust hotfix updates + Oxide/uMod updates
15 * * * * /opt/rust-autowipe/scripts/update_only.sh >> /opt/rust-autowipe/logs/update-only-cron.log 2>&1

# Wipe-day automation
5 19 * * * /opt/rust-autowipe/scripts/run_wipe.sh >> /opt/rust-autowipe/logs/cron.log 2>&1
```

Avoid duplicate update jobs like:

```cron
1 * * * * /home/rustserver/rustserver update && /home/rustserver/rustserver mods-update
0 12 * * * /home/rustserver/update_rust.sh
```

Duplicate update jobs can conflict with wipe automation.

## Installation

Clone the project:

```bash
cd /opt
git clone https://github.com/YOUR_USERNAME/rust-autowipe.git
cd rust-autowipe
```

Run installer:

```bash
chmod +x scripts/install.sh
scripts/install.sh
```

Copy example config if needed:

```bash
cp config/wipe_config.example.json config/wipe_config.json
```

Edit your live config:

```bash
nano config/wipe_config.json
```

## Config

All behavior should be controlled from:

```text
config/wipe_config.json
```

Important sections:

```json
"updates": {
  "rust_update_enabled": true,
  "oxide_update_enabled": true,
  "lgsm_script": "/home/rustserver/rustserver"
}
```

```json
"rcon": {
  "enabled": true,
  "host": "127.0.0.1",
  "port": 28016,
  "password": "CHANGE_ME",
  "command_delay_seconds": 2
}
```

Each wipe profile controls:

- wipe datetime
- next wipe datetime
- procedural/custom map mode
- seed
- world size
- custom map URL
- server browser description
- header image

## Procedural Maps

A procedural wipe uses:

```json
"map": {
  "type": "procedural",
  "seed": 123456789,
  "worldsize": 4250,
  "customlevelurl": null
}
```

## Custom Maps

A custom map wipe uses:

```json
"map": {
  "type": "custom",
  "seed": 12345,
  "worldsize": 4500,
  "customlevelurl": "https://example.com/custom-map.map"
}
```

The script manages LinuxGSM launch parameters using an AutoWipe-managed block.

## Hotfix / Update-Only Mode

`update_only.sh` is designed for non-wipe Rust hotfixes.

It runs:

1. LinuxGSM Rust update check.
2. LinuxGSM Oxide/uMod `mods-update`.

It does not:

- apply wipe profiles
- delete map files
- delete blueprint files
- edit descriptions
- change seeds
- restart for a wipe

Recommended cron:

```cron
15 * * * * /opt/rust-autowipe/scripts/update_only.sh >> /opt/rust-autowipe/logs/update-only-cron.log 2>&1
```

This is useful after monthly force wipe because Rust hotfixes and Oxide updates often happen again shortly after wipe.

## Post-Start RCON Commands

After the server starts and waits for the configured boot delay, AutoWipe can run server commands through RCON.

Example:

```json
"post_start": {
  "wait_seconds_after_start": 180,
  "server_commands": [
    "say Server wipe complete.",
    "server.writecfg"
  ],
  "custom_script": {
    "enabled": false,
    "path": "/opt/rust-autowipe/scripts/custom_post_wipe.sh"
  }
}
```

## Optional Custom Script

Users can provide their own script without editing AutoWipe files.

Example:

```json
"custom_script": {
  "enabled": true,
  "path": "/opt/rust-autowipe/scripts/custom_post_wipe.sh"
}
```

This is useful for:

- Discord notifications
- website updates
- plugin maintenance
- external backups
- custom cleanup

## Testing

Dry run:

```bash
python3 src/autowipe.py --config config/wipe_config.json --dry-run
```

Test a specific wipe date:

```bash
python3 src/autowipe.py --config config/wipe_config.json --target-datetime "2026-07-02T19:10:00+00:00" --dry-run
```

Test update-only mode:

```bash
scripts/update_only.sh
```

Run full wipe manually:

```bash
scripts/run_wipe.sh
```

## Requirements

- Linux
- Python 3.10+
- LinuxGSM Rust server
- Oxide/uMod installed through LinuxGSM mods system
- `mcrcon` if using post-start RCON commands

Install mcrcon:

```bash
sudo apt update
sudo apt install -y mcrcon
```

## Warning

This tool deletes Rust map/save/player/BP files on configured wipe dates.

Always test with `--dry-run` first.
## Safety Notes

- Keep your live `config/wipe_config.json`, `state/`, `logs/`, and backup folders out of Git.
- Test new releases on a copied server or with `--dry-run` before wipe day.
- Schedule `run_wipe.sh` at or shortly after the configured wipe time. AutoWipe will not apply a wipe before the configured `wipe_datetime`.
- `run_wipe.sh` and `update_only.sh` use a lock file so update-only jobs and wipe jobs do not run at the same time.

## Recent Hardening

- Prevented duplicate same-day destructive wipe runs.
- Fixed `server.seed` config rotation crash.
- Moved final wipe state marking until after Rust save/map/BP files are deleted.
- Added process locking to avoid overlapping cron jobs.
- Wipe detection now respects the configured wipe time, not just the wipe date.
