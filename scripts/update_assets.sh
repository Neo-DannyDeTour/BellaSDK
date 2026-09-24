#!/bin/bash
echo "Downloading and extracting assets from Google Drive... Please wait."

# Create the virtual environment
python3 -m venv .venv

# Activate it and install/upgrade the requirement quietly
source .venv/bin/activate
pip install --upgrade gdown --quiet

# Run the python script
python3 setup_assets.py

echo ""
echo "Asset setup complete!"
