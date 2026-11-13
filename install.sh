#!/data/data/com.termux/files/usr/bin/bash

echo "🚀 [1/5] Memperbarui repositori Termux..."
pkg update -y

echo "📦 [2/5] Menginstal dependensi sistem..."
# libvips otomatis menarik libcairo, pango, libpng, dll.
pkg install -y python build-essential pkg-config libvips git

echo "🧹 [3/5] Membersihkan cache..."
rm -rf node_modules package-lock.json bun.lockb ~/.npm/_cacache ~/.bun/install/cache

echo "⚙️ [4/5] Mengatur environment variables..."
export PYTHON=$(command -v python)
export CC=$(command -v clang)
export CXX=$(command -v clang++)

echo "📥 [5/5] Menginstal dependensi npm..."
npm install
npm install @img/sharp-wasm32

echo "✅ Selesai! Jalankan dengan: node index.js"