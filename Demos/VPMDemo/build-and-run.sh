#!/bin/sh
#
# Build the VTG Page Mode demo window and open it.
#
#   sh build-and-run.sh                 build and run the bundled script
#   sh build-and-run.sh --build         build only
#   sh build-and-run.sh --command CMD   run CMD in the window instead
#
# Built by Xcode from project.yml, never `swift build`: the app carries
# SwiftTerm's resource bundle, and `swift build`'s Bundle.module accessor
# only finds one beside the .app root or at this Mac's absolute build path.

set -eu

case "$(uname -s)" in
    Darwin) ;;
    *)
        echo "The VPM demo window is a Mac app; the GL host is the Linux path." >&2
        exit 1
        ;;
esac

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$PROJECT_DIR"

command -v xcodegen >/dev/null 2>&1 || {
    echo "error: xcodegen is required (brew install xcodegen)" >&2
    exit 1
}

# Output goes to $DERIVED_DATA, never the source tree.
DERIVED_DATA=${DERIVED_DATA:-$HOME/tmp/VPMDemo/DerivedData}
xcodegen generate --quiet
/usr/bin/xcodebuild build -project VPMDemo.xcodeproj -scheme VPMDemo \
    -configuration Release -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$DERIVED_DATA" \
    SYMROOT="$DERIVED_DATA/Build/Products" \
    OBJROOT="$DERIVED_DATA/Build/Intermediates.noindex" \
    -skipMacroValidation -skipPackagePluginValidation \
    CODE_SIGNING_ALLOWED=NO -quiet

APP="$DERIVED_DATA/Build/Products/Release/VPMDemo.app"

case "${1:---run}" in
    --build) echo "$APP" ;;
    --run) open "$APP" ;;
    --command)
        [ $# -ge 2 ] || { echo "usage: $0 --command <program>" >&2; exit 2; }
        exec "$APP/Contents/MacOS/VPMDemo" --command "$2"
        ;;
    *)
        echo "usage: $0 [--run|--build|--command <program>]" >&2
        exit 2
        ;;
esac
