#!/usr/bin/env bash
# Linux-hosted cases (NativeAOT can't cross-compile from Windows). Usage: linux-run.sh <net10|net11> <uno|ava>
set -uo pipefail
TFM="$1"; FW="$2"; TV="$TFM.0"; LANE="$TFM-$FW-linux"
ROOT="${PKG_ROOT:-$HOME/pkgsize}"; WORK="$ROOT/work/$LANE"; OUTROOT="$ROOT/out/$LANE"; LOGS="$ROOT/logs/$LANE"; RES="$ROOT/results/$LANE.jsonl"
mkdir -p "$WORK" "$OUTROOT" "$LOGS" "$ROOT/results"
case "$FW" in
  uno) SRC=UnoApp; proj=UnoApp/UnoApp.csproj; tf="$TV-desktop"; TFS="-p:TargetFrameworks=$tf";;
  ava) SRC=AvaApp; proj=AvaApp.Desktop/AvaApp.Desktop.csproj; tf="$TV"; TFS="";;
esac
rsync -a --delete --exclude bin --exclude obj "$ROOT/src/$TFM/$SRC/" "$WORK/$SRC/"

cases() {
  echo "nativeaot|linux-x64|-c Release -p:PublishAot=true -r linux-x64"
}
cases | while IFS='|' read -r ID TARGET ARGS; do
  NAME="$ID--$TARGET"; OUT="$OUTROOT/$NAME"; LOG="$LOGS/$NAME.log"
  find "$WORK/$SRC" -type d \( -name bin -o -name obj \) -prune -exec rm -rf {} + 2>/dev/null
  rm -rf "$OUT"; START=$(date +%s)
  # shellcheck disable=SC2086
  timeout 1200 dotnet publish "$WORK/$SRC/$proj" -f "$tf" $TFS -o "$OUT" -nologo -v:m -clp:Summary $ARGS >"$LOG" 2>&1 </dev/null
  CODE=$?; SECS=$(( $(date +%s) - START ))
  STATUS=fail; PKGB=0; INST=0; PDB=0; ERR=""; FILES=0
  WL=$(grep -E "warning [A-Z]+[0-9]+" "$LOG" | sed -E 's/ *\[[^]]+\] *$//; s/^ *//' | sort -u)
  NW=$(printf '%s' "$WL" | grep -c . || true)
  ILW=$(printf '%s\n' "$WL" | grep -oE "warning IL[0-9]+" | awk '{print $2}' | sort | uniq -c | awk '{printf "%sx%s ", $2, $1}')
  WC=$(printf '%s\n' "$WL" | grep -oE "warning [A-Z]+[0-9]+" | awk '{print $2}' | sort | uniq -c | sort -rn | head -8 | awk '{printf "%sx%s ", $2, $1}')
  if [ $CODE -eq 0 ]; then
    PDB=$(find "$OUT" -type f \( -name '*.pdb' -o -name '*.dbg' \) -printf '%s\n' | awk '{s+=$1} END {print s+0}')
    find "$OUT" -type f \( -name '*.pdb' -o -name '*.dbg' \) -delete
    T="$(mktemp -d)/p.tar.gz"; tar -czf "$T" -C "$OUT" .; PKGB=$(stat -c%s "$T"); rm -f "$T"
    INST=$(find "$OUT" -type f -printf '%s\n' | awk '{s+=$1} END {print s+0}'); FILES=$(find "$OUT" -type f | wc -l)
    STATUS=ok
    find "$OUT" -type f -printf '%s %p\n' | sort -rn | head -25 > "$LOGS/$NAME.topfiles.txt"
  else
    [ $CODE -eq 124 ] && STATUS=timeout
    ERR=$(grep -E "error [A-Z]+[0-9]+|error:" "$LOG" | head -3 | sed 's/^ *//' | tr '\n' '|' | tr -d '"\\' | cut -c1-600)
    [ -z "$ERR" ] && ERR=$(tail -5 "$LOG" | tr '\n' '|' | tr -d '"\\' | cut -c1-600)
  fi
  printf '{"tfm":"%s","fw":"%s","group":"linux","kind":"desktop","target":"%s","config":"%s","args":"%s","seconds":%s,"warnings":%s,"ilWarnings":"%s","warningCodes":"%s","status":"%s","package":"tar.gz","packageBytes":%s,"installBytes":%s,"fileCount":%s,"pdbBytes":%s,"host":"linux","error":"%s"}\n' \
    "$TFM" "$FW" "$TARGET" "$ID" "$ARGS" "$SECS" "${NW:-0}" "${ILW% }" "${WC% }" "$STATUS" "$PKGB" "$INST" "$FILES" "$PDB" "$ERR" >> "$RES"
  printf '%-7s %-30s %4ss %s\n' "$STATUS" "$NAME" "$SECS" "$( [ "$STATUS" = ok ] && echo "$((PKGB/1024)) KB" || echo "$ERR" )"
done
echo "LANE DONE $LANE"
