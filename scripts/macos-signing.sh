#!/bin/bash
# Shared by the release build and the isolated keychain upgrade check.
leon_macos_signing_identity="${LEON_CODESIGN_IDENTITY:-Apple Development}"
leon_macos_signing_team="${LEON_CODESIGN_TEAM_ID:-G5QN8N2P72}"

if [ -z "$leon_macos_signing_identity" ] || [ "$leon_macos_signing_identity" = "-" ]; then
    echo "An Apple-issued signing identity with a stable Team ID is required." >&2
    exit 1
fi
if [[ ! "$leon_macos_signing_team" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "LEON_CODESIGN_TEAM_ID must be a 10-character Apple Team ID." >&2
    exit 1
fi

leon_verify_macos_signing() {
    local target="$1"
    # Match the Mac developer / Developer ID / Mac distribution certificate
    # classes recognized by securityd for a stable teamid: keychain partition.
    local requirement="anchor apple generic and certificate leaf[subject.OU] = \"$leon_macos_signing_team\" and ((certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists) or (certificate 1[field.1.2.840.113635.100.6.2.1] exists and (certificate leaf[field.1.2.840.113635.100.6.1.12] exists or certificate leaf[field.1.2.840.113635.100.6.1.7] exists)))"
    codesign --verify --deep --strict -R "=$requirement" "$target" || return 1
    local metadata actual_team
    metadata="$(codesign -d --verbose=2 "$target" 2>&1)" || return 1
    actual_team="$(sed -n 's/^TeamIdentifier=//p' <<< "$metadata")"
    if [ "$actual_team" != "$leon_macos_signing_team" ]; then
        echo "Unexpected signing Team ID: $actual_team (expected $leon_macos_signing_team)." >&2
        return 1
    fi
    printf 'Verified Apple signing Team ID: %s\n' "$actual_team"
}
