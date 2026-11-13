#!/bin/sh
# LuminarisMD Community — easy installer
#
#   curl -LsSf https://raw.githubusercontent.com/froegeg/LuminarisMD-Community/main/install.sh | sh
#
# Opsi (env):
#   LUMINARIS_DIR=~/LuminarisMD   folder tujuan
#   LUMINARIS_LOG=~/luminaris.install.log   lokasi log instalasi
#   LUMINARIS_SKIP_DEPS=1         lewati install paket sistem (Termux)
#   LUMINARIS_SKIP_INSTALL=1      lewati npm install

set -eu

REPO="froegeg/LuminarisMD-Community"
ZIP_URL="https://github.com/$REPO/releases/latest/download/LuminarisMD.zip"
DEST="${LUMINARIS_DIR:-$HOME/LuminarisMD}"
LOG="${LUMINARIS_LOG:-$HOME/luminaris.install.log}"
TMP=""

# ── Logging: tampil di terminal + simpan ke file ────────────────────
line() { printf '%s\n' "$*" | tee -a "$LOG"; }
step() { line ""; line "── $* ─────────────────────────────"; }
say()  { line "▸ $*"; }
ok()   { line "✓ $*"; }
fail() { line "✗ $*"; line ""; line "Log lengkap: $LOG"; exit 1; }

# Jalankan perintah sambil streaming output ke terminal dan log.
run() {
  status_file="$TMP/.status"
  rm -f "$status_file"
  { set +e; "$@" 2>&1; printf '%s' "$?" >"$status_file"; } | tee -a "$LOG"
  [ -f "$status_file" ] || fail "Gagal menjalankan: $*"
  [ "$(cat "$status_file")" -eq 0 ] || fail "Gagal menjalankan: $*"
}

need() { command -v "$1" >/dev/null 2>&1; }
is_termux() { [ -n "${TERMUX_VERSION:-}" ] || [ -d "/data/data/com.termux" ]; }

# Rapikan log: progress bar curl (\r) jadi baris biasa lalu buang frame-nya.
tidy_log() {
  [ -f "$LOG" ] || return 0
  tr '\r' '\n' <"$LOG" | sed '/^[#=O0-9.% -]*$/d' >"$LOG.tmp" && mv "$LOG.tmp" "$LOG"
}

TMP=$(mktemp -d)
cleanup() { [ -n "$TMP" ] && rm -rf "$TMP"; }
trap cleanup EXIT INT TERM

: >"$LOG" 2>/dev/null || { printf 'Tidak bisa menulis log: %s\n' "$LOG" >&2; exit 1; }

line "LuminarisMD Community installer"
line "Tanggal : $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
line "Log     : $LOG"

# ── 1. Prasyarat sistem ─────────────────────────────────────────────
step "[1/5] Memeriksa sistem"
if is_termux; then
  line "Lingkungan: Termux"
  if [ "${LUMINARIS_SKIP_DEPS:-0}" != "1" ]; then
    say "Memperbarui paket Termux..."
    run pkg update -y
    say "Memasang nodejs-lts, git, unzip, python, libvips..."
    run pkg install -y nodejs-lts git unzip python libvips
    ok "Paket sistem siap"
  else
    line "Install paket sistem dilewati (LUMINARIS_SKIP_DEPS=1)"
  fi
else
  line "Lingkungan: $(uname -s)"
  for c in curl unzip git node npm; do
    need "$c" || fail "'$c' tidak ada. Install dulu lalu jalankan ulang."
    ok "$c ditemukan"
  done
fi

need node || fail "Node.js belum terpasang. Termux: pkg install nodejs-lts"
need npm  || fail "npm belum terpasang."
need curl || fail "curl belum terpasang."
need unzip || fail "unzip belum terpasang."

# ── 2. Versi Node ───────────────────────────────────────────────────
step "[2/5] Memeriksa Node.js"
major=$(node -p "process.versions.node.split('.')[0]")
minor=$(node -p "process.versions.node.split('.')[1]")
line "Node.js: $(node -v)  (butuh >= 22.13.0)"
if [ "$major" -lt 22 ] || { [ "$major" -eq 22 ] && [ "$minor" -lt 13 ]; }; then
  fail "Node.js $(node -v) terlalu lama. Butuh >= 22.13.0."
fi
ok "Versi Node.js memenuhi syarat"

# ── 3. Folder tujuan ────────────────────────────────────────────────
step "[3/5] Menyiapkan folder tujuan"
if [ -e "$DEST" ] && [ -n "$(ls -A "$DEST" 2>/dev/null)" ]; then
  fail "$DEST sudah ada dan tidak kosong. Set LUMINARIS_DIR=/path/lain."
fi
mkdir -p "$DEST"
ok "Folder: $DEST"

# ── 4. Unduh & ekstrak rilis terbaru ────────────────────────────────
step "[4/5] Mengunduh dan mengekstrak paket"
say "Mengunduh: $ZIP_URL"
run curl -fL --progress-bar "$ZIP_URL" -o "$TMP/pkg.zip"
tidy_log

say "Mengekstrak paket..."
mkdir -p "$TMP/src"
run unzip -q "$TMP/pkg.zip" -d "$TMP/src"

SRC="$TMP/src"
set -- "$SRC"/*
if [ "$#" -eq 1 ] && [ -d "$1" ]; then SRC="$1"; fi
[ -f "$SRC/package.json" ] || fail "Isi ZIP tidak valid (package.json tidak ditemukan)."

cp -R "$SRC"/. "$DEST"/
ok "Paket diekstrak ke $DEST"

# ── 5. Dependensi npm ───────────────────────────────────────────────
step "[5/5] Memasang dependensi"
cd "$DEST"
if [ "${LUMINARIS_SKIP_INSTALL:-0}" != "1" ]; then
  say "npm install (bisa beberapa menit)..."
  run npm install --no-audit --no-fund
  if is_termux; then
    say "Menambahkan sharp untuk Termux..."
    run npm install --no-audit --no-fund @img/sharp-wasm32
  fi
  ok "Dependensi terpasang"
else
  line "npm install dilewati (LUMINARIS_SKIP_INSTALL=1)"
fi

line ""
tidy_log
ok "Instalasi selesai — log: $LOG"
cat <<EOF

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