#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
source "$project_root/scripts/macos-signing.sh"
export CLANG_MODULE_CACHE_PATH="$project_root/macos/.build/clang-cache"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/leon-signing-checks.XXXXXX")"
cleanup() {
    for keychain in "$test_dir"/leon-signing-check-*.keychain-db; do
        if [ -e "$keychain" ]; then security delete-keychain "$keychain" >/dev/null 2>&1 || true; fi
    done
    rm -rf "$test_dir"
}
trap cleanup EXIT
fixture_source="$project_root/macos/Tests/KeychainSigningChecks.swift"
swiftc -suppress-warnings -target arm64-apple-macosx13.0 "$fixture_source" -o "$test_dir/original"
swiftc -suppress-warnings -target arm64-apple-macosx13.0 -D UPDATE_BUILD "$fixture_source" -o "$test_dir/updated"

# Negative control: a different ad-hoc build must fail instead of showing UI.
codesign --force --sign - --identifier com.leon.tests.keychain-signing "$test_dir/original"
codesign --force --sign - --identifier com.leon.tests.keychain-signing "$test_dir/updated"
"$test_dir/original" create "$test_dir/leon-signing-check-adhoc.keychain-db"
"$test_dir/original" read "$test_dir/leon-signing-check-adhoc.keychain-db"
if "$test_dir/updated" read "$test_dir/leon-signing-check-adhoc.keychain-db"; then
    echo "FAIL: the negative control did not detect the changed code identity." >&2
    exit 1
fi
echo "PASS: negative control caught per-build keychain authorization"

# The same change must succeed with the stable Apple Team ID.
for binary in "$test_dir/original" "$test_dir/updated"; do
    codesign --force --sign "$leon_macos_signing_identity" --identifier com.leon.tests.keychain-signing "$binary"
    leon_verify_macos_signing "$binary"
done
original_hash="$(codesign -d --verbose=4 "$test_dir/original" 2>&1 | sed -n 's/^CDHash=//p')"
updated_hash="$(codesign -d --verbose=4 "$test_dir/updated" 2>&1 | sed -n 's/^CDHash=//p')"
if [ -z "$original_hash" ] || [ -z "$updated_hash" ] || [ "$original_hash" = "$updated_hash" ]; then
    echo "FAIL: expected two different signed builds." >&2
    exit 1
fi
"$test_dir/original" create "$test_dir/leon-signing-check-apple.keychain-db"
"$test_dir/updated" read "$test_dir/leon-signing-check-apple.keychain-db"
"$test_dir/updated" read "$test_dir/leon-signing-check-apple.keychain-db"
echo "PASS: changed build and repeat launch retained keychain access with the same Apple Team ID"
