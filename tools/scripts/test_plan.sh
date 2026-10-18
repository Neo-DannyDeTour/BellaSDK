#!/bin/bash
find . -name "*.gd" | grep -v "/addons/" | head -n 10 > files_to_edit.txt
echo "10 files to process:"
cat files_to_edit.txt
