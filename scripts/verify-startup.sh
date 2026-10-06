#!/bin/bash
set -euo pipefail

app_binary="${1:-dist/QuotaBar.app/Contents/MacOS/QuotaBar}"
marker_directory="$(mktemp -d "${TMPDIR:-/tmp}/quotabar-startup.XXXXXX")"
marker="$marker_directory/ready"
mkdir -p dist
"$app_binary" --verify-startup "$marker" --verify-window-lifecycle > dist/startup.log 2>&1 &
app_process=$!
cleanup() {
    kill "$app_process" 2>/dev/null || true
    wait "$app_process" 2>/dev/null || true
    rm -rf "$marker_directory"
}
trap cleanup EXIT

# The app services main-actor work, closes its dashboard, confirms that the
# monitoring clock keeps advancing without it, then reopens the dashboard.
# Being alive alone cannot pass.
for attempt in {1..300}; do
    [[ -s "$marker" ]] && break
    if ! kill -0 "$app_process" 2>/dev/null; then
        cat dist/startup.log
        echo 'QuotaBar exited before startup became responsive.' >&2
        exit 1
    fi
    sleep 0.2
done
if [[ ! -s "$marker" ]] || [[ "$(cat "$marker")" != ready ]]; then
    /usr/bin/sample "$app_process" 5 -file dist/startup-sample.txt || true
    cat dist/startup.log
    echo 'QuotaBar did not service the main thread within 60 seconds.' >&2
    exit 1
fi
cat dist/startup.log
