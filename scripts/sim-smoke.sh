#!/usr/bin/env bash
# Launch-smoke test on the iOS simulator: does a size-reduced Uno build still start and render its page?
# Usage: sim-smoke.sh <net10|net11> <name> [msbuild args...]   (builds Release for the simulator, launches, screenshots)
set -uo pipefail
TFM="$1"; NAME="$2"; shift 2
ROOT="${PKG_ROOT:-$HOME/pkgsize}"; WORK="$ROOT/work/sim-$NAME"; LOGS="$ROOT/logs/sim"; mkdir -p "$WORK" "$LOGS"
rsync -a --delete --exclude bin --exclude obj "$ROOT/src/$TFM/UnoApp/" "$WORK/UnoApp/"
printf '<Project>\n  <Import Project="%s/scripts/diag-late.targets" />\n</Project>\n' "$ROOT" > "$WORK/UnoApp/Directory.Build.targets"
ARCH=arm64; [ "$(uname -m)" = x86_64 ] && ARCH=x64
START=$(date +%s)
# shellcheck disable=SC2068
dotnet build "$WORK/UnoApp/UnoApp/UnoApp.csproj" -c Release -f "$TFM.0-ios" -r "iossimulator-$ARCH" -p:TargetFrameworks="$TFM.0-ios" \
  -p:UnoEnableHotReload=false -p:CustomAfterMicrosoftCommonTargets="$ROOT/scripts/diag.targets" -nologo -v:m -clp:Summary $@ > "$LOGS/$NAME.build.log" 2>&1
CODE=$?; echo "build exit=$CODE secs=$(( $(date +%s) - START ))" | tee "$LOGS/$NAME.result.txt"
[ $CODE -ne 0 ] && { tail -20 "$LOGS/$NAME.build.log"; exit 0; }
APP=$(find "$WORK" -name "*.app" -type d -path "*iossimulator*" -not -path "*/obj/*" -not -path "*.app/*" | head -1)
echo "app=$APP bytes=$(find "$APP" -type f -exec stat -f%z {} + | awk '{s+=$1} END {print s}')" | tee -a "$LOGS/$NAME.result.txt"
ls "$APP/Frameworks" >> "$LOGS/$NAME.result.txt" 2>&1
BID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")
UDID=$(xcrun simctl list devices available -j | python3 -c "
import json,sys
d=json.load(sys.stdin)['devices']
c=[x for k,v in sorted(d.items()) if 'iOS' in k for x in v if x['name'].startswith('iPhone')]
print(c[-1]['udid'] if c else '')")
[ -z "$UDID" ] && { echo "no simulator device" | tee -a "$LOGS/$NAME.result.txt"; xcrun simctl list devices available | head -30; exit 0; }
xcrun simctl boot "$UDID" 2>/dev/null; xcrun simctl bootstatus "$UDID" -b > /dev/null 2>&1
xcrun simctl terminate "$UDID" "$BID" 2>/dev/null; xcrun simctl uninstall "$UDID" "$BID" 2>/dev/null
xcrun simctl install "$UDID" "$APP" 2>&1 | tee -a "$LOGS/$NAME.result.txt"
T0=$(python3 -c 'import time; print(time.time())')
xcrun simctl launch --stdout="$LOGS/$NAME.stdout.txt" --stderr="$LOGS/$NAME.stderr.txt" "$UDID" "$BID" 2>&1 | tee -a "$LOGS/$NAME.result.txt"
for s in 4 10 25; do
  sleep $(( s == 4 ? 4 : s == 10 ? 6 : 15 ))
  xcrun simctl io "$UDID" screenshot --type=png "$LOGS/$NAME.t$s.png" >> "$LOGS/$NAME.result.txt" 2>&1
  if xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | grep -q "$BID"; then echo "t+${s}s alive" | tee -a "$LOGS/$NAME.result.txt"; else echo "t+${s}s NOT RUNNING" | tee -a "$LOGS/$NAME.result.txt"; fi
done
xcrun simctl terminate "$UDID" "$BID" 2>/dev/null
# crash reports, if any
find "$HOME/Library/Logs/DiagnosticReports" -name "UnoApp*" -newermt "@${T0%.*}" 2>/dev/null | head -3 | while read -r c; do cp "$c" "$LOGS/$NAME.crash-$(basename "$c")"; echo "crash report: $c" | tee -a "$LOGS/$NAME.result.txt"; done
tail -c 3000 "$LOGS/$NAME.stderr.txt" 2>/dev/null | tail -15
