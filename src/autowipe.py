#!/usr/bin/env python3

import argparse
import json
import re
import shutil
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo


MANAGED_BEGIN = "### AUTOWIPE MANAGED STARTPARAMETERS BEGIN ###"
MANAGED_END = "### AUTOWIPE MANAGED STARTPARAMETERS END ###"


def load_config(config_path: Path) -> dict:
    with config_path.open("r", encoding="utf-8") as file:
        return json.load(file)


def backup_file(path: Path, backup_dir: Path) -> None:
    if not path.exists():
        raise FileNotFoundError(f"Cannot back up missing file: {path}")

    backup_dir.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_path = backup_dir / f"{path.name}.{timestamp}.bak"

    shutil.copy2(path, backup_path)

    print(f"[BACKUP] {path} -> {backup_path}")


def get_due_wipe(config: dict, target_datetime: str | None = None) -> dict | None:
    timezone = ZoneInfo(config["timezone"])

    if target_datetime:
        now = datetime.fromisoformat(target_datetime)
    else:
        now = datetime.now(timezone)

    if now.tzinfo is None:
        now = now.replace(tzinfo=timezone)

    today = now.date()

    for wipe in config["wipes"]:
        wipe_time = datetime.fromisoformat(wipe["wipe_datetime"])

        if wipe_time.date() == today:
            return wipe

    return None


def shell_quote_value(value: str | int) -> str:
    text = str(value)
    text = text.replace('"', '\\"')
    return f'"{text}"'


def set_or_insert_variable(
    content: str,
    key: str,
    value: str | int,
    insert_after_key: str | None = None
) -> str:

    replacement = f'{key}={shell_quote_value(value)}'

    pattern = rf'^\s*#?\s*{re.escape(key)}=".*?"\s*(?:#.*)?$'

    if re.search(pattern, content, flags=re.MULTILINE):
        return re.sub(pattern, replacement, content, flags=re.MULTILINE)

    if insert_after_key:
        insert_pattern = rf'^({re.escape(insert_after_key)}=".*?"\s*(?:#.*)?$)'

        if re.search(insert_pattern, content, flags=re.MULTILINE):
            return re.sub(
                insert_pattern,
                rf'\1\n{replacement}',
                content,
                count=1,
                flags=re.MULTILINE
            )

    return content.rstrip() + f"\n{replacement}\n"


def build_startparameters_block(map_type: str) -> str:

    custom_line = (
        'startparameters="-batchmode '
        '+app.listenip ${ip} '
        '+app.port ${appport} '
        '+server.ip ${ip} '
        '+server.port ${port} '
        '+server.queryport ${queryport} '
        '+server.tickrate ${tickrate} '
        '+server.hostname \\"${servername}\\" '
        '+server.identity \\"${selfname}\\" '
        '+server.gamemode ${gamemode} '
        '+server.levelurl \\"${customlevelurl}\\" '
        '+server.maxplayers ${maxplayers} '
        '+server.saveinterval ${saveinterval} '
        '+rcon.web ${rconweb} '
        '+rcon.ip ${ip} '
        '+rcon.port ${rconport} '
        '+rcon.password \\"${rconpassword}\\" '
        '+server.tags ${tags} '
        '-logfile ${gamelog}"'
    )

    procedural_line = (
        'startparameters="-batchmode '
        '+app.listenip ${ip} '
        '+app.port ${appport} '
        '+server.ip ${ip} '
        '+server.port ${port} '
        '+server.queryport ${queryport} '
        '+server.tickrate ${tickrate} '
        '+server.hostname \\"${servername}\\" '
        '+server.identity \\"${selfname}\\" '
        '+server.gamemode ${gamemode} '
        '+server.level \\"${serverlevel}\\" '
        '+server.seed ${seed} '
        '+server.salt ${salt} '
        '+server.maxplayers ${maxplayers} '
        '+server.worldsize ${worldsize} '
        '+server.saveinterval ${saveinterval} '
        '+rcon.web ${rconweb} '
        '+rcon.ip ${ip} '
        '+rcon.port ${rconport} '
        '+rcon.password \\"${rconpassword}\\" '
        '+server.tags ${tags} '
        '-logfile ${gamelog}"'
    )

    if map_type == "custom":
        custom_output = custom_line
        procedural_output = "#" + procedural_line

    elif map_type == "procedural":
        custom_output = "#" + custom_line
        procedural_output = procedural_line

    else:
        raise ValueError(f"Unknown map type: {map_type}")

    return "\n".join(
        [
            MANAGED_BEGIN,
            "# AutoWipe controls which Rust launch mode is active.",
            "# Edit this block only if you know what you are doing.",
            "",
            "# Custom map mode:",
            custom_output,
            "",
            "# Procedural map mode:",
            procedural_output,
            MANAGED_END,
        ]
    )


def remove_unmanaged_startparameters(content: str) -> str:

    lines = content.splitlines()

    cleaned = []

    inside_managed = False

    for line in lines:

        if line.strip() == MANAGED_BEGIN:
            inside_managed = True
            cleaned.append(line)
            continue

        if line.strip() == MANAGED_END:
            inside_managed = False
            cleaned.append(line)
            continue

        if inside_managed:
            cleaned.append(line)
            continue

        stripped = line.lstrip("#").strip()

        if stripped.startswith("startparameters="):
            cleaned.append("# AUTOWIPE DISABLED OLD LINE: " + stripped)

        else:
            cleaned.append(line)

    return "\n".join(cleaned) + "\n"


def upsert_managed_block(content: str, block: str) -> str:

    pattern = rf'{re.escape(MANAGED_BEGIN)}.*?{re.escape(MANAGED_END)}'

    if re.search(pattern, content, flags=re.DOTALL):
        return re.sub(
            pattern,
            block,
            content,
            count=1,
            flags=re.DOTALL
        )

    marker = "## Server Parameters"

    if marker in content:
        return content.replace(marker, f"{marker}\n{block}", 1)

    return content.rstrip() + "\n\n" + block + "\n"


def update_lgsm_config(config: dict, wipe: dict) -> None:

    lgsm_path = Path(config["paths"]["lgsm_config"])

    content = lgsm_path.read_text(encoding="utf-8")

    server_defaults = config["server_defaults"]
    map_data = wipe["map"]

    map_type = map_data["type"]

    seed = map_data["seed"]
    worldsize = map_data["worldsize"]
    customlevelurl = map_data.get("customlevelurl") or ""

    content = set_or_insert_variable(
        content,
        "servername",
        server_defaults["name"]
    )

    content = set_or_insert_variable(
        content,
        "gamemode",
        server_defaults["gamemode"]
    )

    content = set_or_insert_variable(
        content,
        "serverlevel",
        server_defaults.get("level", "Procedural Map")
    )

    content = set_or_insert_variable(content, "seed", seed)

    content = set_or_insert_variable(content, "worldsize", worldsize)

    content = set_or_insert_variable(
        content,
        "customlevelurl",
        customlevelurl,
        insert_after_key="serverlevel"
    )

    content = set_or_insert_variable(
        content,
        "maxplayers",
        server_defaults["max_players"]
    )

    content = set_or_insert_variable(
        content,
        "saveinterval",
        server_defaults["save_interval"]
    )

    content = set_or_insert_variable(
        content,
        "tickrate",
        server_defaults["tickrate"]
    )

    content = set_or_insert_variable(
        content,
        "tags",
        server_defaults["tags"]
    )

    content = remove_unmanaged_startparameters(content)

    block = build_startparameters_block(map_type)

    content = upsert_managed_block(content, block)

    lgsm_path.write_text(content, encoding="utf-8")

    print(f"[OK] Updated LGSM config: {lgsm_path}")


def set_rust_cvar(content: str, key: str, value: str | int) -> str:

    safe_value = str(value).replace('"', '\\"')

    replacement = f'{key} "{safe_value}"'

    pattern = rf'^{re.escape(key)}\s+".*?"$'

    if re.search(pattern, content, flags=re.MULTILINE):
        return re.sub(pattern, replacement, content, flags=re.MULTILINE)

    return content.rstrip() + f"\n{replacement}\n"


def update_server_cfg(config: dict, wipe: dict) -> None:

    server_cfg_path = Path(config["paths"]["server_cfg"])

    content = server_cfg_path.read_text(encoding="utf-8")

    browser = wipe["server_browser"]

    map_data = wipe["map"]

    server_defaults = config["server_defaults"]

    content = set_rust_cvar(
        content,
        "server.description",
        browser["description"]
    )

    content = set_rust_cvar(
        content,
        "server.headerimage",
        browser["header_image"]
    )

    content = set_rust_cvar(
        content,
        "server.url",
        server_defaults["website"]
    )

    content = set_rust_cvar(
        content,
        "server.tags",
        server_defaults["tags"]
    )

    content = set_rust_cvar(
        content,
        "server.gamemode",
        server_defaults["gamemode"]
    )

    content = set_rust_cvar(
        content,
        "server.seed",
        map_data["seed"]
    )

    content = set_rust_cvar(
        content,
        "server.worldsize",
        map_data["worldsize"]
    )

    server_cfg_path.write_text(content, encoding="utf-8")

    print(f"[OK] Updated server.cfg: {server_cfg_path}")


def write_state(config: dict, wipe: dict) -> None:

    state_path = Path(config["paths"]["state_file"])

    state_path.parent.mkdir(parents=True, exist_ok=True)

    state = {
        "last_applied_wipe": wipe["name"],
        "wipe_datetime": wipe["wipe_datetime"],
        "next_wipe_datetime": wipe["next_wipe_datetime"],
        "map": wipe["map"],
        "applied_at": datetime.now(
            ZoneInfo(config["timezone"])
        ).isoformat()
    }

    state_path.write_text(
        json.dumps(state, indent=2),
        encoding="utf-8"
    )

    print(f"[OK] Wrote state: {state_path}")


def already_applied(config: dict, wipe: dict) -> bool:

    state_path = Path(config["paths"]["state_file"])

    if not state_path.exists():
        return False

    try:
        state = json.loads(
            state_path.read_text(encoding="utf-8")
        )

    except json.JSONDecodeError:
        return False

    return state.get("wipe_datetime") == wipe["wipe_datetime"]


def main() -> None:

    parser = argparse.ArgumentParser(
        description="Rust AutoWipe config rotator"
    )

    parser.add_argument(
        "--config",
        default="../config/wipe_config.json",
        help="Path to wipe_config.json"
    )

    parser.add_argument(
        "--force",
        action="store_true",
        help="Apply the active wipe profile even if already applied"
    )

    parser.add_argument(
        "--target-datetime",
        default=None,
        help="Optional ISO datetime for testing"
    )

    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show selected wipe without editing files"
    )

    args = parser.parse_args()

    config_path = Path(args.config).resolve()

    config = load_config(config_path)

    wipe = get_due_wipe(config, args.target_datetime)

    if wipe is None:
        print("[INFO] No wipe scheduled for today.")
        return

    print(f"[INFO] Wipe scheduled today:")
    print(f"[INFO] Name: {wipe['name']}")
    print(f"[INFO] Map Type: {wipe['map']['type']}")
    print(f"[INFO] Seed: {wipe['map']['seed']}")
    print(f"[INFO] World Size: {wipe['map']['worldsize']}")

    if already_applied(config, wipe) and not args.force:
        print("[INFO] This wipe has already been applied.")
        print("[INFO] Use --force to reapply.")
        return

    if args.dry_run:
        print("[DRY RUN] No files changed.")
        return

    backup_dir = Path(config["paths"]["backup_dir"])

    backup_file(
        Path(config["paths"]["lgsm_config"]),
        backup_dir
    )

    backup_file(
        Path(config["paths"]["server_cfg"]),
        backup_dir
    )

    update_lgsm_config(config, wipe)

    update_server_cfg(config, wipe)

    write_state(config, wipe)

    print("[DONE] AutoWipe config rotation complete.")


if __name__ == "__main__":
    main()