#!/usr/bin/env bash
# Builds FileNameChange.app into ./build -- run this on a Mac.
#
#   ./build.sh              build the app
#   ./build.sh --run        build, then open it
#   ./build.sh --install    build, then copy it to /Applications
#   ./build.sh --universal  build a fat Intel + Apple silicon binary
#   ./build.sh --dmg        build, then package a drag-to-Applications disk image
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

APP_NAME="FileNameChange"
UNIVERSAL=0
INSTALL=0
RUN=0
DMG=0

for arg in "$@"; do
  case "${arg}" in
    --universal) UNIVERSAL=1 ;;
    --install)   INSTALL=1 ;;
    --run)       RUN=1 ;;
    --dmg)       DMG=1 ;;
    -h|--help)
      # Print the contiguous header comment block (usage) and nothing else.
      awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
      exit 0
      ;;
    *)
      echo "unknown option: ${arg} (try --help)" >&2
      exit 1
      ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: this script builds a macOS app and must run on a Mac." >&2
  exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "error: swift not found. Install the Xcode Command Line Tools first:" >&2
  echo "       xcode-select --install" >&2
  exit 1
fi

ARCH_FLAGS=()
if [[ "${UNIVERSAL}" == 1 ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

echo "==> Building ${APP_NAME} (release)..."
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"
BIN="${BIN_DIR}/${APP_NAME}"

if [[ ! -x "${BIN}" ]]; then
  echo "error: built binary not found at ${BIN}" >&2
  exit 1
fi

APP="build/${APP_NAME}.app"
echo "==> Assembling ${APP}..."
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN}" "${APP}/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${APP}/Contents/Info.plist"
printf 'APPL????' > "${APP}/Contents/PkgInfo"

# App icon -- nice to have, never fatal.
if command -v iconutil >/dev/null 2>&1; then
  ICONSET="build/AppIcon.iconset"
  rm -rf "${ICONSET}"
  mkdir -p "${ICONSET}"
  if swift Scripts/make-icon.swift "${ICONSET}" >/dev/null 2>&1 &&
     iconutil -c icns "${ICONSET}" -o "${APP}/Contents/Resources/AppIcon.icns" >/dev/null 2>&1; then
    echo "==> App icon generated"
  else
    echo "==> Skipped app icon (generation failed -- the app still works fine)"
  fi
  rm -rf "${ICONSET}"
fi

codesign --force -s - "${APP}" >/dev/null 2>&1 ||
  echo "==> Note: ad-hoc code signing failed; a locally built app should still run"

echo "OK: built ${APP}"

if [[ "${DMG}" == 1 ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP}/Contents/Info.plist")"
  DMG_PATH="build/${APP_NAME}-${VERSION}.dmg"
  STAGING="build/dmg-staging"
  echo "==> Packaging ${DMG_PATH}..."
  rm -rf "${STAGING}" "${DMG_PATH}"
  mkdir -p "${STAGING}"
  cp -R "${APP}" "${STAGING}/"
  ln -s /Applications "${STAGING}/Applications"
  hdiutil create -volname "${APP_NAME}" -srcfolder "${STAGING}" -ov -format UDZO "${DMG_PATH}" >/dev/null
  rm -rf "${STAGING}"
  echo "OK: created ${DMG_PATH} (open it and drag ${APP_NAME}.app onto Applications)"
fi

if [[ "${INSTALL}" == 1 ]]; then
  rm -rf "/Applications/${APP_NAME}.app"
  cp -R "${APP}" /Applications/
  echo "OK: installed to /Applications/${APP_NAME}.app"
fi

if [[ "${RUN}" == 1 ]]; then
  open "${APP}"
fi
