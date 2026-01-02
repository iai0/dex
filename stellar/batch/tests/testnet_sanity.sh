#!/bin/bash
set -euo pipefail

# Read-only sanity check against the deployed testnet contract.

CONTRACT_ID="CCPGOQUHEPXSGX7B73CG2EY74ZC7JMRKSKZJPDVHMTUUNQM3HJJJC5OP"
NETWORK="testnet"
SOURCE_IDENTITY="test-deployer"

echo "🔎 Checking deployed Soroban batch contract on ${NETWORK}..."
echo "Contract: ${CONTRACT_ID}"

stellar contract invoke \
  --id "${CONTRACT_ID}" \
  --network "${NETWORK}" \
  --source "${SOURCE_IDENTITY}" \
  -- \
  is_coinjoin_enabled

echo "✅ Read-only check complete."
