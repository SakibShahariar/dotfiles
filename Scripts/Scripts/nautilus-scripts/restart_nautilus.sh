#!/usr/bin/env bash
# restart_nautilus.sh — safe restart for Nautilus (no notification)

# Quit Nautilus quietly
nautilus -q 2>/dev/null || true

# short pause
sleep 0.5

# Launch new instance in background
nohup nautilus >/dev/null 2>&1 &
