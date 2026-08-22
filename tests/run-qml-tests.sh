#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
export PATH="$root/tests/fixtures:$PATH"
export QT_QPA_PLATFORM=${QT_QPA_PLATFORM:-offscreen}
qmltestrunner=/usr/lib/qt6/bin/qmltestrunner
[[ -x $qmltestrunner ]] || qmltestrunner=$(command -v qmltestrunner)
exec "$qmltestrunner" -input "$root/tests/qml" -import /usr/lib/qt6/qml "$@"
