# Stellar batch / CoinJoin (Soroban testnet)

Soroban CoinJoin-enabled batch contract with snapshot-driven tests and a live testnet deployment.

## Layout
- `batch/`: Rust contract, tests, and snapshots.
- `tests/`: Shell helpers for contract init/query and CoinJoin monitoring.
- `TESTING_GUIDE.md`: Quick testnet walkthrough (manual flow).
- `batch/COINJOIN_TESTING_GUIDE.md`: Detailed guide.

## Build
```bash
cd stellar/batch
cargo build --target wasm32-unknown-unknown --release
```
Output: `target/wasm32-unknown-unknown/release/soroswap_batch.wasm`.

## Current testnet deployment
- Contract ID: `CCPGOQUHEPXSGX7B73CG2EY74ZC7JMRKSKZJPDVHMTUUNQM3HJJJC5OP`
- Network: `testnet` (`https://soroban-testnet.stellar.org`)
- Deployer identity (local CLI): `test-deployer`

Deploy command (reference):
```bash
stellar contract deploy \
  --wasm target/wasm32-unknown-unknown/release/soroswap_batch.wasm \
  --network testnet \
  --source test-deployer
```
Explorer: https://stellar.expert/explorer/testnet/contract/CCPGOQUHEPXSGX7B73CG2EY74ZC7JMRKSKZJPDVHMTUUNQM3HJJJC5OP

## Tests
```bash
cd stellar/batch
cargo test
```
Snapshot expectations live under `batch/test_snapshots/`; update only when intentionally changing behavior.

## Quick live check (read-only)
```bash
cd stellar
tests/testnet_sanity.sh
```
Calls `is_coinjoin_enabled` on the deployed contract; expects `false` on a fresh deploy.

## Notes
- Shell scripts in `stellar/tests/` mirror Solana helpers for consistency.
- No secrets committed; CLI identities are assumed to be configured locally.
