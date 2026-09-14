#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 /path/Clipmori.dmg keychain-profile" >&2
    exit 1
fi
dmg="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
profile="$2"
[[ -f "$dmg" && "$dmg" == *.dmg ]] || { echo "Expected an existing DMG." >&2; exit 1; }
codesign --verify --strict "$dmg"
# Credentials stay in Keychain. Save the submission ID even when Apple is still processing.
result="${dmg%.dmg}.notary.json"
[[ ! -e "$result" ]] || { echo "Submission record exists. Resume with notarytool info/wait; do not submit twice." >&2; exit 1; }
xcrun notarytool submit "$dmg" --keychain-profile "$profile" --output-format json > "$result"
submission_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$result")"
echo "Submission: $submission_id (saved in $result)"
xcrun notarytool wait "$submission_id" --keychain-profile "$profile" --timeout 20m --output-format json > "${dmg%.dmg}.notary-status.json"
python3 - "${dmg%.dmg}.notary-status.json" <<'PY'
import json, sys
status = json.load(open(sys.argv[1]))
if status.get('status') != 'Accepted':
    raise SystemExit('Notarization was not accepted. Retrieve the log with notarytool log before proceeding.')
PY
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
(cd "$(dirname "$dmg")" && shasum -a 256 "$(basename "$dmg")" > SHA256SUMS)
echo "Notarized and stapled: $dmg"
