#!/bin/sh
set -eu

if [ "${MODULE_HOLD:-false}" = "true" ]; then
    echo "MODULE_HOLD=true; container is sleeping for diagnostics"
    trap 'exit 0' INT TERM
    while true; do
        sleep 60 &
        wait $!
    done
fi

exec /usr/local/bin/zig_iotedge "$@"
