#!/usr/bin/env bash
# Builds Lambda deployment zips into backend/build/ (Linux x86_64 wheels, Python 3.12)
set -euo pipefail
cd "$(dirname "$0")"
rm -rf build && mkdir -p build/processor build/api

pip install -r processor/requirements.txt \
  --platform manylinux2014_x86_64 --implementation cp --python-version 3.12 \
  --only-binary=:all: --target build/processor --quiet
cp processor/handler.py build/processor/
cp api/handler.py build/api/

(cd build/processor && zip -qr ../processor.zip .)
(cd build/api && zip -qr ../api.zip .)
echo "Built: build/processor.zip build/api.zip"
