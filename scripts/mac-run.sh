#!/usr/bin/env bash
# Apple side of the package-size matrix (iOS, Mac Catalyst, macOS desktop). bash 3.2 compatible.
# Usage: mac-run.sh <net10|net11> <uno|maui|ava> <ios|maccatalyst|macos> [case-id ...]
# Expects: dotnet on PATH = matching SDK, DEVELOPER_DIR set, sources in $PKG_ROOT/src/<tfm>/.
set -uo pipefail
TFM="$1"; FW="$2"; GROUP="$3"; shift 3; ONLY="${*:-}"
TV="$TFM.0"; LANE="$TFM-$FW-$GROUP"
ROOT="${PKG_ROOT:-$HOME/pkgsize}"; WORK="$ROOT/work/$LANE"; OUTROOT="$ROOT/out/$LANE"; LOGS="$ROOT/logs/$LANE"; RES="$ROOT/results/$LANE.jsonl"
mkdir -p "$WORK" "$OUTROOT" "$LOGS" "$ROOT/results"
case "$FW" in uno) SRC=UnoApp;; maui) SRC=MauiApp1;; ava) SRC=AvaApp;; esac
rsync -a --delete --exclude bin --exclude obj "$ROOT/src/$TFM/$SRC/" "$WORK/$SRC/"

proj=""; tf=""
case "$FW:$GROUP" in
  uno:ios)          proj=UnoApp/UnoApp.csproj;           tf="$TV-ios";;
  uno:macos)        proj=UnoApp/UnoApp.csproj;           tf="$TV-desktop";;
  ava:ios)          proj=AvaApp.iOS/AvaApp.iOS.csproj;   tf="$TV-ios";;
  ava:macos)        proj=AvaApp.Desktop/AvaApp.Desktop.csproj; tf="$TV";;
  maui:ios)         proj=MauiApp1.csproj;                tf="$TV-ios";;
  maui:maccatalyst) proj=MauiApp1.csproj;                tf="$TV-maccatalyst";;
  *) echo "n/a: $FW:$GROUP"; exit 0;;
esac
# single-project heads: only evaluate the TFM being built (keeps global props out of the other heads' restore)
TFS=""; case "$FW" in uno|maui) TFS="-p:TargetFrameworks=$tf";; esac
# Avalonia iOS: the template predates the iOS 27 UIScene requirement (MT7199); skip the build-time check so the size can be measured
AVA_IOS=""; [ "$FW:$GROUP" = ava:ios ] && AVA_IOS="-p:ValidateSceneManifest=false"

NOSIGN="-p:EnableCodeSigning=false -p:CodesignRequireProvisioningProfile=false"
cases_ios() {
  echo "debug|ios-arm64|-c Debug -r ios-arm64 $NOSIGN"
  echo "release-default|ios-arm64|-c Release -r ios-arm64 $NOSIGN"
  echo "release-trimfull|ios-arm64|-c Release -r ios-arm64 -p:TrimMode=full $NOSIGN"
  echo "mono-interpreter|ios-arm64|-c Release -r ios-arm64 -p:UseMonoRuntime=true -p:UseInterpreter=true $NOSIGN"
  echo "mono-aot|ios-arm64|-c Release -r ios-arm64 -p:UseMonoRuntime=true $NOSIGN"
  echo "coreclr|ios-arm64|-c Release -r ios-arm64 -p:UseMonoRuntime=false $NOSIGN"
  echo "nativeaot|ios-arm64|-c Release -r ios-arm64 -p:PublishAot=true $NOSIGN"
}
cases_maccatalyst() {
  echo "debug|maccatalyst-arm64|-c Debug -r maccatalyst-arm64 $NOSIGN"
  echo "release-default|maccatalyst-arm64|-c Release -r maccatalyst-arm64 $NOSIGN"
  echo "release-default|maccatalyst-universal|-c Release $NOSIGN"
  echo "mono-interpreter|maccatalyst-arm64|-c Release -r maccatalyst-arm64 -p:UseMonoRuntime=true -p:UseInterpreter=true $NOSIGN"
  echo "mono-aot|maccatalyst-arm64|-c Release -r maccatalyst-arm64 -p:UseMonoRuntime=true $NOSIGN"
  echo "coreclr|maccatalyst-arm64|-c Release -r maccatalyst-arm64 -p:UseMonoRuntime=false $NOSIGN"
  echo "nativeaot|maccatalyst-arm64|-c Release -r maccatalyst-arm64 -p:PublishAot=true $NOSIGN"
}
cases_macos() {
  R="-r osx-arm64"
  echo "debug-fdd|osx-arm64|-c Debug --self-contained false $R"
  echo "release-default|osx-arm64|-c Release $R"
  echo "fdd|osx-arm64|-c Release --self-contained false $R"
  echo "scd|osx-arm64|-c Release --self-contained true $R"
  echo "scd-trim|osx-arm64|-c Release --self-contained true -p:PublishTrimmed=true $R"
  echo "scd-trimpartial|osx-arm64|-c Release --self-contained true -p:PublishTrimmed=true -p:TrimMode=partial $R"
  echo "scd-r2r|osx-arm64|-c Release --self-contained true -p:PublishReadyToRun=true $R"
  echo "scd-trim-r2r|osx-arm64|-c Release --self-contained true -p:PublishTrimmed=true -p:PublishReadyToRun=true $R"
  echo "singlefile-trim|osx-arm64|-c Release --self-contained true -p:PublishTrimmed=true -p:PublishSingleFile=true -p:EnableCompressionInSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true $R"
  echo "nativeaot|osx-arm64|-c Release -p:PublishAot=true $R"
  echo "mono-scd-trim|osx-arm64|-c Release --self-contained true -p:UseMonoRuntime=true -p:PublishTrimmed=true $R"
  if [ "$FW" = uno ]; then echo "app-bundle-scd-trim|osx-arm64|-c Release --self-contained true -p:PublishTrimmed=true -p:TrimMode=partial -p:PackageFormat=app $R"; fi
}

sumsizes() { awk '{s+=$1} END {print s+0}'; }
dirbytes() { find "$1" -type f -exec stat -f%z {} + 2>/dev/null | sumsizes; }
zipbytes() { local z; z="$(mktemp -d)/p.zip"; ditto -c -k --sequesterRsrc --keepParent "$1" "$z"; stat -f%z "$z"; rm -rf "$(dirname "$z")"; }
# App Store: FairPlay encrypts every Mach-O, so those bytes don't compress in the download; everything else does
appstore_bytes() { local total=0 sz f; while IFS= read -r -d '' f; do if file -b "$f" | grep -q 'Mach-O'; then sz=$(stat -f%z "$f"); else sz=$(gzip -9 -c "$f" | wc -c | tr -d ' '); fi; total=$((total + sz)); done < <(find "$1" -type f -print0); echo $total; }
macho_bytes() { local total=0 f; while IFS= read -r -d '' f; do if file -b "$f" | grep -q 'Mach-O'; then total=$((total + $(stat -f%z "$f"))); fi; done < <(find "$1" -type f -print0); echo $total; }

cases_$GROUP | while IFS='|' read -r ID TARGET ARGS; do
  if [ -n "$ONLY" ] && ! echo " $ONLY " | grep -q " $ID "; then continue; fi
  NAME="$ID--$TARGET"; OUT="$OUTROOT/$NAME"; LOG="$LOGS/$NAME.log"
  find "$WORK/$SRC" -type d \( -name bin -o -name obj \) -prune -exec rm -rf {} + 2>/dev/null
  rm -rf "$OUT"
  START=$(date +%s)
  # 20-minute cap per build, so a pathological ILLink/ILC run can't wedge the lane
  # shellcheck disable=SC2086
  # Avalonia: enable NativeAOT on the head only (HeadPublishAot in the iOS csproj), not on the class library
  [ "$FW" = ava ] && [ "$GROUP" = ios ] && ARGS=$(echo "$ARGS" | sed 's/-p:PublishAot=true/-p:HeadPublishAot=true/')
  ( dotnet publish "$WORK/$SRC/$proj" -f "$tf" $TFS $AVA_IOS -o "$OUT" -nologo -v:m -clp:Summary -p:UnoEnableHotReload=false $ARGS >"$LOG" 2>&1 </dev/null ) & PUBPID=$!
  ( sleep 1200; if kill -0 $PUBPID 2>/dev/null; then echo "TIMEOUT: build killed after 20 minutes" >> "$LOG"; pkill -TERM -f "$WORK/$SRC"; kill -TERM $PUBPID; fi ) & WDPID=$!
  wait $PUBPID; CODE=$?; kill $WDPID 2>/dev/null; wait $WDPID 2>/dev/null
  SECS=$(( $(date +%s) - START ))
  STATUS=fail; PKG=""; PKGB=0; INST=0; EXTRA=""; ERR=""
  WL=$(grep -E "warning [A-Z]+[0-9]+" "$LOG" | sed -E 's/ *\[[^]]+\] *$//; s/^ *//' | sort -u)
  NW=$(printf '%s' "$WL" | grep -c . || true)
  ILW=$(printf '%s\n' "$WL" | grep -oE "warning IL[0-9]+" | awk '{print $2}' | sort | uniq -c | awk '{printf "%sx%s ", $2, $1}')
  WC=$(printf '%s\n' "$WL" | grep -oE "warning [A-Z]+[0-9]+" | awk '{print $2}' | sort | uniq -c | sort -rn | head -8 | awk '{printf "%sx%s ", $2, $1}')
  if [ $CODE -eq 0 ] && ! grep -q '^TIMEOUT' "$LOG"; then
    APP=$(find "$OUT" "$WORK/$SRC" -name "*.app" -type d -path "*$TARGET*" -not -path "*/obj/*" -not -path "*.app/*" 2>/dev/null | head -1)
    [ -z "$APP" ] && APP=$(find "$OUT" "$WORK/$SRC" -name "*.app" -type d -not -path "*/obj/*" -not -path "*.app/*" 2>/dev/null | head -1)
    PKGF=$(find "$OUT" -name "*.pkg" 2>/dev/null | head -1)
    if [ "$GROUP" = macos ]; then  # folder publishes: ship size excludes debug symbols (same rule as Windows/Linux)
      EXTRA=",\"pdbBytes\":$( { find "$OUT" -type f \( -name '*.pdb' -o -name '*.dbg' \) -exec stat -f%z {} + ; find "$OUT" -type d -name '*.dSYM' -exec sh -c 'find "$1" -type f -exec stat -f%z {} +' _ {} \; ; } 2>/dev/null | sumsizes)"
      find "$OUT" -type f \( -name '*.pdb' -o -name '*.dbg' \) -delete; find "$OUT" -type d -name '*.dSYM' -prune -exec rm -rf {} +
    fi
    if [ "$GROUP" = ios ] && [ -n "$APP" ]; then
      PKG=appstore-estimate; PKGB=$(appstore_bytes "$APP"); INST=$(dirbytes "$APP")
      EXTRA="$EXTRA,\"ipaZipBytes\":$(zipbytes "$APP"),\"machoBytes\":$(macho_bytes "$APP")"
    elif [ "$GROUP" = maccatalyst ] && [ -n "$APP" ]; then PKG=app-zip; PKGB=$(zipbytes "$APP"); INST=$(dirbytes "$APP"); EXTRA="$EXTRA,\"machoBytes\":$(macho_bytes "$APP")"
    elif [ "$ID" = app-bundle-scd-trim ] && [ -n "$APP" ]; then PKG=app-zip; PKGB=$(zipbytes "$APP"); INST=$(dirbytes "$APP")
    elif [ "$GROUP" = macos ]; then PKG=zip; PKGB=$(zipbytes "$OUT"); INST=$(dirbytes "$OUT")
    fi
    [ -n "$PKGF" ] && EXTRA="$EXTRA,\"pkgBytes\":$(stat -f%z "$PKGF")"
    if [ "${PKGB:-0}" -gt 0 ]; then STATUS=ok; else ERR="no package found"; fi
  else
    if grep -q '^TIMEOUT' "$LOG"; then STATUS=timeout; fi
    ERR=$(grep -E "error [A-Z]+[0-9]+|error:|^TIMEOUT" "$LOG" | head -3 | sed 's/^ *//' | tr '\n' '|' | tr -d '"\\' | cut -c1-600)
    [ -z "$ERR" ] && ERR=$(tail -5 "$LOG" | tr '\n' '|' | tr -d '"\\' | cut -c1-600)
  fi
  printf '{"tfm":"%s","fw":"%s","group":"%s","target":"%s","config":"%s","args":"%s","seconds":%s,"warnings":%s,"ilWarnings":"%s","warningCodes":"%s","status":"%s","package":"%s","packageBytes":%s,"installBytes":%s%s,"error":"%s"}\n' \
    "$TFM" "$FW" "$GROUP" "$TARGET" "$ID" "$ARGS" "$SECS" "${NW:-0}" "${ILW% }" "${WC% }" "$STATUS" "$PKG" "${PKGB:-0}" "${INST:-0}" "$EXTRA" "$ERR" >> "$RES"
  printf '%-7s %-36s %4ss %s\n' "$STATUS" "$NAME" "$SECS" "$( [ "$STATUS" = ok ] && echo "$((PKGB/1024)) KB" || echo "$ERR" )"
  # keep a top-files listing of the template-default Release build for the size analysis
  if [ "$STATUS" = ok ] && [ "$ID" = release-default ]; then
    T="${APP:-$OUT}"; find "$T" -type f -exec stat -f'%z %N' {} + 2>/dev/null | sort -rn | head -25 > "$LOGS/$NAME.topfiles.txt"
  fi
  rm -rf "$OUT"
done
find "$WORK/$SRC" -type d \( -name bin -o -name obj \) -prune -exec rm -rf {} + 2>/dev/null
echo "LANE DONE $LANE"
