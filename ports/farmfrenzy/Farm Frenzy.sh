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

PORTMASTER_LIBS="$controlfolder/libs"
SQUASH_IMAGE="$PORTMASTER_LIBS/wine-runtime.squashfs"
BOX64_IMAGE="$PORTMASTER_LIBS/box64-runtime.squashfs"
MNT_BOX64="/tmp/farmfrenzy_box64"
MNT_RUNTIME="/tmp/farmfrenzy_runtime"
WINEPREFIX="/tmp/farmfrenzy/.wine"

if [ ! -f "$SQUASH_IMAGE" ] || [ ! -f "$BOX64_IMAGE" ]; then
    echo "[ERROR]: SquashFS images not found at $SQUASH_IMAGE or $BOX64_IMAGE"
    exit 1
fi

echo "[LAUNCHER]: Mounting Wine runtime SquashFS..."
mkdir -p "$MNT_RUNTIME"
mount -t squashfs -o loop "$SQUASH_IMAGE" "$MNT_RUNTIME"

echo "[LAUNCHER]: Mounting Box64 runtime SquashFS..."
mkdir -p "$MNT_BOX64"
mount -t squashfs -o loop "$BOX64_IMAGE" "$MNT_BOX64"

PATH="$MNT_RUNTIME/bin:$MNT_BOX64/bin:$PATH"
LD_LIBRARY_PATH="$MNT_RUNTIME/lib:$MNT_BOX64/lib:$LD_LIBRARY_PATH"

echo "[LAUNCHER]: Extracting main wineprefix to RAM..."
mkdir -p "$WINEPREFIX"
tar -xf "$MNT_RUNTIME/wineprefix.tar.xz" -C "$WINEPREFIX" --strip-components=1

if [ -f "$GAMEDIR/bottle.json" ]; then
    RUNNER=$(grep -o '"runner"[[:space:]]*:[[:space:]]*"[^"]*' "$GAMEDIR/bottle.json" | sed 's/"runner"[[:space:]]*:[[:space:]]*"//')
    WINEARCH=$(grep -o '"winearch"[[:space:]]*:[[:space:]]*"[^"]*' "$GAMEDIR/bottle.json" | sed 's/"winearch"[[:space:]]*:[[:space:]]*"//')
fi

RUNNER=${RUNNER:-"default"}
WINEARCH=${WINEARCH:-"win64"}

case "$RUNNER" in
    default)
        WINE="$MNT_RUNTIME/bin/wine"
        ;;
    *)
        echo "Error: Unknown runner '$RUNNER' specified in bottle.json"
        umount -f "$MNT_RUNTIME" 2>/dev/null
        umount -f "$MNT_BOX64" 2>/dev/null
        rm -rf "$MNT_RUNTIME" "$MNT_BOX64" "$WINEPREFIX"
        exit 1
        ;;
esac

export LD_LIBRARY_PATH="$MNT_RUNTIME/lib:$LD_LIBRARY_PATH"
export PATH="$MNT_RUNTIME/bin:$PATH"

BOX="$MNT_BOX64/bin/box64"

echo "[LAUNCHER]: Using runner '$RUNNER' with WINEPREFIX='$WINEPREFIX' BOX='$BOX'"

if [ -f "$GAMEDIR/bottle.json" ]; then
    while IFS= read -r line; do
        k=$(echo "$line" | cut -d':' -f1 | tr -d '"[:space:]')
        v=$(echo "$line" | cut -d':' -f2- | tr -d '"[:space:],')
        if [ -n "$k" ] && [ "$k" != "env" ]; then
            export "$k=$v"
        fi
    done < <(grep -A 5 '"env"' "$GAMEDIR/bottle.json" | grep -v '"env"' | grep -v '}')
fi

CONFIGDIRS=$(grep -o '"configdir"[[:space:]]*:[[:space:]]*\[[^]]*\]' "$GAMEDIR/bottle.json" | sed -e 's/.*\[//' -e 's/\].*//' -e 's/"//g' -e 's/,/ /g')
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
