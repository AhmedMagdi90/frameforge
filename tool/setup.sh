#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"

if ! command -v flutter >/dev/null 2>&1; then
  echo 'Install Flutter 3.35 or newer and put flutter on PATH, then run this script again.' >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo 'Python 3 is required to install the native video engines.' >&2
  exit 1
fi

if [[ ! -d android && ! -d ios ]]; then
  scaffold_dir="$(mktemp -d)"
  trap 'rm -rf -- "$scaffold_dir"' EXIT
  flutter create --no-pub --platforms=android,ios --org dev.frameforge --project-name frameforge "$scaffold_dir/frameforge"
  cp -R "$scaffold_dir/frameforge/android" ./android
  cp -R "$scaffold_dir/frameforge/ios" ./ios
elif [[ ! -d android || ! -d ios ]]; then
  echo 'Both mobile runners are required. Restore the missing runner before continuing.' >&2
  exit 1
fi

python3 tool/install_platforms.py
flutter pub get
echo 'FrameForge is ready. Connect a device and run: flutter run'
