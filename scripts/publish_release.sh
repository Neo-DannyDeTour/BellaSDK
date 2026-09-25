#!/bin/bash

# Ensure a version tag is provided when running the script
if [ -z "$1" ]; then
  echo "Error: No version tag provided."
  echo "Usage: ./publish_release.sh <version-tag>"
  echo "Example: ./publish_release.sh v1.0.2"
  exit 1
fi

VERSION=$1
REPO="Neo-DannyDeTour/BellaSDK"
GDRIVE_FOLDER="https://drive.google.com/drive/folders/1EIplMuRXGZBpfP5XdidS_mtlFUrvjh8J?usp=drive_link"

# Navigate to the Desktop where the exported folders are located
cd ~/Desktop || exit

echo "Packaging BellaSDK for Linux..."
zip -r "BellaSDK_Linux_${VERSION}.zip" BellaSDK_Linux/ -q

echo "Packaging BellaSDK for Windows..."
zip -r "BellaSDK_Windows_${VERSION}.zip" BellaSDK_Windows/ -q

echo "Generating changelog and placing Google Drive download at the bottom..."

# 1. Fetch GitHub's auto-generated release notes body
AUTO_NOTES=$(gh api "repos/${REPO}/releases/generate-notes" -f tag_name="$VERSION" --jq .body 2>/dev/null || echo "")

# 2. Define the button / banner for the bottom
BOTTOM_BANNER="

---

### 📦 Full Project Download (>4GB)
[![Download from Google Drive](https://img.shields.io/badge/Google_Drive-Download_Full_Project-blue?style=for-the-badge&logo=googledrive&logoColor=white)](${GDRIVE_FOLDER})

> Need the uncompressed project files or daily snapshots? Access the complete assets repository directly via the link above."

# 3. Combine them together
FULL_RELEASE_NOTES="${AUTO_NOTES}${BOTTOM_BANNER}"

echo "Uploading to GitHub Releases..."
gh release create "$VERSION" "BellaSDK_Linux_${VERSION}.zip" "BellaSDK_Windows_${VERSION}.zip" \
  --repo "$REPO" \
  --title "Release $VERSION" \
  --notes "$FULL_RELEASE_NOTES"

echo "Cleaning up local zip archives..."
rm "BellaSDK_Linux_${VERSION}.zip" "BellaSDK_Windows_${VERSION}.zip"

echo "Success! $VERSION is live with the download button at the bottom."
