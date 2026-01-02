# Soroswap Batch (Soroban) — Testnet Deployment

Concise notes for the Soroban CoinJoin batch contract.

## Build
```bash
cargo build --target wasm32-unknown-unknown --release
```
Outputs: `target/wasm32-unknown-unknown/release/soroswap_batch.wasm`.

## Current Testnet Deployment
- Contract ID: `CCPGOQUHEPXSGX7B73CG2EY74ZC7JMRKSKZJPDVHMTUUNQM3HJJJC5OP`
- Deployer identity: `test-deployer` (configured in `stellar keys`)
- Network: `testnet` (`https://soroban-testnet.stellar.org`)

Deployment command used:
```bash
stellar contract deploy \
  --wasm target/wasm32-unknown-unknown/release/soroswap_batch.wasm \
  --network testnet \
  --source test-deployer
```
Explorer: https://stellar.expert/explorer/testnet/contract/CCPGOQUHEPXSGX7B73CG2EY74ZC7JMRKSKZJPDVHMTUUNQM3HJJJC5OP

## Quick Live Check
Read-only sanity against the deployed contract (uses `is_coinjoin_enabled`, no state changes):
```bash
tests/testnet_sanity.sh
```
Expected output includes `is_coinjoin_enabled -> false` on a fresh deployment.

## Notes
- Uses `stellar` CLI identities already configured locally (no secrets committed).
- The long walkthrough remains in `COINJOIN_TESTING_GUIDE.md`; this README is the deployment cheat-sheet.
