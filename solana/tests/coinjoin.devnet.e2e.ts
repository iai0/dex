import * as anchor from "@coral-xyz/anchor";
import { Program } from "@coral-xyz/anchor";
import {
  createMint,
  getAccount,
  getAssociatedTokenAddressSync,
  getOrCreateAssociatedTokenAccount,
  mintTo,
} from "@solana/spl-token";
import { AccountMeta, PublicKey, SystemProgram } from "@solana/web3.js";
import { Batch } from "../target/types/batch";
import {
  DEVNET_DENOM,
  DEVNET_MINT_AMOUNT,
  DEVNET_MINT_AUTHORITY,
  DEVNET_MINT_DECIMALS,
  DEVNET_MINT_KEYPAIR,
  DEVNET_PARTICIPANTS,
} from "./devnet.fixtures";

const POOL_SEED = Buffer.from("pool");
const CONFIG_SEED = Buffer.from("config");
const MIN_POOL_SIZE = 3;

describe("batch coinjoin devnet e2e", () => {
  const provider = anchor.AnchorProvider.env();
  anchor.setProvider(provider);
  const connection = provider.connection;
  const program = anchor.workspace.Batch as Program<Batch>;

  const participants = DEVNET_PARTICIPANTS;

  async function airdrop(pubkey: PublicKey, sol: number) {
    const sig = await connection.requestAirdrop(
      pubkey,
      sol * anchor.web3.LAMPORTS_PER_SOL
    );
    await connection.confirmTransaction(sig, "confirmed");
  }

  async function ensureMint() {
    const mintPubkey = DEVNET_MINT_KEYPAIR.publicKey;
    const info = await connection.getAccountInfo(mintPubkey);
    if (info) {
      return mintPubkey;
    }

    const created = await createMint(
      connection,
      DEVNET_MINT_AUTHORITY,
      DEVNET_MINT_AUTHORITY.publicKey,
      null,
      DEVNET_MINT_DECIMALS,
      DEVNET_MINT_KEYPAIR
    );
    if (!created.equals(mintPubkey)) {
      throw new Error("Mint pubkey mismatch after creation");
    }
    return created;
  }

  it("initializes config/pool, deposits, mixes, and pays recipients on devnet", async () => {
    // 1) Prepare PDAs.
    const [configPda] = PublicKey.findProgramAddressSync(
      [CONFIG_SEED],
      program.programId
    );
    const denomBytes = Buffer.alloc(8);
    denomBytes.writeBigUInt64LE(BigInt(DEVNET_DENOM));
    const [poolPda] = PublicKey.findProgramAddressSync(
      [POOL_SEED, denomBytes],
      program.programId
    );

    // 2) Ensure shared devnet mint exists (7 decimals to align with denom of 10_000_000).
    const mint = await ensureMint();

    // 3) Compute vault ATA for the pool PDA.
    const vaultAta = getAssociatedTokenAddressSync(mint, poolPda, true);

    // 4) Airdrop SOL to participants for fees (plus mint authority for ATA/mint fees).
    for (const kp of participants) {
      await airdrop(kp.publicKey, 2);
    }
    await airdrop(DEVNET_MINT_AUTHORITY.publicKey, 2);

    // 5) Initialize config if missing.
    const configInfo = await connection.getAccountInfo(configPda);
    if (!configInfo) {
      await program.methods
        .initializeConfig(provider.wallet.publicKey, provider.wallet.publicKey)
        .accounts({
          config: configPda,
          payer: provider.wallet.publicKey,
          systemProgram: SystemProgram.programId,
        })
        .rpc();
    }

    // 6) Initialize pool if missing.
    const poolInfo = await connection.getAccountInfo(poolPda);
    if (!poolInfo) {
      await program.methods
        .initPool(
          new anchor.BN(DEVNET_DENOM),
          10,
          MIN_POOL_SIZE,
          MIN_POOL_SIZE + 2
        )
        .accounts({
          payer: provider.wallet.publicKey,
          config: configPda,
          pool: poolPda,
          mint,
          vault: vaultAta,
          systemProgram: SystemProgram.programId,
          tokenProgram: anchor.utils.token.TOKEN_PROGRAM_ID,
          associatedTokenProgram: anchor.utils.token.ASSOCIATED_PROGRAM_ID,
          rent: anchor.web3.SYSVAR_RENT_PUBKEY,
        })
        .rpc();
    }

    // 7) Create ATAs for participants and mint tokens to them.
    const userAtas = [];
    for (const kp of participants) {
      const ata = await getOrCreateAssociatedTokenAccount(
        connection,
        DEVNET_MINT_AUTHORITY,
        mint,
        kp.publicKey
      );
      userAtas.push(ata.address);
      const currentAmount = Number(ata.amount);
      const shortfall = DEVNET_MINT_AMOUNT - currentAmount;
      if (shortfall > 0) {
        await mintTo(
          connection,
          DEVNET_MINT_AUTHORITY,
          mint,
          ata.address,
          DEVNET_MINT_AUTHORITY.publicKey,
          shortfall
        );
      }
    }

    // 8) Deposits from each participant.
    for (let i = 0; i < participants.length; i++) {
      await program.methods
        .deposit()
        .accounts({
          pool: poolPda,
          mint,
          vault: vaultAta,
          depositor: participants[i].publicKey,
          depositorToken: userAtas[i],
          tokenProgram: anchor.utils.token.TOKEN_PROGRAM_ID,
        })
        .signers([participants[i]])
        .rpc();
    }

    // 9) Execute mixing to pay recipients (use participant ATAs as recipients).
    const remainingAccounts: AccountMeta[] = userAtas.map((addr) => ({
      pubkey: addr,
      isSigner: false,
      isWritable: true,
    }));

    await program.methods
      .executeMixing()
      .accounts({
        pool: poolPda,
        vault: vaultAta,
        mint,
        tokenProgram: anchor.utils.token.TOKEN_PROGRAM_ID,
      })
      .remainingAccounts(remainingAccounts)
      .rpc();

    // 10) Assertions.
    // Vault should be drained post-mix.
    const vaultAccount = await getAccount(connection, vaultAta);
    if (Number(vaultAccount.amount) !== 0) {
      throw new Error("Vault not drained after mixing");
    }

    // Each participant should end at or above the target mint amount (deposit refunded via mixing).
    for (const ata of userAtas) {
      const acc = await getAccount(connection, ata);
      if (Number(acc.amount) < DEVNET_MINT_AMOUNT) {
        throw new Error("Recipient balance incorrect after mixing");
      }
    }

    const poolAccount = await program.account.pool.fetch(poolPda);
    if (!poolAccount.currentPoolSize.eq(new anchor.BN(0))) {
      throw new Error("Pool not reset after mixing");
    }
  });
});
