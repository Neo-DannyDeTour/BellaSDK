#!/bin/bash
for f in $(find . -name "*.gd" | grep -v "/addons/" | head -n 10); do
  echo "Formatting and linting $f"
  gdformat "$f"
  gdlint "$f"
done
