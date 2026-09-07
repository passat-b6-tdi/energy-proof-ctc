#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -f .env ]]; then
    echo "Missing .env. Copy .env.example to .env and fill the deployment values." >&2
    exit 1
fi

set -a
source .env
set +a

: "${SOURCE_CHAIN_RPC_URL:?SOURCE_CHAIN_RPC_URL is required}"
: "${DEPLOYER_ACCOUNT:?DEPLOYER_ACCOUNT is required}"

forge create contracts/source-chain/EnergyMeter.sol:EnergyMeter \
    --rpc-url "$SOURCE_CHAIN_RPC_URL" \
    --account "$DEPLOYER_ACCOUNT" \
    --broadcast \
    --verify \
    --verifier blockscout \
    --verifier-url "${SEPOLIA_VERIFIER_URL:-https://eth-sepolia.blockscout.com/api/}" \
    -vvv
