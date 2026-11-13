#!/bin/sh
# LuminarisMD Community — easy installer
#
#   curl -LsSf https://raw.githubusercontent.com/froegeg/LuminarisMD-Community/main/install.sh | sh
#
# Opsi (env):
#   LUMINARIS_DIR=~/LuminarisMD   folder tujuan
#   LUMINARIS_SKIP_DEPS=1         lewati install paket sistem (Termux)
#   LUMINARIS_SKIP_INSTALL=1      lewati npm install

set -eu

REPO="froegeg/LuminarisMD-Community"
ZIP_URL="https://github.com/$REPO/releases/latest/download/LuminarisMD.zip"
DEST="${LUMINARIS_DIR:-$HOME/LuminarisMD}"

say()  { printf '\033[1;36m▸ %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
fail() { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1; }
is_termux() { [ -n "${TERMUX_VERSION:-}" ] || [ -d "/data/data/com.termux" ]; }

# ── 1. Prasyarat sistem ─────────────────────────────────────────────
if is_termux; then
  if [ "${LUMINARIS_SKIP_DEPS:-0}" != "1" ]; then
    say "Termux terdeteksi — memasang paket sistem..."
    pkg update -y >/dev/null 2>&1 || true
    pkg install -y nodejs-lts git unzip python libvips >/dev/null 2>&1 \
      || fail "Gagal memasang paket Termux."
  fi
else
  for c in curl unzip git node npm; do
    need "$c" || fail "'$c' tidak ada. Install dulu lalu jalankan ulang."
  done
fi

need node || fail "Node.js belum terpasang. Termux: pkg install nodejs-lts"
need npm  || fail "npm belum terpasang."
need curl || fail "curl belum terpasang."

# ── 2. Versi Node ───────────────────────────────────────────────────
major=$(node -p "process.versions.node.split('.')[0]")
minor=$(node -p "process.versions.node.split('.')[1]")
if [ "$major" -lt 22 ] || { [ "$major" -eq 22 ] && [ "$minor" -lt 13 ]; }; then
  fail "Node.js $(node -v) terlalu lama. Butuh >= 22.13.0."
fi

# ── 3. Folder tujuan ────────────────────────────────────────────────
if [ -e "$DEST" ] && [ -n "$(ls -A "$DEST" 2>/dev/null)" ]; then
  fail "$DEST sudah ada dan tidak kosong. Set LUMINARIS_DIR=/path/lain."
fi

# ── 4. Unduh & ekstrak rilis terbaru ────────────────────────────────
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

say "Mengunduh rilis terbaru..."
curl -fLsS "$ZIP_URL" -o "$TMP/pkg.zip" || fail "Gagal mengunduh $ZIP_URL"

say "Mengekstrak..."
mkdir -p "$TMP/src"
unzip -q "$TMP/pkg.zip" -d "$TMP/src" || fail "Gagal mengekstrak ZIP."

SRC="$TMP/src"
set -- "$SRC"/*
if [ "$#" -eq 1 ] && [ -d "$1" ]; then SRC="$1"; fi
[ -f "$SRC/package.json" ] || fail "Isi ZIP tidak valid (package.json tidak ditemukan)."

mkdir -p "$DEST"
cp -R "$SRC"/. "$DEST"/
ok "Paket siap di $DEST"

# ── 5. Dependensi npm ───────────────────────────────────────────────
cd "$DEST"
if [ "${LUMINARIS_SKIP_INSTALL:-0}" != "1" ]; then
  say "Memasang dependensi (npm install)..."
  npm install --no-audit --no-fund || fail "npm install gagal."
  if is_termux; then
    npm install --no-audit --no-fund @img/sharp-wasm32 >/dev/null 2>&1 || true
  fi
fi

cat <<EOF

✓ Instalasi selesai.

Langkah berikutnya:
  1. cd $DEST
  2. Edit config.js → botNumber, ownerNumber, botName
  3. npm start
  4. Tautkan WhatsApp lewat pairing code / QR

ffmpeg (fitur audio/video):
  Termux : pkg install ffmpeg
  Ubuntu : sudo apt install ffmpeg
  macOS  : brew install ffmpeg
EOF