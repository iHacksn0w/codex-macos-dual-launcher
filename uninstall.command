#!/bin/zsh
SCRIPT_DIR="${0:A:h}"
exec "$SCRIPT_DIR/scripts/uninstall.command" "$@"
