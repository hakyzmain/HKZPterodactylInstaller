#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/wings-heal.sh"

CONFIGS_DIR="$(dirname "${BASH_SOURCE[0]}")/../configs"
export CONFIGS_DIR

[ -z "${OS:-}" ] && detect_os
hkz_wings_heal "$CONFIGS_DIR"
