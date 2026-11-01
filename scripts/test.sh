#!/bin/sh
# Command Line Tools intermittently fail to find the Swift Testing macro plugin
# ("plugin for module 'TestingMacros' not found"); pointing at it explicitly is reliable.
set -e
cd "$(dirname "$0")/.."
PLUGINS="$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins/testing"
exec swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS" "$@"
