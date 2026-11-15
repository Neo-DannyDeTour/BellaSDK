#!/bin/bash
set -euo pipefail

gdformat --check .
gdlint .
