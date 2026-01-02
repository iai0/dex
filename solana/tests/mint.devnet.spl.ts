import {
  createMint,
  getOrCreateAssociatedTokenAccount,
  mintTo,
} from "@solana/spl-token";
import {
  Connection,
  Keypair,
  LAMPORTS_PER_SOL,
  PublicKey,
} from "@solana/web3.js";
import {
  DEVNET_AIRDROP_SOL,
  DEVNET_DENOM,
  DEVNET_MINT_AMOUNT,
  DEVNET_MINT_AUTHORITY,
  DEVNET_MINT_DECIMALS,
  DEVNET_MINT_KEYPAIR,
  DEVNET_PARTICIPANTS,
  DEVNET_RPC,
} from "./devnet.fixtures";

async function ensureSol(
  connection: Connection,
  keypair: Keypair,
  minSol: number
) {
  const balance = await connection.getBalance(keypair.publicKey);
  if (balance >= minSol * LAMPORTS_PER_SOL) {
    return;
  }
  const sig = await connection.requestAirdrop(
    keypair.publicKey,
    minSol * LAMPORTS_PER_SOL
  );
  await connection.confirmTransaction(sig, "confirmed");
}

async function ensureMint(
  connection: Connection,
  mintAuthority: Keypair
): Promise<PublicKey> {
  const mintPubkey = DEVNET_MINT_KEYPAIR.publicKey;
  const info = await connection.getAccountInfo(mintPubkey);
  if (info) {
    return mintPubkey;
  }

  const created = await createMint(
    connection,
    mintAuthority,
    mintAuthority.publicKey,
    null,
    DEVNET_MINT_DECIMALS,
    DEVNET_MINT_KEYPAIR
  );
  if (!created.equals(mintPubkey)) {
    throw new Error("Mint pubkey mismatch after creation");
  }
  return created;
}

async function main() {
  const connection = new Connection(DEVNET_RPC, "confirmed");
  console.log(`RPC: ${DEVNET_RPC}`);

  await ensureSol(connection, DEVNET_MINT_AUTHORITY, DEVNET_AIRDROP_SOL);
  for (const kp of DEVNET_PARTICIPANTS) {
    await ensureSol(connection, kp, DEVNET_AIRDROP_SOL);
  }

  const mint = await ensureMint(connection, DEVNET_MINT_AUTHORITY);
  console.log(`Mint ready: ${mint.toBase58()}`);

  for (const owner of DEVNET_PARTICIPANTS) {
    const ata = await getOrCreateAssociatedTokenAccount(
      connection,
      DEVNET_MINT_AUTHORITY,
      mint,
      owner.publicKey
    );

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
      console.log(
        `Topped up ${owner.publicKey.toBase58()} by ${
          shortfall / DEVNET_DENOM
        } denom(s) (ATA ${ata.address.toBase58()})`
      );
    } else {
      console.log(
        `No mint needed for ${owner.publicKey.toBase58()} (ATA ${ata.address.toBase58()})`
      );
    }
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
