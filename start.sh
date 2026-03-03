#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  OnionTalkie · start.sh
#  Avvia il server locale: build web + bridge Tor + HTTP server
# ─────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PORT="${PORT:-8080}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}"
echo "   ___  _   _ ___ ___  _   _ "
echo "  / _ \\| \\ | |_ _/ _ \\| \\ | |"
echo " | | | |  \\| || | | | |  \\| |"
echo " | |_| | |\\  || | |_| | |\\  |"
echo "  \\___/|_| \\_|___\\___/|_| \\_|  Talkie"
echo -e "${NC}"

# ── Check dependencies ──

echo -e "${YELLOW}▶ Verifica dipendenze...${NC}"

# Flutter
if ! command -v flutter &>/dev/null; then
  echo -e "${RED}❌ Flutter non trovato. Installalo da https://flutter.dev${NC}"
  exit 1
fi
echo -e "  ${GREEN}✓${NC} Flutter"

# Dart
if ! command -v dart &>/dev/null; then
  echo -e "${RED}❌ Dart non trovato. Viene installato con Flutter.${NC}"
  exit 1
fi
echo -e "  ${GREEN}✓${NC} Dart"

# Tor (optional — server will warn if not found)
if command -v tor &>/dev/null; then
  echo -e "  ${GREEN}✓${NC} Tor ($(tor --version 2>/dev/null | head -1))"
else
  echo -e "  ${YELLOW}⚠${NC}  Tor non trovato — il server proverà ad avviarlo, ma potrebbe fallire."
  echo -e "      Installa: ${CYAN}brew install tor${NC} (macOS) / ${CYAN}sudo apt install tor${NC} (Linux)"
fi

echo ""

# ── Build web ──

echo -e "${YELLOW}▶ Build webapp Flutter...${NC}"
flutter build web --release
echo -e "${GREEN}✓ Build completata${NC}"
echo ""

# ── Install server dependencies ──

echo -e "${YELLOW}▶ Installazione dipendenze server...${NC}"
cd "$SCRIPT_DIR/server"
dart pub get
cd "$SCRIPT_DIR"
echo -e "${GREEN}✓ Dipendenze pronte${NC}"
echo ""

# ── Start server ──

echo -e "${YELLOW}▶ Avvio server su porta $PORT...${NC}"
echo ""

exec dart run server/bin/server.dart \
  --port "$PORT" \
  --host "0.0.0.0" \
  --web-dir "./build/web" \
  --tor-data "./server/tor_data" \
  "$@"
