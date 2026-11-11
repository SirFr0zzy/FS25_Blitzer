#!/bin/sh
# Kopiert den Mod als Ordner in den FS25-Mods-Ordner (Proton).
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"
DST="$HOME/.local/share/Steam/steamapps/compatdata/2300320/pfx/drive_c/users/steamuser/Documents/My Games/FarmingSimulator2025/mods/FS25_SpeedLaserGun"
mkdir -p "$DST"
rsync -a --delete --exclude blender --exclude '.git' --exclude '*.iml' --exclude deploy.sh --exclude '.idea' "$SRC/" "$DST/"
echo "Deployed nach: $DST"
