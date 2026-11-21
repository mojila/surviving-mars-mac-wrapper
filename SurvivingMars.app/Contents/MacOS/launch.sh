#!/bin/bash
# SurvivingMars wrapper launcher - GPTK 3.0-3 + D3DMetal
# Spec: ~/Documents/SurvivingMars-Wrapper/SPEC-PLAN.txt
set -u

DEBUG=0
if [ "${1:-}" = "--debug" ]; then DEBUG=1; fi

WINE_BIN="/Applications/Game Porting Toolkit.app/Contents/Resources/wine/bin/wine64"
GAME_DIR="/Volumes/External/Surviving Mars - Relaunched [FitGirl Repack]/Surviving Mars - Relaunched"
GAME_EXE="$GAME_DIR/Mars.exe"
SUPPORT="$HOME/Library/Application Support/SurvivingMars"
PREFIX="$SUPPORT/prefix"
SAVES="$SUPPORT/saves"
LOGDIR="$HOME/Library/Logs/SurvivingMars"
CONF="$SUPPORT/wrapper.conf"

# user overrides (GAME_DIR, WINE_BIN) allowed
if [ -f "$CONF" ]; then
  # shellcheck disable=SC1090
  . "$CONF"
  GAME_EXE="$GAME_DIR/Mars.exe"
fi

mkdir -p "$SUPPORT" "$LOGDIR" "$SAVES"

STAMP=$(date +%Y%m%d-%H%M%S)
LOG="$LOGDIR/launch-$STAMP.log"
ln -sfn "$LOG" "$LOGDIR/latest.log"

# rotate: keep last 10, gzip older
ls -t "$LOGDIR"/launch-*.log 2>/dev/null | tail -n +11 | while read -r old; do
  gzip -f "$old" 2>/dev/null || true
done

loghead() {
  {
    echo "=== SurvivingMars wrapper log $STAMP ==="
    date
    sw_vers 2>&1 | head -n 4
    echo "chip: $(uname -m) $(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)"
    system_profiler SPDisplaysDataType 2>/dev/null | grep -i -m1 "Metal Support" || true
    echo "gptk: $(mdls -raw -name kMDItemVersion '/Applications/Game Porting Toolkit.app' 2>/dev/null || echo unknown)"
    echo "wine_bin: $WINE_BIN"
    ls -la "$WINE_BIN" 2>&1 | head -n 2
    echo "game_exe: $GAME_EXE"
    ls -la "$GAME_EXE" 2>&1 | head -n 2
    echo "prefix: $PREFIX"
    df -h "$HOME" 2>&1 | tail -n 1
    echo "debug=$DEBUG"
    echo "WINEDEBUG=${WINEDEBUG:-unset} MTL_HUD_ENABLED=${MTL_HUD_ENABLED:-unset} MTL_DEBUG_LAYER=${MTL_DEBUG_LAYER:-unset}"
    echo "args: $*"
    echo "---"
  } >> "$LOG" 2>&1
}

fail() {
  echo "ERROR: $1 (exit $2)" | tee -a "$LOG" >&2
  osascript -e "display alert \"Surviving Mars wrapper\" message \"$1 -- log: $LOG\"" 2>/dev/null || true
  exit "$2"
}

loghead "$@"

[ -x "$WINE_BIN" ] || fail "wine binary not found: $WINE_BIN" 11
[ -f "$GAME_EXE" ] || fail "game not found (is External mounted?): $GAME_EXE" 10

export WINEPREFIX="$PREFIX"
export WINEDLLOVERRIDES="steam_api64=n,b"
if [ "$DEBUG" -eq 1 ]; then
  export WINEDEBUG="+timestamp,+pid,+seh,+err,+loaddll,+d3d12"
  export MTL_DEBUG_LAYER=1
  export MTL_HUD_ENABLED=1
else
  export WINEDEBUG="+seh,+err,+loaddll"
  export MTL_HUD_ENABLED=0
  unset MTL_DEBUG_LAYER || true
fi

if [ ! -f "$PREFIX/system.reg" ]; then
  echo "prefix missing, booting..." | tee -a "$LOG"
  timeout 300 "$WINE_BIN" wineboot -u >> "$LOG" 2>&1 || fail "wineboot failed, see log" 12
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
  echo "saves linked: $RUNE_DIR -> $SAVES" >> "$LOG"
fi

echo "launching: $GAME_EXE" | tee -a "$LOG"
"$WINE_BIN" "$GAME_EXE" >> "$LOG" 2>&1 &
WINEPID=$!
wait $WINEPID
CODE=$?

{
  echo "---"
  echo "exit code: $CODE"
  echo "last errors:"
  grep -a -m20 -E "err:|fixme:d3d12|Failed|failed" "$LOG" | tail -n 20 || true
  echo "tail:"
  tail -n 50 "$LOG"
} >> "$LOG" 2>&1

if [ "$CODE" -ne 0 ]; then
  fail "game exited with code $CODE" "$CODE"
fi
echo "clean exit" | tee -a "$LOG"
