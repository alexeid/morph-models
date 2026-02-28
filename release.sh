#!/bin/bash
#
# Build and package MM (morph-models) for BEAST 2.8 Package Manager.
#
# Usage:
#   ./release.sh              # build + package ZIP
#   ./release.sh --release    # also create GitHub release on alexeid/morph-models
#
set -euo pipefail

# Extract version and package name from version.xml
VERSION=$(sed -n "s/.*version='\([^']*\)'.*/\1/p" version.xml)
PKG_NAME=$(sed -n "s/.*name='\([^']*\)'.*/\1/p" version.xml)
ZIP_NAME="${PKG_NAME}.v${VERSION}.zip"

echo "=== Building ${PKG_NAME} v${VERSION} ==="

# Step 1: Maven build
mvn clean package -DskipTests

# Step 2: Assemble package directory (flat, no wrapper)
STAGING=$(mktemp -d)
trap "rm -rf $STAGING" EXIT

mkdir -p "$STAGING/lib" "$STAGING/fxtemplates" "$STAGING/examples/nexus"

# JARs
cp beast-morph-models/target/beast-morph-models-*-SNAPSHOT.jar "$STAGING/lib/"
cp beast-morph-models-fx/target/beast-morph-models-fx-*-SNAPSHOT.jar "$STAGING/lib/"

# version.xml
cp version.xml "$STAGING/"

# BEAUti template
cp beast-morph-models-fx/src/main/resources/fxtemplates/morph-models.xml "$STAGING/fxtemplates/"

# Examples (excluding legacy-2.7/)
cp examples/M3982.xml "$STAGING/examples/"
cp examples/nexus/*.nex "$STAGING/examples/nexus/"

# Step 3: Create ZIP from contents (flat structure, no wrapper directory)
rm -f "$ZIP_NAME"
(cd "$STAGING" && zip -r - .) > "$ZIP_NAME"

echo ""
echo "=== Package built: ${ZIP_NAME} ==="
unzip -l "$ZIP_NAME"

# Step 4: Optionally create GitHub release
if [[ "${1:-}" == "--release" ]]; then
    echo ""
    echo "=== Creating GitHub release v${VERSION} ==="
    gh release create "v${VERSION}" "$ZIP_NAME" \
        --repo alexeid/morph-models \
        --title "${PKG_NAME} v${VERSION}" \
        --notes "Lewis MK/MKv substitution models for BEAST 2.8"
    echo "Done: https://github.com/alexeid/morph-models/releases/tag/v${VERSION}"
fi
