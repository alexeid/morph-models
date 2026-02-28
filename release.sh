#!/bin/bash
#
# Build and package a BEAST 2.8 package for the BEAST Package Manager.
#
# Reads the package name and version from version.xml, builds with Maven,
# assembles the standard BEAST package ZIP, and optionally creates a
# GitHub release.
#
# Usage:
#   ./release.sh              # build + create package ZIP
#   ./release.sh --release    # also create a GitHub release with the ZIP attached
#
# The ZIP can then be submitted to CBAN (CompEvol/CBAN) by adding an entry
# to packages2.8.xml via pull request. See README.md for details.
#
set -euo pipefail

# --- Extract metadata from version.xml ---

if [[ ! -f version.xml ]]; then
    echo "ERROR: version.xml not found in $(pwd)" >&2
    exit 1
fi

# Parse only the <package> element (not <provider classname="..."> etc.)
PKG_LINE=$(grep '<package ' version.xml | head -1)
PKG_NAME=$(echo "$PKG_LINE" | sed "s/.*name=['\"]\\([^'\"]*\\)['\"].*/\\1/")
VERSION=$(echo "$PKG_LINE" | sed "s/.*version=['\"]\\([^'\"]*\\)['\"].*/\\1/")

if [[ -z "$PKG_NAME" || -z "$VERSION" ]]; then
    echo "ERROR: could not parse name/version from version.xml" >&2
    exit 1
fi

ZIP_NAME="${PKG_NAME}.v${VERSION}.zip"
GITHUB_REPO=$(git remote get-url origin 2>/dev/null \
    | sed 's|.*github.com[:/]\(.*\)\.git$|\1|; s|.*github.com[:/]\(.*\)$|\1|')

echo "=== ${PKG_NAME} v${VERSION} ==="
echo ""

# --- Step 1: Maven build ---

echo "--- Building with Maven ---"
mvn clean package -DskipTests
echo ""

# --- Step 2: Assemble BEAST package (flat ZIP structure) ---

echo "--- Assembling package ZIP ---"
STAGING=$(mktemp -d)
trap "rm -rf $STAGING" EXIT

mkdir -p "$STAGING/lib"

# version.xml (required)
cp version.xml "$STAGING/"

# Package JARs: collect from target/ (single module) or */target/ (multi-module).
# Only include the project's own JARs — BEAST core deps (beast-base, beast-pkgmgmt,
# beagle, colt, etc.) are already in the BEAST installation and must NOT be bundled.
jar_count=0
for jar in $(find . -path '*/target/*.jar' \
        -not -name '*-javadoc.jar' \
        -not -name '*-sources.jar' \
        -not -path '*/test-classes/*' \
        -not -path '*/target/lib/*' | sort); do
    cp "$jar" "$STAGING/lib/"
    jar_count=$((jar_count + 1))
done

if [[ $jar_count -eq 0 ]]; then
    echo "ERROR: no JARs found in target directories" >&2
    exit 1
fi

# fxtemplates/ (optional — check common locations)
fxtemplates_found=false
for dir in fxtemplates \
           src/main/resources/fxtemplates \
           */src/main/resources/fxtemplates; do
    if compgen -G "$dir/*.xml" > /dev/null 2>&1; then
        mkdir -p "$STAGING/fxtemplates"
        cp "$dir"/*.xml "$STAGING/fxtemplates/"
        fxtemplates_found=true
    fi
done

# examples/ (optional — check common locations)
if [[ -d examples ]]; then
    # Top-level examples dir: copy everything except legacy directories
    rsync -a --exclude='legacy*' examples/ "$STAGING/examples/"
elif [[ -d src/test/resources/examples ]]; then
    # Skeleton convention: examples in test resources
    mkdir -p "$STAGING/examples"
    cp -R src/test/resources/examples/* "$STAGING/examples/"
fi

# Create ZIP from staging contents (flat, no wrapper directory)
rm -f "$ZIP_NAME"
(cd "$STAGING" && zip -r - .) > "$ZIP_NAME"

echo ""
echo "=== Package: ${ZIP_NAME} ==="
unzip -l "$ZIP_NAME"

# --- Step 3: Optionally create GitHub release ---

if [[ "${1:-}" == "--release" ]]; then
    if [[ -z "$GITHUB_REPO" ]]; then
        echo "ERROR: could not determine GitHub repo from git remote" >&2
        exit 1
    fi

    echo ""
    echo "--- Creating GitHub release v${VERSION} on ${GITHUB_REPO} ---"
    gh release create "v${VERSION}" "$ZIP_NAME" \
        --repo "$GITHUB_REPO" \
        --title "${PKG_NAME} v${VERSION}" \
        --generate-notes

    DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}/${ZIP_NAME}"
    echo ""
    echo "=== Release created ==="
    echo "URL: https://github.com/${GITHUB_REPO}/releases/tag/v${VERSION}"
    echo ""
    echo "--- Next step: submit to CBAN ---"
    echo "Add this entry to packages2.8.xml in https://github.com/CompEvol/CBAN via pull request:"
    echo ""
    cat <<XMLEOF
    <package name="${PKG_NAME}" version="${VERSION}"
        url="${DOWNLOAD_URL}"
        projectURL="https://github.com/${GITHUB_REPO}"
        description="TODO: one-line description of your package">
        <depends on="BEAST.base" atleast="2.8.0"/>
    </package>
XMLEOF
fi
