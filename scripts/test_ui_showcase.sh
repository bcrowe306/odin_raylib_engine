#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Automated UI Showcase Test & Screenshot Capture Script
# ==============================================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "================================================================="
echo " Building and Running UI Showcase End-to-End Test Suite..."
echo "================================================================="

# 1. Ensure screenshot directory exists
mkdir -p ui_screenshots

# 2. Build the showcase binary
echo "Compiling ui_showcase..."
odin build ui -out:ui_showcase

# 3. Run the automated test hook in headless mode
echo "Running automated input injection & screenshot capture..."
./ui_showcase --headless

# 4. Clean up temporary binary
rm -f ui_showcase

echo "================================================================="
echo " UI Showcase E2E Verification Complete!"
echo " Screenshots captured in: ui_screenshots/"
ls -lh ui_screenshots/*.png
echo "================================================================="
