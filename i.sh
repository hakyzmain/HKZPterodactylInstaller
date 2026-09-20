#!/bin/bash
set -e
curl -fsSL -o /tmp/phkz-run.sh "https://raw.githubusercontent.com/hakyzmain/HKZPterodactylInstaller/main/run.sh"
exec bash /tmp/phkz-run.sh "$@"
