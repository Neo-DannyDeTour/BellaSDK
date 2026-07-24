import os
import zipfile
import sys

def download_and_extract_assets():
    print("Initializing asset download process...")

    try:
        import gdown
        print("gdown module found. Preparing to connect to Google Drive...")
    except ImportError:
        print("Error: gdown is not installed. Please run the virtual environment setup commands first.")
        sys.exit(1)

    ## Google Drive unique identifier for the compressed assets file to be downloaded.
    FILE_ID = '1vcstZwhslYQTzJSyN8dDWfom2kpeA76t'

    ## The local filename where the downloaded Google Drive zip archive will be temporarily saved.
    DESTINATION = 'assets.zip'

    print(f"Downloading assets (ID: {FILE_ID}) from Google Drive...")

    # Constructing the full URL and using fuzzy=True makes gdown more resilient
    url = f'https://drive.google.com/uc?id={FILE_ID}'
    gdown.download(url=url, output=DESTINATION, quiet=False, fuzzy=True)

    if os.path.exists(DESTINATION):
        print(f"Download successful. Extracting {DESTINATION} into the project directory...")
        with zipfile.ZipFile(DESTINATION, 'r') as zip_ref:
            zip_ref.extractall()

        print(f"Extraction complete. Deleting the temporary {DESTINATION} file to save space...")
        os.remove(DESTINATION)
        print("Assets folder is fully set up and ready!")
    else:
        print("Error: The download failed and the archive was not found.")

if __name__ == '__main__':
    download_and_extract_assets()
