# CoinJoin Quick Testing Guide (Soroban Testnet)

This is a concise guide for the current minimal CoinJoin-enabled batch contract.

## Contract / Network
- Contract ID: `CCPGOQUHEPXSGX7B73CG2EY74ZC7JMRKSKZJPDVHMTUUNQM3HJJJC5OP`
- Network: `testnet` (`https://soroban-testnet.stellar.org`)
- Deployer identity (local): `test-deployer`

## Build & Deploy (reference)
```bash
cargo build --target wasm32-unknown-unknown --release
stellar contract deploy \
  --wasm target/wasm32-unknown-unknown/release/soroswap_batch.wasm \
  --network testnet \
  --source test-deployer
```

## Read-Only Sanity Check
Uses the deployed contract, no state changes:
```bash
tests/testnet_sanity.sh
```
Expected: prints `false` (CoinJoin disabled by default).

## Core Methods
- `private_swap(token_in, token_out, amount_in, min_amount_out, user_address, receiving_address)`  
  Deposit into the CoinJoin pool for a fixed denomination; user supplies a fresh receiving address.
- `execute_coinjoin_mixing(denomination_symbol, max_deposits?)`  
  Trigger mixing when the pool has enough deposits (fixed denominations: `"10"`, `"100"`, `"1K"`, `"10K"`).
- `get_coinjoin_stats(denomination_symbol)`  
  Returns `(current_pool_size, current_fees, estimated_wait_time)`.
- `get_deposit_details(denomination_symbol, index)`  
  Returns privacy-safe deposit metadata for monitoring.

## Minimal Manual Flow (testnet)
Replace `$USER` and `$RECEIVER` with your identities/addresses.
```bash
# Deposit to the 1 XLM pool (10 stroop denom symbol = "10")
stellar contract invoke \
  --id CCPGOQUHEPXSGX7B73CG2EY74ZC7JMRKSKZJPDVHMTUUNQM3HJJJC5OP \
  --network testnet \
  --source $USER \
  -- \
  private_swap \
  --token_in $TOKEN \
  --token_out $TOKEN \
  --amount_in 10000000 \
  --min_amount_out 9900000 \
  --user_address $USER_ADDRESS \
  --receiving_address $RECEIVER

# Check pool
stellar contract invoke \
  --id CCPGOQUHEPXSGX7B73CG2EY74ZC7JMRKSKZJPDVHMTUUNQM3HJJJC5OP \
  --network testnet \
  --source $USER \
  -- \
  get_coinjoin_stats \
  --denomination_symbol "10"

# Trigger mixing (when enough deposits exist)
stellar contract invoke \
  --id CCPGOQUHEPXSGX7B73CG2EY74ZC7JMRKSKZJPDVHMTUUNQM3HJJJC5OP \
  --network testnet \
  --source $USER \
  -- \
  execute_coinjoin_mixing \
  --denomination_symbol "10" \
  --max_deposits 3
```

## Notes / Best Practices
- Use fresh receiving addresses per deposit for privacy.
- Stick to the fixed denominations; mismatched amounts will fail.
- Verify pool size via `get_coinjoin_stats` before triggering mixing.
- Test with small amounts first.
