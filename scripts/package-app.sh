#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/.build/app}"
APP_NAME="${APP_NAME:-Interless}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-dev.interless.app}"
BUNDLE_VERSION="${BUNDLE_VERSION:-0.1.0}"
BUNDLE_BUILD="${BUNDLE_BUILD:-1}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SKIP_SIGN="${SKIP_SIGN:-0}"
BUILD_SYSTEM="${BUILD_SYSTEM:-xcodebuild}"

APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
TEMPLATE_PLIST="$ROOT_DIR/Resources/AppBundle/Info.plist"
ENTITLEMENTS="$ROOT_DIR/Resources/AppBundle/Interless.entitlements"
EXECUTABLE="$ROOT_DIR/.build/$CONFIGURATION/$APP_NAME"
XCODE_PRODUCTS_ROOT="$ROOT_DIR/.build/xcode-products"

build_with_swiftpm() {
  swift build -c "$CONFIGURATION" --product "$APP_NAME" --package-path "$ROOT_DIR"
  EXECUTABLE="$ROOT_DIR/.build/$CONFIGURATION/$APP_NAME"
  RESOURCE_BUILD_DIR="$ROOT_DIR/.build/$CONFIGURATION"
}

build_with_xcodebuild() {
  local xcode_config
  case "$CONFIGURATION" in
    release|Release) xcode_config="Release" ;;
    debug|Debug) xcode_config="Debug" ;;
    *) xcode_config="$CONFIGURATION" ;;
  esac
  local xcode_products_dir="$XCODE_PRODUCTS_ROOT/$xcode_config"
  rm -rf "$xcode_products_dir"
  xcodebuild build \
    -scheme "$APP_NAME" \
    -destination 'platform=macOS,arch=arm64' \
    -configuration "$xcode_config" \
    -derivedDataPath "$ROOT_DIR/.build/xcode-derived" \
    -skipMacroValidation \
    SYMROOT="$XCODE_PRODUCTS_ROOT" \
    OBJROOT="$ROOT_DIR/.build/xcode-objects"
  EXECUTABLE="$xcode_products_dir/$APP_NAME"
  RESOURCE_BUILD_DIR="$xcode_products_dir"
}

echo "==> Building $APP_NAME ($CONFIGURATION via $BUILD_SYSTEM)"
case "$BUILD_SYSTEM" in
  swiftpm)
    build_with_swiftpm
    ;;
  xcodebuild)
    build_with_xcodebuild
    ;;
  *)
    echo "Unsupported BUILD_SYSTEM='$BUILD_SYSTEM' (expected xcodebuild or swiftpm)" >&2
    exit 2
    ;;
esac

echo "==> Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$EXECUTABLE" "$MACOS_DIR/$APP_NAME"
chmod 755 "$MACOS_DIR/$APP_NAME"

sed \
  -e "s|\$(BUNDLE_IDENTIFIER)|$BUNDLE_IDENTIFIER|g" \
  -e "s|\$(BUNDLE_VERSION)|$BUNDLE_VERSION|g" \
  -e "s|\$(BUNDLE_BUILD)|$BUNDLE_BUILD|g" \
  "$TEMPLATE_PLIST" > "$CONTENTS_DIR/Info.plist"

cp "$ROOT_DIR/Resources/AppBundle/AppIcon.svg" "$RESOURCES_DIR/AppIcon.svg"

if compgen -G "$RESOURCE_BUILD_DIR/*.bundle" >/dev/null; then
  echo "==> Copying SwiftPM resource bundles"
  find "$RESOURCE_BUILD_DIR" -maxdepth 1 -type d -name '*.bundle' -exec cp -R {} "$RESOURCES_DIR/" \;
fi

if compgen -G "$RESOURCE_BUILD_DIR/*.metallib" >/dev/null; then
  echo "==> Copying colocated Metal libraries"
  find "$RESOURCE_BUILD_DIR" -maxdepth 1 -type f -name '*.metallib' -exec cp {} "$MACOS_DIR/" \;
fi

plutil -lint "$CONTENTS_DIR/Info.plist" >/dev/null
test -x "$MACOS_DIR/$APP_NAME"
test -f "$RESOURCES_DIR/AppIcon.svg"

if [[ "$SKIP_SIGN" != "1" ]]; then
  echo "==> Signing with identity '$SIGN_IDENTITY'"
  codesign --force --sign "$SIGN_IDENTITY" --entitlements "$ENTITLEMENTS" "$APP_DIR"
else
  echo "==> Skipping codesign"
fi

echo "Packaged: $APP_DIR"
