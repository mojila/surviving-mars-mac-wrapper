#!/bin/bash
# SurvivingMars wrapper launcher - GPTK 3.0-3 + D3DMetal
# Spec: ~/Documents/SurvivingMars-Wrapper/SPEC-PLAN.txt
# Usage: launch.sh [--debug] [--settings]
#   --debug     verbose Wine/D3D output to stderr (run from Terminal to see it)
#   --settings  open settings UI (game folder), then exit
#
# Note: this launcher intentionally keeps no log files. Normal runs are
# silent (Wine output goes to /dev/null so it cannot fill the unified log).
# Use --debug from Terminal when diagnosing a failure.
set -u

WINE_BIN="/Applications/Game Porting Toolkit.app/Contents/Resources/wine/bin/wine64"
GAME_DIR="/Volumes/External/Surviving Mars - Relaunched [FitGirl Repack]/Surviving Mars - Relaunched"
SUPPORT="$HOME/Library/Application Support/SurvivingMars"
PREFIX="$SUPPORT/prefix"
SAVES="$SUPPORT/saves"
CONF="$SUPPORT/wrapper.conf"

# user overrides (GAME_DIR, WINE_BIN) allowed
if [ -f "$CONF" ]; then
  # shellcheck disable=SC1090
  . "$CONF"
fi
GAME_EXE="$GAME_DIR/Mars.exe"

DEBUG=0
SETTINGS=0
for a in "$@"; do
  [ "$a" = "--debug" ] && DEBUG=1
  [ "$a" = "--settings" ] && SETTINGS=1
done

mkdir -p "$SUPPORT"

save_conf() {
  {
    echo "# wrapper.conf - managed by launch.sh --settings, edit by hand if needed"
    echo "GAME_DIR=\"$GAME_DIR\""
    echo "WINE_BIN=\"$WINE_BIN\""
  } > "$CONF"
}

pick_folder() { # $1 prompt, $2 current -> prints path or empty
  osascript -e "try
    set d to choose folder with prompt \"$1\" default location (POSIX file \"$2\" as alias)
    return POSIX path of d
  on error
    return \"\"
  end try" 2>/dev/null
}

settings_ui() {
  while true; do
    CHOICE=$(osascript -e "set r to button returned of (display dialog \"Surviving Mars wrapper settings\" & return & return & \"Game folder:\" & return & \"$GAME_DIR\" buttons {\"Done\", \"Game folder…\"} default button \"Done\")" 2>/dev/null) || return 0
    case "$CHOICE" in
      "Game folder"*)
        NEWDIR=$(pick_folder "Choose the folder containing Mars.exe" "$GAME_DIR")
        if [ -n "$NEWDIR" ]; then
          GAME_DIR="${NEWDIR%/}"
          GAME_EXE="$GAME_DIR/Mars.exe"
          if [ ! -f "$GAME_EXE" ]; then
            osascript -e "display alert \"No Mars.exe in that folder\" message \"$GAME_DIR\"" 2>/dev/null || true
          fi
          save_conf
        fi
        ;;
      *) return 0 ;;
    esac
  done
}

[ "$SETTINGS" -eq 1 ] && { settings_ui; exit 0; }

# game folder missing -> offer to locate it instead of dying
if [ ! -f "$GAME_EXE" ]; then
  NEWDIR=$(pick_folder "Mars.exe not found. Choose the game folder (or Cancel to quit)" "$HOME")
  if [ -n "$NEWDIR" ]; then
    GAME_DIR="${NEWDIR%/}"
    GAME_EXE="$GAME_DIR/Mars.exe"
    save_conf
  fi
fi

mkdir -p "$SAVES"

export WINEPREFIX="$PREFIX"
export WINEDLLOVERRIDES="steam_api64=n,b"
if [ "$DEBUG" -eq 1 ]; then
  export WINEDEBUG="+err,+seh"
  export MTL_HUD_ENABLED=1
  unset MTL_DEBUG_LAYER || true
else
  # silent: no Wine channels, Metal validation off, output discarded below
  export WINEDEBUG="-all"
  export MTL_HUD_ENABLED=0
  unset MTL_DEBUG_LAYER || true
fi

fail() {
  echo "ERROR: $1 (exit $2)" >&2
  osascript -e "display dialog \"$1\" buttons {\"OK\"} default button \"OK\" with title \"Surviving Mars wrapper\"" 2>/dev/null || true
  exit "$2"
}

[ -x "$WINE_BIN" ] || fail "wine binary not found: $WINE_BIN" 11
[ -f "$GAME_EXE" ] || fail "game not found (is External mounted?): $GAME_EXE" 10

if [ ! -f "$PREFIX/system.reg" ]; then
  [ "$DEBUG" -eq 1 ] && echo "prefix missing, booting..." >&2
  if [ "$DEBUG" -eq 1 ]; then
    timeout 300 "$WINE_BIN" wineboot -u || fail "wineboot failed (run with --debug from Terminal for details)" 12
  else
    timeout 300 "$WINE_BIN" wineboot -u >/dev/null 2>&1 || fail "wineboot failed (run with --debug from Terminal for details)" 12
  fi
fi

# saves symlink: prefix RUNE dir -> $SAVES (idempotent)
RUNE_DIR="$PREFIX/drive_c/users/Public/Documents/Steam/RUNE/3215050"
if [ ! -L "$RUNE_DIR" ]; then
  mkdir -p "$(dirname "$RUNE_DIR")" "$SAVES"
  if [ ! -e "$RUNE_DIR" ]; then
    ln -sfn "$SAVES" "$RUNE_DIR"
  else
    # game already created real dir: merge into SAVES once
    cp -R "$RUNE_DIR/." "$SAVES/" 2>/dev/null || true
    rm -rf "$RUNE_DIR"
    ln -sfn "$SAVES" "$RUNE_DIR"
  fi
  [ "$DEBUG" -eq 1 ] && echo "saves linked: $RUNE_DIR -> $SAVES" >&2
fi

# the game requires its own folder as working directory (else exit 255)
cd "$GAME_DIR" || fail "cannot cd to game dir: $GAME_DIR" 13

[ "$DEBUG" -eq 1 ] && echo "launching: $GAME_EXE" >&2
if [ "$DEBUG" -eq 1 ]; then
  "$WINE_BIN" "$GAME_EXE"
  CODE=$?
else
  "$WINE_BIN" "$GAME_EXE" >/dev/null 2>&1
  CODE=$?
fi

if [ "$CODE" -ne 0 ]; then
  fail "game exited with code $CODE (run with --debug from Terminal for details)" "$CODE"
fi
[ "$DEBUG" -eq 1 ] && echo "clean exit" >&2
