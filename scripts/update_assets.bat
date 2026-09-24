@echo off
echo Downloading and extracting assets from Google Drive... Please wait.

:: Create the virtual environment to avoid the externally-managed-environment error
python -m venv .venv

:: Activate it and install the requirement quietly
call .venv\Scripts\activate.bat
pip install --upgrade gdown --quiet

:: Run the python script we created earlier
python setup_assets.py

echo.
echo Asset setup complete! You can close this window.
pause
