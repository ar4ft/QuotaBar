#!/bin/bash
set -euo pipefail

app_binary="${1:-dist/QuotaBar.app/Contents/MacOS/QuotaBar}"
fixture_directory="$(mktemp -d "${TMPDIR:-/tmp}/quotabar-keychain-checks.XXXXXX")"
fixture="$fixture_directory/fixture.keychain-db"
app_process=""
mkdir -p dist
cleanup() {
    if [[ -n "$app_process" ]]; then
        kill "$app_process" 2>/dev/null || true
        wait "$app_process" 2>/dev/null || true
    fi
    /usr/bin/security delete-keychain "$fixture" >/dev/null 2>&1 || true
    rm -rf "$fixture_directory"
}
trap cleanup EXIT

# Public synthetic fixture values only; no user's credentials or default Keychain.
/usr/bin/security create-keychain -p quotabar-synthetic-fixture "$fixture"
/usr/bin/security add-generic-password -a synthetic -s 'QuotaBar test fixture' -w not-a-real-token "$fixture"
/usr/bin/security lock-keychain "$fixture"
"$app_binary" --verify-keychain "$fixture" > dist/keychain.log 2>&1 &
app_process=$!
for attempt in {1..200}; do
    kill -0 "$app_process" 2>/dev/null || break
    sleep 0.1
done
if kill -0 "$app_process" 2>/dev/null; then
    /usr/bin/sample "$app_process" 5 -file dist/keychain-sample.txt || true
    cat dist/keychain.log
    echo 'Noninteractive Keychain checks did not finish within 20 seconds.' >&2
    exit 1
fi
if ! wait "$app_process"; then
    cat dist/keychain.log
    exit 1
fi
cat dist/keychain.log
