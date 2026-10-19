#!/bin/bash
# ============================================================
# DIY Part 1 - Executed BEFORE feeds update
# JDCloud Arthur (RE-SS-01) - based on ZN-M2 v4
# Remove problematic feeds that break `make defconfig`
# ============================================================

set -e

echo "============================================"
echo " DIY Part 1: Pruning feeds (Arthur)"
echo "============================================"

# Same as ZN-M2 v4: feeds/video has qt5 recursive dependency that breaks
# `make defconfig`. Not needed for this build.
if [ -f "feeds.conf.default" ]; then
    sed -i '/\/video/d' feeds.conf.default
    echo "  -> removed video feed from feeds.conf.default"
else
    echo "  -> WARNING: feeds.conf.default not found!"
fi

echo "DIY Part 1 completed."
