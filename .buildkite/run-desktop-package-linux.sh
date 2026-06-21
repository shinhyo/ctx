#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

unset APPDIR
unset APPIMAGE
unset GIO_EXTRA_MODULES
unset GST_PLUGIN_PATH
unset GTK_PATH
unset LD_LIBRARY_PATH
unset XDG_DATA_DIRS

"${SCRIPT_DIR}/prepare-desktop-package.sh" x86_64
