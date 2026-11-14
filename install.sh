#!/bin/sh
# LuminarisMD Community — easy installer
#
#   curl -LsSf https://raw.githubusercontent.com/froegeg/LuminarisMD-Community/main/install.sh | sh
#
# Opsi (env):
#   LUMINARIS_DIR=~/LuminarisMD            folder tujuan
#   LUMINARIS_LOG=~/luminaris.install.log  lokasi log instalasi
#   LUMINARIS_VERSION=v2.2.6               versi yang ditampilkan
#   LUMINARIS_SKIP_DEPS=1                  lewati install paket sistem (Termux)
#   LUMINARIS_SKIP_INSTALL=1               lewati npm install
#   LUMINARIS_ZIP_URL=<url>                paket rilis alternatif
#   LUMINARIS_ZIP_SHA256=<hex>             checksum paket alternatif
#   LUMINARIS_OPEN_SHELL=1                 buka shell di folder instalasi setelah selesai

set -eu

REPO="froegeg/LuminarisMD-Community"
RELEASE_API="https://api.github.com/repos/$REPO/releases/latest"
ZIP_URL="${LUMINARIS_ZIP_URL:-https://github.com/$REPO/releases/latest/download/LuminarisMD.zip}"
if [ -n "${LUMINARIS_ZIP_URL:-}" ]; then
  ZIP_URLS="$ZIP_URL"
else
  # release-assets.githubusercontent.com diblokir di beberapa jaringan.
  ZIP_URLS="$ZIP_URL https://gh-proxy.com/$ZIP_URL https://ghfast.top/$ZIP_URL"
fi
DEST="${LUMINARIS_DIR:-$HOME/LuminarisMD}"
LOG="${LUMINARIS_LOG:-$HOME/luminaris.install.log}"
APP_AUTHOR="froegeg"
APP_VERSION="${LUMINARIS_VERSION:-v2.2.6}"
TOTAL_STEPS=5

TMP=""
UPDATE=0
BACKUP=""
PCT=0
RUN_PID=""
START_TS=$(date +%s)

# ── Warna (hanya kalau stdout TTY) ──────────────────────────────────
IS_TTY=0
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ]; then
  IS_TTY=1
fi

if [ "$IS_TTY" = "1" ] && [ -z "${NO_COLOR:-}" ]; then
  C_R=$(printf '\033[0m')
  C_B=$(printf '\033[1m')
  C_D=$(printf '\033[2m')
  C_C=$(printf '\033[36m')
  C_M=$(printf '\033[35m')
  C_G=$(printf '\033[32m')
  C_Y=$(printf '\033[33m')
  C_E=$(printf '\033[31m')
else
  C_R=""
  C_B=""
  C_D=""
  C_C=""
  C_M=""
  C_G=""
  C_Y=""
  C_E=""
fi

# ── Util ────────────────────────────────────────────────────────────
need() { command -v "$1" >/dev/null 2>&1; }
is_termux() { [ -n "${TERMUX_VERSION:-}" ] || [ -d "/data/data/com.termux" ]; }

sha256_of() {
  if need sha256sum; then
    sha256sum "$1" | awk '{print $1}'
  elif need shasum; then
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

release_digest() {
  if [ -n "${LUMINARIS_ZIP_SHA256:-}" ]; then
    printf '%s' "$LUMINARIS_ZIP_SHA256"
    return 0
  fi
  # Paket custom tidak punya entri digest di API rilis.
  [ -n "${LUMINARIS_ZIP_URL:-}" ] && return 0
  curl -fsSL --connect-timeout 10 --max-time 20 "$RELEASE_API" 2>/dev/null |
    sed -n 's/.*"digest":[[:space:]]*"sha256:\([0-9a-f]\{64\}\)".*/\1/p' |
    head -n 1
}

pick_zip_url() {
  for candidate in $ZIP_URLS; do
    log "  Menguji akses paket: $candidate"
    if curl -fsIL --connect-timeout 8 --max-time 20 "$candidate" >/dev/null 2>&1; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

if is_termux; then
  ENV_LABEL="Termux"
else
  ENV_LABEL=$(uname -s)
fi

log() { printf '%s\n' "$*" >>"$LOG"; }

clip_line() {
  clip_text=$1
  clip_max=$2
  [ "$IS_TTY" = "1" ] || { printf '%s' "$clip_text"; return 0; }
  case "$clip_max" in
    ''|*[!0-9]*) clip_max=40 ;;
  esac
  [ "$clip_max" -lt 8 ] && clip_max=8
  if [ "${#clip_text}" -gt "$clip_max" ]; then
    printf '%s...' "$(printf '%s' "$clip_text" | cut -c1-$((clip_max - 3)))"
  else
    printf '%s' "$clip_text"
  fi
}

say() {
  cols=$(term_cols)
  printf '  %s▸%s %s\n' "$C_C" "$C_R" "$(clip_line "$*" $((cols - 5)))"
  log "  ▸ $*"
}
ok() {
  cols=$(term_cols)
  printf '  %s✓%s %s\n' "$C_G" "$C_R" "$(clip_line "$*" $((cols - 5)))"
  log "  ✓ $*"
}
warn() {
  cols=$(term_cols)
  printf '  %s!%s %s\n' "$C_Y" "$C_R" "$(clip_line "$*" $((cols - 5)))"
  log "  ! $*"
}
err() {
  cols=$(term_cols)
  printf '  %s✗%s %s\n' "$C_E" "$C_R" "$(clip_line "$*" $((cols - 5)))"
  log "  ✗ $*"
}

# Lebar terminal; dihitung ulang setiap render supaya ikut saat window di-resize.
term_cols() {
  cols=""
  if [ "$IS_TTY" = "1" ]; then
    if command -v stty >/dev/null 2>&1; then
      sz=$(stty size < /dev/tty 2>/dev/null || true)
      case "$sz" in
        *' '*) cols=${sz#* } ;;
      esac
    fi
    [ -z "$cols" ] && cols="${COLUMNS:-}"
  fi
  case "${cols:-}" in
    ''|*[!0-9]*) cols=80 ;;
  esac
  [ "$cols" -lt 32 ] && cols=32
  [ "$cols" -gt 120 ] && cols=120
  printf '%s' "$cols"
}

repeat_char() {
  # $1 = karakter, $2 = jumlah
  awk -v c="$1" -v n="$2" 'BEGIN { for (i = 0; i < n; i++) printf "%s", c }'
}

clear_line() {
  if [ "$IS_TTY" = "1" ]; then
    printf '\r\033[K'
  fi
  return 0
}

rule() {
  cols=$(term_cols)
  n=$((cols - 3))
  [ "$n" -lt 10 ] && n=10
  if [ "$IS_TTY" = "1" ]; then
    printf '  %s' "$C_D"
    awk -v n="$n" 'BEGIN { for (i = 0; i < n; i++) printf "─" }'
    printf '%s\n' "$C_R"
  else
    awk -v n="$n" 'BEGIN { for (i = 0; i < n; i++) printf "-"; print "" }'
  fi
}

spin_char() {
  case $(( $1 % 4 )) in
    0) printf '|' ;;
    1) printf '/' ;;
    2) printf '-' ;;
    3) printf '\\' ;;
  esac
}

elapsed() {
  elapsed_now=$(date +%s)
  elapsed_secs=$((elapsed_now - START_TS))
  elapsed_mins=$((elapsed_secs / 60))
  elapsed_rem=$((elapsed_secs % 60))
  if [ "$elapsed_mins" -gt 0 ]; then
    printf '%dm %ds' "$elapsed_mins" "$elapsed_rem"
  else
    printf '%ds' "$elapsed_secs"
  fi
}

# ── Progress bar ────────────────────────────────────────────────────
draw_bar() {
  bar_pct=$1
  bar_label=$2
  bar_mode=$3
  bar_spin=${4:-}

  case "$bar_pct" in
    ''|*[!0-9]*) bar_pct=0 ;;
  esac
  [ "$bar_pct" -lt 0 ] && bar_pct=0
  [ "$bar_pct" -gt 100 ] && bar_pct=100

  cols=$(term_cols)
  if [ "$bar_mode" = "live" ]; then
    bar_overhead=15
  else
    bar_overhead=12
  fi

  bar_max_label=$((cols - bar_overhead - 10))
  [ "$bar_max_label" -lt 0 ] && bar_max_label=0
  if [ "$bar_max_label" -gt 0 ]; then
    bar_label=$(printf '%s' "$bar_label" | cut -c1-"$bar_max_label")
  else
    bar_label=""
  fi

  bar_label_len=${#bar_label}
  bar_width=$((cols - bar_overhead - bar_label_len - 1))
  [ "$bar_width" -lt 10 ] && bar_width=10
  [ "$bar_width" -gt 60 ] && bar_width=60

  bar_filled=$((bar_pct * bar_width / 100))
  bar_empty=$((bar_width - bar_filled))
  bar_fill=$(repeat_char '█' "$bar_filled")
  bar_void=$(repeat_char '░' "$bar_empty")

  if [ "$IS_TTY" = "1" ]; then
    if [ "$bar_mode" = "live" ]; then
      printf '\r\033[K  %s▕%s%s%s%s%s%s▏%s %s%3d%%%s  %s%s%s %s' \
        "$C_C" "$C_G" "$bar_fill" "$C_D" "$bar_void" "$C_R" "$C_C" "$C_R" \
        "$C_B" "$bar_pct" "$C_R" "$C_Y" "$bar_spin" "$C_R" "$bar_label"
    else
      printf '  %s▕%s%s%s%s%s%s▏%s %s%3d%%%s  %s\n' \
        "$C_C" "$C_G" "$bar_fill" "$C_D" "$bar_void" "$C_R" "$C_C" "$C_R" \
        "$C_B" "$bar_pct" "$C_R" "$bar_label"
    fi
  else
    [ "$bar_mode" = "live" ] && return 0
    printf '  [%3d%%] %s\n' "$bar_pct" "$bar_label"
  fi
}

progress() {
  prog_pct=$1
  prog_label=$2
  case "$prog_pct" in
    ''|*[!0-9]*) prog_pct=0 ;;
  esac
  [ "$prog_pct" -gt 100 ] && prog_pct=100
  PCT=$prog_pct
  draw_bar "$prog_pct" "$prog_label" line
  log "  [$prog_pct%] $prog_label"
}

# ── Error / cleanup ─────────────────────────────────────────────────
show_tail() {
  [ -s "$1" ] || return 0
  printf '\n  %sOutput terakhir:%s\n' "$C_D" "$C_R"
  tail -n 12 "$1" | while IFS= read -r tail_line; do
    printf '  %s│%s %s\n' "$C_E" "$C_R" "$tail_line"
  done
}

fail() {
  clear_line
  err "$*"
  if [ -n "${TMP:-}" ] && [ -s "$TMP/cmd.out" ]; then
    show_tail "$TMP/cmd.out"
  fi
  if [ -n "${BACKUP:-}" ]; then
    printf '  %sBackup:%s %s\n' "$C_Y" "$C_R" "$BACKUP"
    log "  Backup: $BACKUP"
  fi
  printf '\n  %sLog:%s %s\n' "$C_D" "$C_R" "$LOG"
  exit 1
}

cleanup() {
  if [ -n "${RUN_PID:-}" ]; then
    kill "$RUN_PID" 2>/dev/null || true
  fi
  if [ -n "${TMP:-}" ]; then
    rm -rf "$TMP"
  fi
  return 0
}

on_interrupt() {
  trap - INT TERM
  clear_line
  printf '\n  %sDibatalkan.%s\n' "$C_Y" "$C_R"
  log "Dibatalkan oleh pengguna."
  [ -n "${RUN_PID:-}" ] && kill "$RUN_PID" 2>/dev/null || true
  exit 130
}

# ── Header / step / finish ──────────────────────────────────────────
header() {
  rule
  cols=$(term_cols)
  printf '  %s%s%s %s%s%s\n' \
    "$C_B" "$C_M" "LuminarisMD" "$C_R" "$C_D" \
    "$(clip_line 'Community Installer' $((cols - 15)))"
  printf '  %s%s%s %s•%s %sLuminarisMD %s%s\n' \
    "$C_C" "$APP_AUTHOR" "$C_R" "$C_D" "$C_R" "$C_B" "$APP_VERSION" "$C_R"
  printf '  %s%s%s\n' "$C_D" \
    "$(clip_line "$ENV_LABEL • $(uname -m) • $(date -u '+%Y-%m-%d %H:%M UTC')" $((cols - 3)))" \
    "$C_R"
  rule
  path_max=$((cols - 12))
  printf '  %sLog%s     %s\n' "$C_D" "$C_R" "$(clip_line "$LOG" "$path_max")"
  printf '  %sTarget%s  %s\n' "$C_D" "$C_R" "$(clip_line "$DEST" "$path_max")"
  printf '\n'

  log "LuminarisMD Community Installer"
  log "Author: $APP_AUTHOR"
  log "Version: LuminarisMD $APP_VERSION"
  log "Tanggal: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  log "Lingkungan: $ENV_LABEL $(uname -m)"
  log "Target: $DEST"
  log "Log: $LOG"
  log "============================================================"
}

step() {
  step_num=$1
  step_title=$2
  printf '\n'
  if [ "$IS_TTY" = "1" ]; then
    cols=$(term_cols)
    printf '  %s[%s/%s]%s %s%s%s\n' \
      "$C_D" "$step_num" "$TOTAL_STEPS" "$C_R" "$C_B" \
      "$(clip_line "$step_title" $((cols - 9)))" "$C_R"
    n=$((cols - 3))
    printf '  %s' "$C_D"
    awk -v n="$n" 'BEGIN { for (i = 0; i < n; i++) printf "─" }'
    printf '%s\n' "$C_R"
  else
    printf '  [%s/%s] %s\n' "$step_num" "$TOTAL_STEPS" "$step_title"
  fi
  log ""
  log "[$step_num/$TOTAL_STEPS] $step_title"
}

finish() {
  progress 100 "Instalasi selesai"
  printf '\n'
  rule
  printf '  %s%s✓ Instalasi selesai%s  %s(%s)%s\n' \
    "$C_B" "$C_G" "$C_R" "$C_D" "$(elapsed)" "$C_R"
  printf '  %s%s%s %s•%s %sLuminarisMD %s%s\n' \
    "$C_C" "$APP_AUTHOR" "$C_R" "$C_D" "$C_R" "$C_B" "$APP_VERSION" "$C_R"
  rule
  printf '\n  %sLangkah berikutnya%s\n' "$C_B" "$C_R"
  cols=$(term_cols)
  printf '    %s1.%s cd %s\n' "$C_D" "$C_R" "$(clip_line "$DEST" $((cols - 12)))"
  printf '    %s2.%s %s\n' "$C_D" "$C_R" \
    "$(clip_line 'nano config.js  (botNumber, ownerNumber, botName)' $((cols - 8)))"
  printf '    %s3.%s npm start\n' "$C_D" "$C_R"
  printf '    %s4.%s %s\n' "$C_D" "$C_R" \
    "$(clip_line 'Tautkan WhatsApp lewat pairing code / QR' $((cols - 8)))"

  printf '\n  %sffmpeg%s  ' "$C_D" "$C_R"
  if need ffmpeg && need ffprobe; then
    printf '%s✓ siap%s\n' "$C_G" "$C_R"
  else
    printf '%s! belum ada%s\n' "$C_Y" "$C_R"
    case "$ENV_LABEL" in
      Termux) printf '    pkg install ffmpeg\n' ;;
      Darwin) printf '    brew install ffmpeg\n' ;;
      *)      printf '    sudo apt install ffmpeg\n' ;;
    esac
  fi

  printf '  %sLog%s     %s\n' "$C_D" "$C_R" "$(clip_line "$LOG" $((cols - 12)))"
  printf '\n'

  log ""
  log "Instalasi selesai dalam $(elapsed)."
  log "Author: $APP_AUTHOR • LuminarisMD $APP_VERSION"
  log "Log: $LOG"
}

tidy_log() {
  [ -f "$LOG" ] || return 0
  tr '\r' '\n' <"$LOG" >"$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG" || true
  return 0
}

# Jalankan perintah dengan spinner + hidden output (output masuk log).
run() {
  run_pct=$1
  run_label=$2
  shift 2

  log ""
  log "$ $*"

  if [ ! -t 1 ]; then
    printf '  %s▸%s %s...\n' "$C_C" "$C_R" "$run_label"
    : >"$TMP/cmd.out"
    if "$@" >"$TMP/cmd.out" 2>&1 </dev/null; then
      cat "$TMP/cmd.out" >>"$LOG"
      progress "$run_pct" "$run_label"
      return 0
    fi
    cat "$TMP/cmd.out" >>"$LOG"
    fail "$run_label"
  fi

  : >"$TMP/cmd.out"
  "$@" >"$TMP/cmd.out" 2>&1 </dev/null &
  RUN_PID=$!

  run_i=0
  while kill -0 "$RUN_PID" 2>/dev/null; do
    run_spin=$(spin_char "$run_i")
    draw_bar "$PCT" "$run_label" live "$run_spin"
    run_i=$((run_i + 1))
    sleep 1
  done

  if wait "$RUN_PID"; then
    run_status=0
  else
    run_status=$?
  fi
  RUN_PID=""

  cat "$TMP/cmd.out" >>"$LOG"

  if [ "$run_status" -ne 0 ]; then
    fail "$run_label (exit $run_status)"
  fi

  clear_line
  progress "$run_pct" "$run_label"
}

# ── Mulai ───────────────────────────────────────────────────────────
TMP=$(mktemp -d) || {
  printf 'Gagal membuat direktori sementara.\n' >&2
  exit 1
}
trap cleanup EXIT
trap on_interrupt INT TERM

: >"$LOG" 2>/dev/null || {
  printf 'Tidak bisa menulis log: %s\n' "$LOG" >&2
  exit 1
}

header
progress 0 "Memulai"

# ── 1. Prasyarat sistem ─────────────────────────────────────────────
step 1 "Prasyarat sistem"
if is_termux; then
  ok "Lingkungan: Termux ($(uname -m))"
  if [ "${LUMINARIS_SKIP_DEPS:-0}" != "1" ]; then
    run 6 "Memperbarui repositori Termux" pkg update -y
    if need dpkg; then
      run 10 "Menyelesaikan konfigurasi paket tertunda" dpkg --force-confold --configure -a
    fi
    # --force-confold: jangan berhenti di prompt conffile saat script dijalankan via curl | sh.
    run 20 "Meng-upgrade paket Termux" pkg upgrade -y -o Dpkg::Options::=--force-confold
    run 30 "Memasang paket sistem + ffmpeg" pkg install -y -o Dpkg::Options::=--force-confold \
      nodejs-lts git unzip python build-essential pkg-config libvips ffmpeg
  else
    warn "Install paket sistem dilewati (LUMINARIS_SKIP_DEPS=1)"
  fi
else
  ok "Lingkungan: $ENV_LABEL ($(uname -m))"
  for c in curl unzip git node npm; do
    need "$c" || fail "'$c' tidak ada. Install dulu lalu jalankan ulang."
    ok "$c ditemukan"
  done
  progress 30 "Prasyarat sistem siap"
fi

need node || fail "Node.js belum terpasang. Termux: pkg install nodejs-lts"
need npm  || fail "npm belum terpasang."
need curl || fail "curl belum terpasang."
need unzip || fail "unzip belum terpasang."

if need ffmpeg && need ffprobe; then
  ok "ffmpeg & ffprobe siap"
else
  warn "ffmpeg/ffprobe belum ada — fitur audio/video tidak akan jalan"
fi

# ── 2. Versi Node ───────────────────────────────────────────────────
step 2 "Memeriksa Node.js"
if ! node -v >/dev/null 2>&1; then
  fail "Node.js tidak bisa dijalankan (libc++ mungkin usang). Di Termux jalankan: pkg upgrade -y && pkg install --reinstall libc++ nodejs-lts"
fi

major=$(node -p "process.versions.node.split('.')[0]")
minor=$(node -p "process.versions.node.split('.')[1]")
say "Node.js: $(node -v) (butuh >= 22.13.0)"
if [ "$major" -lt 22 ] || { [ "$major" -eq 22 ] && [ "$minor" -lt 13 ]; }; then
  fail "Node.js $(node -v) terlalu lama. Butuh >= 22.13.0."
fi
ok "Versi Node.js memenuhi syarat"
progress 34 "Node.js siap"

# ── 3. Folder tujuan ────────────────────────────────────────────────
step 3 "Menyiapkan folder tujuan"
case "$DEST" in
  ""|"/"|"$HOME"|"$HOME/") fail "LUMINARIS_DIR tidak valid: $DEST" ;;
esac
case "/$DEST/" in
  */../*|*/./*) fail "LUMINARIS_DIR tidak boleh mengandung '.' atau '..': $DEST" ;;
esac
if [ -e "$DEST" ] && [ ! -d "$DEST" ]; then
  fail "$DEST ada tetapi bukan folder."
fi

if [ -e "$DEST" ] && [ -n "$(ls -A "$DEST" 2>/dev/null)" ]; then
  UPDATE=1
  BACKUP="${DEST}.backup-$(date '+%Y%m%d-%H%M%S')-$$"
  say "Folder sudah ada — mode update"
  say "Pastikan bot sudah berhenti sebelum update."
  say "Folder lama dipindahkan ke: $BACKUP"
  if mv "$DEST" "$BACKUP"; then
    ok "Backup dibuat"
  else
    fail "Gagal memindahkan folder lama ke backup."
  fi
  if mkdir -p "$DEST"; then
    ok "Folder baru: $DEST"
  else
    fail "Gagal membuat folder: $DEST"
  fi
  progress 40 "Folder baru siap"
else
  if mkdir -p "$DEST"; then
    ok "Folder: $DEST"
  else
    fail "Gagal membuat folder: $DEST"
  fi
  progress 40 "Folder tujuan siap"
fi

# ── 4. Unduh & ekstrak rilis terbaru ────────────────────────────────
step 4 "Mengunduh & mengekstrak paket"
say "Rilis: $ZIP_URL"
say "Mencari sumber paket yang bisa diakses..."
DOWNLOAD_URL=$(pick_zip_url) || fail "Semua sumber paket tidak bisa diakses. Periksa koneksi internet."
if [ "$DOWNLOAD_URL" != "$ZIP_URL" ]; then
  say "Jalur alternatif: $DOWNLOAD_URL"
fi

say "Memeriksa checksum rilis..."
EXPECTED_SHA=$(release_digest | tr 'A-F' 'a-f' || true)
if [ -n "$EXPECTED_SHA" ]; then
  say "Checksum rilis: $(printf '%s' "$EXPECTED_SHA" | cut -c1-12)..."
else
  warn "Checksum tidak tersedia — verifikasi dilewati"
fi

run 55 "Mengunduh rilis terbaru" \
  curl -fL -sS --connect-timeout 15 --retry 2 --retry-delay 1 "$DOWNLOAD_URL" -o "$TMP/pkg.zip"

if [ -n "$EXPECTED_SHA" ]; then
  ACTUAL_SHA=$(sha256_of "$TMP/pkg.zip" || true)
  if [ -z "$ACTUAL_SHA" ]; then
    warn "sha256sum tidak tersedia — checksum dilewati"
  elif [ "$ACTUAL_SHA" = "$EXPECTED_SHA" ]; then
    ok "Checksum SHA-256 cocok"
  else
    fail "Checksum paket tidak cocok. Unduhan dibatalkan."
  fi
fi

run 65 "Mengekstrak paket" unzip -q "$TMP/pkg.zip" -d "$TMP/src"

SRC="$TMP/src"
set -- "$SRC"/*
if [ "$#" -eq 1 ] && [ -d "$1" ]; then SRC="$1"; fi
[ -f "$SRC/package.json" ] || fail "Isi ZIP tidak valid (package.json tidak ditemukan)."

if cp -R "$SRC"/. "$DEST"/; then
  ok "Paket diekstrak ke $DEST"
else
  fail "Gagal menyalin paket ke $DEST."
fi
progress 70 "Paket diekstrak"

if [ "$UPDATE" = "1" ]; then
  say "Memulihkan data pengguna dari backup..."
  if [ -f "$BACKUP/config.js" ]; then
    if ! command -v cmp >/dev/null 2>&1 || ! cmp -s "$BACKUP/config.js" "$DEST/config.js"; then
      cp -p "$DEST/config.js" "$DEST/config.new.js" || fail "Gagal menyimpan config default baru."
      restore_msg="  config.js lama dipertahankan; default baru: config.new.js"
    else
      restore_msg="  config.js lama dipertahankan"
    fi
    printf '  %s\n' "$restore_msg"
    log "$restore_msg"
    cp -p "$BACKUP/config.js" "$DEST/config.js" || fail "Gagal memulihkan config.js."
  fi
  for p in .env session data logs; do
    if [ -e "$BACKUP/$p" ]; then
      rm -rf "$DEST/$p"
      cp -Rp "$BACKUP/$p" "$DEST/$p" || fail "Gagal memulihkan $p dari backup."
      ok "$p dipertahankan"
    fi
  done
  ok "Data pengguna dipulihkan"
  progress 74 "Data pengguna dipulihkan"
fi

# ── 5. Dependensi npm ───────────────────────────────────────────────
step 5 "Memasang dependensi"
cd "$DEST" || fail "Tidak bisa masuk ke $DEST"

if [ "${LUMINARIS_SKIP_INSTALL:-0}" != "1" ]; then
  if is_termux; then
    say "Menyiapkan toolchain build Termux..."
    if need python; then export PYTHON="$(command -v python)"; fi
    if need clang; then export CC="$(command -v clang)"; fi
    if need clang++; then export CXX="$(command -v clang++)"; fi
    printf '  %sPYTHON=%s  CC=%s  CXX=%s%s\n' \
      "$C_D" "${PYTHON:-?}" "${CC:-?}" "${CXX:-?}" "$C_R"
    log "  PYTHON=${PYTHON:-?} CC=${CC:-?} CXX=${CXX:-?}"

    run 78 "Membersihkan cache dan artefak lama" \
      rm -rf node_modules package-lock.json bun.lockb "$HOME/.npm/_cacache" "$HOME/.bun/install/cache"
  fi

  # npm 12+ memblokir dependency git (EALLOWGIT) dan lifecycle script secara default.
  # --allow-git=root hanya mengizinkan git dep di package.json root; flag script
  # mengembalikan perilaku npm <=11 agar canvas/esbuild/baileys bisa build.
  npm_major=$(npm --version 2>/dev/null | cut -d. -f1)
  case "$npm_major" in
    ''|*[!0-9]*) npm_major=0 ;;
  esac

  npm_install() {
    ni_pct=$1
    ni_label=$2
    shift 2
    if [ "$npm_major" -ge 12 ]; then
      run "$ni_pct" "$ni_label" \
        npm install --no-audit --no-fund --allow-git=root --dangerously-allow-all-scripts "$@"
    else
      run "$ni_pct" "$ni_label" npm install --no-audit --no-fund "$@"
    fi
  }

  if [ "$npm_major" -ge 12 ]; then
    say "npm $npm_major: mengizinkan git dependency root dan install scripts"
  fi

  npm_install 92 "Memasang dependensi npm"
  if is_termux; then
    npm_install 97 "Menambahkan sharp untuk Termux" @img/sharp-wasm32
  fi
  ok "Dependensi terpasang"
else
  warn "npm install dilewati (LUMINARIS_SKIP_INSTALL=1)"
fi

finish
tidy_log

# Installer berjalan di proses terpisah saat dipanggil via `curl | sh`, jadi
# `cd` di sini tidak bisa memindahkan folder shell pemanggil. Quick install di
# README memakai `... | sh && cd ~/LuminarisMD`; untuk masuk otomatis lewat
# script ini, set LUMINARIS_OPEN_SHELL=1 (butuh terminal/TTY).
cd "$DEST" 2>/dev/null || true

if [ "${LUMINARIS_OPEN_SHELL:-0}" = "1" ]; then
  # test -r/-w pada /dev/tty tetap true walau proses tidak punya controlling
  # terminal, jadi coba buka file descriptor-nya langsung.
  if (exec 3</dev/tty) 2>/dev/null && (exec 3>/dev/tty) 2>/dev/null; then
    shell_bin="${SHELL:-sh}"
    case "$shell_bin" in
      /*)
        if [ ! -f "$shell_bin" ] || [ ! -x "$shell_bin" ]; then
          shell_bin=sh
        fi
        ;;
      *)
        shell_bin=$(command -v "$shell_bin" 2>/dev/null || printf 'sh')
        ;;
    esac
    printf '\n  %sMembuka shell di %s%s\n' "$C_D" "$DEST" "$C_R"
    log "Membuka shell di $DEST"
    cleanup
    trap - EXIT INT TERM
    cd "$DEST" || exit 1
    "$shell_bin" -i </dev/tty >/dev/tty 2>&1 || true
  else
    warn "LUMINARIS_OPEN_SHELL=1 tetapi /dev/tty tidak tersedia"
  fi
fi
