#!/usr/bin/env bash
# Verify a deployed contract on Arc's Blockscout.
#
#   script/verify-blockscout.sh <address> <src/File.sol:Name> [testnet|mainnet]
#
# Submits the standard-JSON input straight to the explorer's v2 API rather than
# through `arc-forge verify-contract`, whose pre-flight "getabi" call is rate
# limited (and fails the whole run) long before the verification itself is.
# The compiler in foundry.toml must be one the explorer lists
# (GET /api/v2/smart-contracts/verification/config); an unlisted one fails with
# a bare "Unable to verify".
set -euo pipefail

address=$1
target=$2
network=${3:-testnet}

case "$network" in
  testnet) explorer=https://explorer.testnet.arc.io ;;
  mainnet) explorer=https://explorer.arc.io ;;
  *) echo "network must be testnet or mainnet" >&2; exit 1 ;;
esac

solc=$(sed -n 's/^solc *= *"\(.*\)"/\1/p' foundry.toml)
[ -n "$solc" ] || { echo "pin solc in foundry.toml first" >&2; exit 1; }

input=$(mktemp)
trap 'rm -f "$input"' EXIT
arc-forge verify-contract "$address" "$target" --chain-id 1 --verifier blockscout \
  --verifier-url "$explorer/api/" --compiler-version "$solc" --show-standard-json-input 2>/dev/null >"$input"

full=$(curl -s "$explorer/api/v2/smart-contracts/verification/config" |
  python3 -c "import sys,json;print(next(v for v in json.load(sys.stdin)['solidity_compiler_versions'] if v.startswith('v$solc+')))")

curl -sf -X POST "$explorer/api/v2/smart-contracts/$address/verification/via/standard-input" \
  -F "compiler_version=$full" -F "license_type=none" -F "autodetect_constructor_args=true" \
  -F "files[0]=@$input;type=application/json"
echo

for _ in $(seq 1 24); do
  state=$(curl -s "$explorer/api/v2/smart-contracts/$address" |
    python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('is_verified'), d.get('name'))")
  case "$state" in True*) echo "verified: $state ($full)"; exit 0 ;; esac
  sleep 5
done
echo "not verified after 2 minutes: $state" >&2
exit 1
