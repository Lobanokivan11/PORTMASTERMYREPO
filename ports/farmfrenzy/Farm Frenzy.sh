#!/bin/bash

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source $controlfolder/control.txt
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls

GAMEDIR="$(dirname "$0")/farmfrenzy"
EXEC="$GAMEDIR/data/farm.exe"
BASE=$(basename "$EXEC")
SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"
LOG=${LOG:-"$GAMEDIR/log.txt"}

cd "$GAMEDIR/data"
> "$LOG" && exec > >(tee "$LOG") 2>&1

SQUASH_IMAGE="wine-runtime.squashfs"
MNT_RUNTIME="/tmp/farmfrenzy_runtime"
WINEPREFIX="/tmp/farmfrenzy/.wine"
BOX64_IMAGE="box64-runtime.squashfs"

if [ ! -f "$SQUASH_IMAGE" ] || [ ! -f "$BOX64_IMAGE" ]; then
    echo "[ERROR]: SquashFS images not found at $SQUASH_IMAGE or $BOX64_IMAGE"
    exit 1
fi

echo "[LAUNCHER]: Mounting Wine runtime SquashFS..."
mkdir -p "$MNT_RUNTIME"
mount -t squashfs -o loop "$SQUASH_IMAGE" "$MNT_RUNTIME"

echo "[LAUNCHER]: Extracting main wineprefix to RAM..."
mkdir -p "$WINEPREFIX"
tar -xf "$MNT_RUNTIME/wineprefix.tar.xz" -C "$WINEPREFIX" --strip-components=1

RUNNER=$(jq -r '.runner // "default"' "$GAMEDIR/bottle.json")
WINEARCH=$(jq -r '.env.WINEARCH // "win64"' "$GAMEDIR/bottle.json")

case "$RUNNER" in
    default)
        WINE="$MNT_RUNTIME/bin/wine"
        ;;
    *)
        echo "Error: Unknown runner '$RUNNER' specified in bottle.json"
        umount -f "$MNT_RUNTIME" && rm -rf "$MNT_RUNTIME" "$WINEPREFIX"
        exit 1
        ;;
esac

export LD_LIBRARY_PATH="$MNT_RUNTIME/lib:$LD_LIBRARY_PATH"
export PATH="$MNT_RUNTIME/bin:$PATH"

BOX="$MNT_BOX64/bin/box64"

echo "[LAUNCHER]: Using runner '$RUNNER' with WINEPREFIX='$WINEPREFIX' BOX='$BOX'"

if command -v jq >/dev/null; then
    while IFS="=" read -r k v; do
        export "$k=$v"
    done < <(jq -r '.env | to_entries | .[] | "\(.key)=\(.value)"' "$GAMEDIR/bottle.json")
else
    echo "Error: jq not found"
    umount -f "$MNT_RUNTIME" && rm -rf "$MNT_RUNTIME" "$WINEPREFIX"
    exit 1
fi

CONFIGDIRS=$(jq -r '.configdir[]? // empty' "$GAMEDIR/bottle.json")
if [ -n "$CONFIGDIRS" ] && [ -n "$WINEPREFIX" ]; then
    mkdir -p "$GAMEDIR/config"

    while IFS= read -r dir; do
        LOCAL="$GAMEDIR/config"
        WINEDEST="$WINEPREFIX/$dir"
        mkdir -p "$LOCAL"
        rm -rf "$WINEDEST" && mkdir -p "$(dirname "$WINEDEST")"
        if [ ! -e "$WINEDEST" ]; then
            ln -s "$LOCAL" "$WINEDEST"
            echo "[CONFIG]: Binding $LOCAL -> $WINEDEST"
        fi
    done <<< "$CONFIGDIRS"
fi

export TEXTINPUTPRESET="NAME"
export TEXTINPUTINTERACTIVE="Y"
export TEXTINPUTNOAUTOCAPITALS="Y"
export TEXTINPUTADDEXTRASYMBOLS="Y"

$GPTOKEYB "$BASE" -c "$GAMEDIR/farm.gptk" &
$BOX $WINE "$EXEC"

echo "[LAUNCHER]: Shutting down Wine and cleaning RAM..."

"$MNT_RUNTIME/bin/wineserver" -k
sleep 1
umount -f "$MNT_RUNTIME" 2>/dev/null
umount -f "$MNT_BOX64" 2>/dev/null
rm -rf "$MNT_RUNTIME"
rm -rf "$MNT_BOX64"
rm -rf "/tmp/farmfrenzy"

pm_finish
