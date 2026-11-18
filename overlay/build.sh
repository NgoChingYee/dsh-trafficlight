#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Swift toolchain workaround
# ----------------------------
# On this Mac the default SDK symlink (MacOSX.sdk -> MacOSX26.2.sdk) was built
# with swiftlang-6.2.3, while the active `swift` compiler is 6.2.4, so SwiftPM
# fails with "this SDK is not supported by this compiler". The bundled
# MacOSX15.4.sdk is built with Swift 6.1, which the 6.2.4 compiler accepts, so
# we build against it by default. Override with `DSH_TL_OVERLAY_SDKROOT`.
#   DSH_TL_OVERLAY_SDKROOT=/path/to/sdk bash build.sh
if [ -n "${DSH_TL_OVERLAY_SDKROOT:-}" ]; then
  SDKROOT="$DSH_TL_OVERLAY_SDKROOT"
else
  SDKROOT="${SDKROOT:-}"
fi
if [ -z "$SDKROOT" ]; then
  ALT="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
  if [ -d "$ALT" ]; then
    echo "Overlay: using macOS 15.4 SDK ($ALT) to avoid the local toolchain mismatch."
    SDKROOT="$ALT"
  fi
fi
export SDKROOT

echo "Building TrafficLightOverlay (release)…"
if [ -n "$SDKROOT" ]; then
  echo "  SDKROOT=$SDKROOT"
fi
# --disable-sandbox: SwiftPM's built-in sandbox conflicts with the shell
# sandbox wrapper on some setups ("sandbox-exec: sandbox_apply: Operation not permitted").
swift build -c release --disable-sandbox
echo
echo "Build complete. Run with:"
echo "  ./.build/release/TrafficLightOverlay"
echo
echo "Tip: start the dsh bridge (dsh-trafficlight plugin) or the mock bridge first:"
echo "  node ../mock-bridge.mjs"