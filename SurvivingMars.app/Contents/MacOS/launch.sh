#!/bin/bash
# SurvivingMars wrapper launcher - GPTK 3.0-3 + D3DMetal
# Spec: ~/Documents/SurvivingMars-Wrapper/SPEC-PLAN.txt
# Usage: launch.sh [--debug] [--settings] [--no-mouse-fix]
#   --debug     verbose Wine/D3D output to stderr (run from Terminal to see it)
#   --settings  open settings UI (game folder), then exit
#   --no-mouse-fix  skip the cursor-hitbox/focus registry fix for this run
#
# Clicks miss in fullscreen? Two known Wine causes, both handled here:
#   1. Cursor hitbox vertically offset (fullscreen scaling mismatch):
#      fastest in-game fix is Alt+Enter (toggle Windowed) or
#      Options > Video > Display Mode > Windowed/Borderless. The registry
#      fix below (RetinaMode=N) removes the macOS HiDPI scaling offset.
#   2. Zero highlights/clicks anywhere (focus loss): the registry fix
#      enables CaptureDisplaysForFullscreen + DirectInput MouseWarpOverride,
#      the GPTK/winemac equivalent of winecfg's "Automatically capture the
#      mouse in full-screen windows". No Proton/Gamescope on macOS.
#
# Note: this launcher intentionally keeps no log files. Normal runs are
# silent (Wine output goes to /dev/null so it cannot fill the unified log).
# Use --debug from Terminal when diagnosing a failure.
set -u

WINE_BIN="/Applications/Game Porting Toolkit.app/Contents/Resources/wine/bin/wine64"
GAME_DIR="/Users/ajilaksono/Games/Surviving Mars - Relaunched/Surviving Mars - Relaunched"
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
MOUSE_FIX_OPT=1
USE_DEBUG_EXE=0
for a in "$@"; do
  [ "$a" = "--debug" ] && DEBUG=1
  [ "$a" = "--settings" ] && SETTINGS=1
  [ "$a" = "--no-mouse-fix" ] && MOUSE_FIX_OPT=0
  [ "$a" = "--mars-debug" ] && USE_DEBUG_EXE=1
done
# --mars-debug runs MarsDebug.exe (debug build: asserts on, Lua console on
# Enter) instead of Mars.exe. Used for console cheats like force-enabling
# LOAD GAME or LoadGame("name.savegame.sav") by hand.
[ "$USE_DEBUG_EXE" -eq 1 ] && GAME_EXE="$GAME_DIR/MarsDebug.exe"
# wrapper.conf overrides (only if set there; defaults kept otherwise):
#   MOUSE_FIX=0            disable the registry mouse/focus fix entirely
#   RETINA_MODE=Y|N        winemac RetinaMode (default N: no HiDPI scaling,
#                          fixes vertical cursor-hitbox offset)
#   CAPTURE_FULLSCREEN=Y|N winemac CaptureDisplaysForFullscreen (default Y:
#                          keeps mouse focus grabbed in fullscreen)
#   MOUSE_WARP=force|disable|enable  DirectInput MouseWarpOverride (default force)

mkdir -p "$SUPPORT"

save_conf() {
  {
    echo "# wrapper.conf - managed by launch.sh --settings, edit by hand if needed"
    echo "GAME_DIR=\"$GAME_DIR\""
    echo "WINE_BIN=\"$WINE_BIN\""
    echo "# MOUSE_FIX=1  (set 0 to disable cursor-hitbox/focus registry fix)"
    echo "# RETINA_MODE=N  (Y re-enables HiDPI scaling; N fixes click offset)"
    echo "# CAPTURE_FULLSCREEN=Y  (N disables fullscreen display capture)"
    echo "# MOUSE_WARP=force  (DirectInput MouseWarpOverride)"
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

# Cursor-hitbox / focus fix (idempotent, ~1 s). Replaces the manual winecfg
# steps: winemac has no "virtual desktop" checkbox; these registry keys are
# the equivalent. Never fatal: a failed reg write only warns in --debug.
apply_mouse_fix() {
  [ "${MOUSE_FIX:-1}" -eq 1 ] || { [ "$DEBUG" -eq 1 ] && echo "mouse fix disabled (MOUSE_FIX=0)" >&2; return 0; }
  [ "$MOUSE_FIX_OPT" -eq 1 ] || { [ "$DEBUG" -eq 1 ] && echo "mouse fix skipped (--no-mouse-fix)" >&2; return 0; }
  local retina="${RETINA_MODE:-N}" cap="${CAPTURE_FULLSCREEN:-Y}" warp="${MOUSE_WARP:-force}"
  local out="/dev/null"
  [ "$DEBUG" -eq 1 ] && out="/dev/stderr"
  timeout 30 "$WINE_BIN" reg add "HKCU\\Software\\Wine\\Mac Driver" /v RetinaMode /d "$retina" /f >"$out" 2>&1 || \
    { [ "$DEBUG" -eq 1 ] && echo "warn: RetinaMode reg write failed" >&2; }
  timeout 30 "$WINE_BIN" reg add "HKCU\\Software\\Wine\\Mac Driver" /v CaptureDisplaysForFullscreen /d "$cap" /f >"$out" 2>&1 || \
    { [ "$DEBUG" -eq 1 ] && echo "warn: CaptureDisplaysForFullscreen reg write failed" >&2; }
  timeout 30 "$WINE_BIN" reg add "HKCU\\Software\\Wine\\DirectInput" /v MouseWarpOverride /d "$warp" /f >"$out" 2>&1 || \
    { [ "$DEBUG" -eq 1 ] && echo "warn: MouseWarpOverride reg write failed" >&2; }
  [ "$DEBUG" -eq 1 ] && echo "mouse fix applied: RetinaMode=$retina CaptureDisplaysForFullscreen=$cap MouseWarpOverride=$warp" >&2
}
apply_mouse_fix

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

# real Paradox saves live here (per Wine user), NOT in the RUNE stub above:
#   <prefix>/drive_c/users/crossover/Saved Games/Surviving Mars Relaunched
# Pinned exact path on purpose: never fuzzy-find this name, because Temp/
# and AppData/Roaming/ contain same-named dirs that must NOT be touched.
REAL_DST="$SUPPORT/savegames"
SAVEDIR="$PREFIX/drive_c/users/crossover/Saved Games/Surviving Mars Relaunched"
# SAVES_REALDIR=1 (in wrapper.conf) keeps SAVEDIR as a real dir instead of a
# symlink — diagnostic mode for testing whether the game lists saves through
# a symlink. With a real dir, sync prefix -> SUPPORT after a successful run.
if [ "${SAVES_REALDIR:-0}" = 1 ]; then
  mkdir -p "$SAVEDIR" "$REAL_DST"
  [ "$DEBUG" -eq 1 ] && echo "saves real-dir mode: $SAVEDIR (no symlink)" >&2
else
  mkdir -p "$REAL_DST"
if [ ! -L "$SAVEDIR" ]; then
  mkdir -p "$(dirname "$SAVEDIR")" "$REAL_DST"
  if [ -d "$SAVEDIR" ]; then
    cp -R "$SAVEDIR/." "$REAL_DST/" 2>/dev/null || true
    rm -rf "$SAVEDIR"
  fi
  ln -sfn "$REAL_DST" "$SAVEDIR"
  [ "$DEBUG" -eq 1 ] && echo "savegames linked: $SAVEDIR -> $REAL_DST" >&2
fi
fi

# the game requires its own folder as working directory (else exit 255)
cd "$GAME_DIR" || fail "cannot cd to game dir: $GAME_DIR" 13

[ "$DEBUG" -eq 1 ] && echo "launching: $GAME_EXE --disableMods --noWorkshop" >&2
if [ "$DEBUG" -eq 1 ]; then
  "$WINE_BIN" "$GAME_EXE" --disableMods --noWorkshop
  CODE=$?
else
  "$WINE_BIN" "$GAME_EXE" --disableMods --noWorkshop >/dev/null 2>&1
  CODE=$?
fi

if [ "$CODE" -ne 0 ]; then
  fail "game exited with code $CODE (run with --debug from Terminal for details)" "$CODE"
fi
[ "$DEBUG" -eq 1 ] && echo "clean exit" >&2
