#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────
#  fetch_tor_android.sh
#  Scarica i binari Tor ufficiali per Android (arm64-v8a, armeabi-v7a,
#  x86_64) dal Tor Browser release bundle e li piazza nella directory
#  jniLibs del progetto Android.
#
#  Requisiti: curl, unzip
#
#  Utilizzo:
#    cd <project_root>
#    bash scripts/fetch_tor_android.sh [TOR_VERSION]
#
#  Esempio:
#    bash scripts/fetch_tor_android.sh 14.0.4
#
#  Se non specifichi la versione, lo script la rileva automaticamente
#  dall'ultima release stabile del Tor Browser.
# ──────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
JNILIBS_DIR="$PROJECT_ROOT/android/app/src/main/jniLibs"
TMP_DIR="$(mktemp -d)"

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

log()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }

# ──────────────────────────────────────────────────────────────────
# 1. Determina la versione Tor Browser da usare
# ──────────────────────────────────────────────────────────────────

if [[ $# -ge 1 ]]; then
  TB_VERSION="$1"
  log "Versione specificata manualmente: $TB_VERSION"
else
  log "Rilevo l'ultima versione stabile del Tor Browser…"
  TB_VERSION=$(curl -sfL "https://aus1.torproject.org/torbrowser/update_3/release/downloads.json" \
    | grep -oE '"version"\s*:\s*"[^"]+"' | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)*') || true
  if [[ -z "${TB_VERSION:-}" ]]; then
    error "Impossibile rilevare la versione. Specifica manualmente: $0 <versione>"
  fi
  log "Ultima versione rilevata: $TB_VERSION"
fi

# ──────────────────────────────────────────────────────────────────
# 2. Mappa ABI Android → suffisso Tor Browser APK
# ──────────────────────────────────────────────────────────────────

declare -A ABI_MAP=(
  ["arm64-v8a"]="aarch64"
  ["armeabi-v7a"]="armv7"
  ["x86_64"]="x86_64"
)

BASE_URL="https://dist.torproject.org/torbrowser/${TB_VERSION}"

# ──────────────────────────────────────────────────────────────────
# 3. Scarica e estrai i binari
# ──────────────────────────────────────────────────────────────────

for ABI in "${!ABI_MAP[@]}"; do
  ARCH="${ABI_MAP[$ABI]}"
  APK_NAME="tor-browser-android-${ARCH}-${TB_VERSION}.apk"
  APK_URL="${BASE_URL}/${APK_NAME}"
  APK_PATH="${TMP_DIR}/${APK_NAME}"

  log "Scarico $APK_NAME …"
  if ! curl -sfL -o "$APK_PATH" "$APK_URL"; then
    warn "  ⚠ Impossibile scaricare per $ABI ($ARCH). Salto."
    continue
  fi

  log "Estraggo libTor.so per $ABI …"
  mkdir -p "$TMP_DIR/extract_${ABI}"

  # Il binario Tor nell'APK del Tor Browser si trova in lib/{abi}/libTor.so
  FOUND=false
  for LIB_NAME in "lib/${ABI}/libTor.so" "lib/${ABI}/libtor.so"; do
    if unzip -o -j "$APK_PATH" "$LIB_NAME" -d "$TMP_DIR/extract_${ABI}" 2>/dev/null; then
      FOUND=true
      EXTRACTED_FILE="$TMP_DIR/extract_${ABI}/$(basename "$LIB_NAME")"
      TARGET_DIR="${JNILIBS_DIR}/${ABI}"
      mkdir -p "$TARGET_DIR"
      cp "$EXTRACTED_FILE" "$TARGET_DIR/libtor.so"
      chmod +x "$TARGET_DIR/libtor.so"
      SIZE=$(du -h "$TARGET_DIR/libtor.so" | cut -f1)
      log "  → ${ABI}/libtor.so ($SIZE)"
      break
    fi
  done

  if [[ "$FOUND" == false ]]; then
    warn "  ⚠ libTor.so non trovato nell'APK per $ABI"
    warn "  Contenuto lib/ nell'APK:"
    unzip -l "$APK_PATH" | grep "^.*lib/.*\.so" | head -10 || true
  fi

  # Pulisci l'APK per risparmiare spazio (sono ~100 MB ciascuno)
  rm -f "$APK_PATH"
done

# ──────────────────────────────────────────────────────────────────
# 4. Verifica risultato
# ──────────────────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "                 BINARI TOR PER ANDROID"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

TOTAL=0
for ABI in arm64-v8a armeabi-v7a x86_64; do
  LIB="${JNILIBS_DIR}/${ABI}/libtor.so"
  if [[ -f "$LIB" ]]; then
    SIZE=$(du -h "$LIB" | cut -f1)
    FILE_INFO=$(file "$LIB" 2>/dev/null | sed 's/.*: //')
    echo -e "  ${GREEN}✓${NC} $ABI  ${SIZE}  ($FILE_INFO)"
    TOTAL=$((TOTAL + 1))
  else
    echo -e "  ${RED}✗${NC} $ABI  (non trovato)"
  fi
done

echo ""
if [[ $TOTAL -eq 0 ]]; then
  error "Nessun binario Tor trovato! Controlla la versione e riprova."
elif [[ $TOTAL -lt 3 ]]; then
  warn "Solo $TOTAL/3 architetture trovate. L'app funzionerà solo su quei dispositivi."
else
  log "Tutti i binari Tor ($TOTAL/3) installati con successo!"
fi

echo ""
echo "Percorso: $JNILIBS_DIR"
echo "Versione Tor Browser: $TB_VERSION"
echo ""
echo "Ora puoi compilare l'app con: flutter build apk --release"
echo ""
