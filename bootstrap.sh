#!/bin/bash
set -e
curl -fsSL -o /tmp/phkz-run.sh "https://raw.githubusercontent.com/hakyzmain/HKZPterodactylInstaller/main/run.sh?t=$(date +%s)"
exec bash /tmp/phkz-run.sh "$@"
