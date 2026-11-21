Surviving Mars Relaunched - macOS Wrapper (GPTK/D3DMetal)

What this is: a thin macOS .app wrapper that launches the Windows build of
Surviving Mars Relaunched on Apple Silicon via the Game Porting Toolkit
(D3DMetal), with per-launch logs for diagnosis.

What this is NOT: this repo contains NO game files, NO installer, NO crack,
NO emulation keys. You must provide your own legally obtained copy of the game.
Nothing here bypasses copy protection.

Requirements
  - Apple Silicon Mac, macOS 14+, Rosetta installed
  - Game Porting Toolkit 3.x in /Applications
  - Your own copy of the game (Windows x86-64 build)

Layout
  SurvivingMars.app/Contents/MacOS/launch.sh  launcher (absolute GPTK wine path, preflight, log rotation)
  SurvivingMars.app/Contents/Info.plist        bundle metadata (Retina-capable)
  wrapper.conf.example                           copy to ~/Library/Application Support/SurvivingMars/wrapper.conf to override paths
  SPEC-PLAN.txt                                  spec and plan
  TEST-RESULTS.txt                               first-run results

Install
  1. cp wrapper.conf.example ~/Library/Application\ Support/SurvivingMars/wrapper.conf
  2. Edit GAME_DIR in wrapper.conf to point at the folder containing Mars.exe
  3. Copy or symlink SurvivingMars.app to /Applications (or run in place)

Run
  Normal:  SurvivingMars.app (double-click) or Contents/MacOS/launch.sh
  Verbose: Contents/MacOS/launch.sh --debug

Logs
  ~/Library/Logs/SurvivingMars/launch-YYYYMMDD-HHMMSS.log (+ latest.log symlink).
  Keep last 10, older ones gzipped. A failing run keeps its log and shows the path.

Saves
  Launcher symlinks the emulator save dir to ~/Library/Application Support/SurvivingMars/saves
  so saves survive prefix rebuilds.

Legal
  Wrapper scripts and docs only (MIT). Do not commit game binaries, DLC packs,
  videos, DLLs, steam emu configs, or keys. See .gitignore, which blocks them.
