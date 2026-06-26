#!/usr/bin/env bash
# Quick iteration: build + launch the window directly (no bundle).
set -euo pipefail
cd "$(dirname "$0")"
exec swift run Runway
