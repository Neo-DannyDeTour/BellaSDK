#!/bin/bash

# Ensure a version tag is provided when running the script
if [ -z "$1" ]; then
  echo "Error: No version tag provided."
  echo "Usage: ./publish_release.sh <version-tag>"
  echo "Example: ./publish_release.sh v1.0.2"
  exit 1
fi

VERSION=$1
REPO="UnrealDanny/BellaSDK"

# Navigate to the Desktop where the exported folders are located
cd ~/Desktop || exit

echo "Packaging BellaSDK for Linux..."
zip -r "BellaSDK_Linux_${VERSION}.zip" BellaSDK_Linux/ -q

echo "Packaging BellaSDK for Windows..."
zip -r "BellaSDK_Windows_${VERSION}.zip" BellaSDK_Windows/ -q

echo "Uploading to GitHub Releases..."
# This command creates the release, attaches the zipped binaries, and generates the notes automatically
gh release create "$VERSION" "BellaSDK_Linux_${VERSION}.zip" "BellaSDK_Windows_${VERSION}.zip" \
  --repo "$REPO" \
  --title "Release $VERSION" \
  --generate-notes

echo "Cleaning up local zip archives..."
rm "BellaSDK_Linux_${VERSION}.zip" "BellaSDK_Windows_${VERSION}.zip"

echo "Success! $VERSION is now live."
