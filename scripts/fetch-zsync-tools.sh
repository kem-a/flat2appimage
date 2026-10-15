#!/bin/sh
# Download zsync2 binary for bundling with AppManager
# Usage: fetch-zsync-tools.sh <arch> <output_dir>
# zsync2 is used for efficient delta updates of AppImages
#
# The zsync2 releases from AppImageCommunity are AppImage binaries.
# We extract the actual ELF binary from inside the AppImage so that it
# can be properly bundled by quick-sharun (or any other repackaging tool)
# without breaking the embedded squashfs runtime.

set -e

ARCH="${1:-x86_64}"
OUTPUT_DIR="${2:-.}"

# zsync2 releases from AppImageCommunity
ZSYNC2_REPO="AppImageCommunity/zsync2"

# Map architecture names
case "$ARCH" in
    x86_64|amd64)
        ZSYNC2_ARCH="x86_64"
        ;;
    aarch64|arm64)
        ZSYNC2_ARCH="aarch64"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"

# Check if zsync2 already exists and is executable
if [ -x "zsync2" ]; then
    echo "zsync2 already exists in $OUTPUT_DIR, skipping download"
    ls -la zsync2
    exit 0
fi

# Get the latest release asset URL using GitHub API
echo "Finding latest zsync2 release for ${ZSYNC2_ARCH}..."
ZSYNC2_URL=$(curl -s "https://api.github.com/repos/${ZSYNC2_REPO}/releases/latest" | \
    grep -o "https://github.com/${ZSYNC2_REPO}/releases/download/[^\"]*-${ZSYNC2_ARCH}.AppImage\"" | \
    head -1 | tr -d '"')

if [ -z "$ZSYNC2_URL" ]; then
    # Fallback: search in all releases
    ZSYNC2_URL=$(curl -s "https://api.github.com/repos/${ZSYNC2_REPO}/releases" | \
        grep -o "https://github.com/${ZSYNC2_REPO}/releases/download/[^\"]*-${ZSYNC2_ARCH}.AppImage\"" | \
        head -1 | tr -d '"')
fi

if [ -z "$ZSYNC2_URL" ]; then
    echo "Error: Could not find zsync2 AppImage for ${ZSYNC2_ARCH}"
    exit 1
fi

# Download zsync2 AppImage to a temporary file
echo "Downloading zsync2 from: $ZSYNC2_URL"
APPIMAGE_TMP="zsync2-tmp.AppImage"
curl -L -o "$APPIMAGE_TMP" "$ZSYNC2_URL"
chmod +x "$APPIMAGE_TMP"

# Extract the native zsync2 binary from the AppImage.
# Using --appimage-extract (works without FUSE) to get the real ELF binary
# so it can be properly rebundled by quick-sharun or similar tools.
echo "Extracting zsync2 from AppImage..."
EXTRACT_DIR="zsync2-extract"
rm -rf "$EXTRACT_DIR"

# --appimage-extract extracts to squashfs-root/ in CWD
./"$APPIMAGE_TMP" --appimage-extract >/dev/null 2>&1 || true
if [ -d "squashfs-root" ]; then
    mv "squashfs-root" "$EXTRACT_DIR"
fi

# Find the zsync2 binary inside the extracted AppImage
EXTRACTED_BIN=""
for candidate in \
    "$EXTRACT_DIR/usr/bin/zsync2" \
    "$EXTRACT_DIR/usr/local/bin/zsync2" \
    "$EXTRACT_DIR/bin/zsync2" \
    "$EXTRACT_DIR/AppRun"; do
    if [ -f "$candidate" ] && [ -x "$candidate" ]; then
        # Verify it's an actual ELF binary, not a script
        if file "$candidate" 2>/dev/null | grep -q "ELF"; then
            EXTRACTED_BIN="$candidate"
            break
        fi
    fi
done

if [ -n "$EXTRACTED_BIN" ]; then
    cp "$EXTRACTED_BIN" zsync2
    chmod +x zsync2
    echo "Extracted native zsync2 binary"

    # Also install any bundled shared libraries that aren't available on the
    # build system (e.g. OpenSSL 1.1 libs needed by zsync2).  This allows
    # quick-sharun / ldd to resolve all dependencies when repackaging.
    if command -v ldd >/dev/null 2>&1; then
        missing_libs=$(ldd zsync2 2>/dev/null | grep "not found" | awk '{print $1}' || true)
        if [ -n "$missing_libs" ]; then
            echo "Installing bundled libraries needed by zsync2..."
            mkdir -p "$OUTPUT_DIR/lib"
            for lib in $missing_libs; do
                found=$(find "$EXTRACT_DIR" -name "$lib" -type f 2>/dev/null | head -1)
                if [ -n "$found" ]; then
                    cp "$found" "$OUTPUT_DIR/lib/"
                    echo "  installed $lib to $OUTPUT_DIR/lib/"
                fi
            done
        fi
    fi
else
    # Fallback: use the AppImage directly (will work on systems with FUSE
    # but may not survive repackaging by quick-sharun)
    echo "Warning: Could not extract native binary, using AppImage directly"
    cp "$APPIMAGE_TMP" zsync2
fi

# Cleanup
rm -f "$APPIMAGE_TMP"
rm -rf "$EXTRACT_DIR"

echo "zsync2 installed to $OUTPUT_DIR"
ls -la zsync2
