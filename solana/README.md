# Solana (Anchor)

Anchor workspace targeting Solana devnet with CoinJoin-focused batch program plus minimal factory/pair stubs.

## Layout
- `programs/batch`: CoinJoin pool contract with fixed denominations and PDA vault escrow (SPL token).
- `programs/factory_stub`: simple registry of token pairs for testing.
- `programs/pair_stub`: minimal pair that holds two token vaults and can emit stub swaps.
- `tests/`: Anchor/TS placeholder; expand with real flows once devnet mints/keys are wired.

## Devnet deployments
- `batch`: `2uDexdyb8hj7R1nrR9ESEci831Urbag5Rq12TzgZEAZq`
- `factory_stub`: `uY7scRK6DgtK7Ww9udtDiny7fpyEF324C78PXHnemKP`
- `pair_stub`: `6Wq5RBNnszrhQiR5QBbgZGgHPthLAhot2miZ1qDddKci`

These IDs are synced in `Anchor.toml` and the program sources (`declare_id!`).

## Shared devnet SPL fixtures
- Mint (7 decimals): `AhNpRxSLCXxugeaTWvKbNGcmWJXGqGxDtq7KREEnYyuF`
- Mint authority: `FbA1g1Gzp5k9qnQjaC2rY1UDPiX2L3hTJVWBm9UkCVYx`
- Participants (devnet-only): `3GPP1gXYjF4MRHEkBpvUA5ZRbtLzeiWRVq1yNWoWSs55`, `E1Qvez4cJe6JgGQmzTNdcQV8iebGCsbQaPrRkD5gAWsr`
- Keypairs live in `tests/devnet.fixtures.ts`; they are meant for public testing on devnet.
- `npm run mint:devnet-spl` tops up 5 denominations (50_000_000 units) to each participant ATA and creates the mint if missing (RPC is `ANCHOR_PROVIDER_URL`/`SOLANA_RPC` or devnet).

## Devnet e2e flow
1) Install deps: `npm install`.
2) Seed SPL balances on devnet: `npm run mint:devnet-spl` (idempotent; reuses the shared mint/authority).
3) Run e2e: `npm test` (runs `anchor test --skip-local-validator`, hitting devnet; this redeploys the programs to the IDs in `Anchor.toml`).
4) If you only want to sanity-check deployments (no redeploy), run `npx ts-node tests/devnet.deploy.test.ts`.

## Build
```bash
cd solana
anchor build
```

## Test (placeholder)
```bash
npm install
npm test   # runs anchor test --skip-local-validator
```
`npm test`/`anchor test --skip-local-validator` uses the devnet cluster from `Anchor.toml`. Node 20 is recommended (`.nvmrc` included).
The suite includes:
- `tests/devnet.deploy.test.ts` — read-only check that the devnet program IDs match `Anchor.toml` and the program accounts are executable on devnet.
- `tests/coinjoin.devnet.e2e.ts` — devnet CoinJoin flow (creates a test mint/PDAs, funds dev-only keys, deposits, and executes mixing).

## Deploy (devnet)
Update `Anchor.toml` program IDs to your deployed IDs, then:
```bash
anchor deploy --provider.cluster devnet
```

Key accounts:
- `initialize_config` creates a singleton config PDA (owner=funder, factory/router passed in).
- `init_pool` sets up a denomination pool + PDA vault (associated token account for the pool PDA).
- `deposit` transfers one fixed-denomination amount from user to vault, increments counters.
- `execute_mixing` pays one denomination amount to each recipient token account provided in remaining accounts; expects participant count == current pool size.
