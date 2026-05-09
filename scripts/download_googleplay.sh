#!/usr/bin/env bash
set -euo pipefail

# Usage: download_googleplay.sh --package <name> --arch <arm64|armv7> --merge <true|false> --output <dir>

PACKAGE=""
ARCH="arm64"
MERGE="true"
OUTPUT_DIR="."

while [[ $# -gt 0 ]]; do
  case "$1" in
  --package)
    PACKAGE="$2"
    shift 2
    ;;
  --arch)
    ARCH="$2"
    shift 2
    ;;
  --merge)
    MERGE="$2"
    shift 2
    ;;
  --output)
    OUTPUT_DIR="$2"
    shift 2
    ;;
  *)
    echo "Unknown option: $1"
    exit 1
    ;;
  esac
done

if [[ -z "$PACKAGE" ]]; then
  echo "Error: --package is required"
  exit 1
fi

# Install dependencies if not present (assume runner has apt)
sudo apt-get update -qq
sudo apt-get install -y -qq openjdk-17-jre-headless apksigner

# Clone the downloader tool (idempotent, remove if exists)
if [[ -d gplay-apk-downloader ]]; then
  rm -rf gplay-apk-downloader
fi
git clone https://github.com/alltechdev/gplay-apk-downloader.git
cd gplay-apk-downloader
./setup.sh

# Authenticate (non-interactive)
echo "y" | ./gplay auth

# Download
mkdir -p "$OUTPUT_DIR"
CMD="./gplay download $PACKAGE -a $ARCH -o $OUTPUT_DIR"
if [[ "$MERGE" == "true" ]]; then
  CMD="$CMD -m"
fi
$CMD

# Clean up
cd ..
rm -rf gplay-apk-downloader

echo "Download completed. Files saved to $OUTPUT_DIR"
