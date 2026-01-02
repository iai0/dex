import { Keypair } from "@solana/web3.js";

export const DEVNET_RPC =
  process.env.ANCHOR_PROVIDER_URL ||
  process.env.SOLANA_RPC ||
  "https://api.devnet.solana.com";

export const DEVNET_MINT_DECIMALS = 7;
export const DEVNET_DENOM = 10_000_000; // matches Denomination::Small in the program
export const DEVNET_AIRDROP_SOL = 2;
export const DEVNET_MINT_AMOUNT = DEVNET_DENOM * 5;

// Fixed devnet-only keypairs that can be shared for testing.
const MINT_ACCOUNT_SECRET = [
  201, 52, 19, 87, 233, 198, 0, 155, 190, 212, 148, 192, 29, 223, 68, 79, 225,
  131, 244, 58, 8, 176, 247, 61, 131, 176, 243, 67, 192, 236, 153, 145, 144,
  17, 21, 137, 35, 65, 95, 189, 16, 130, 226, 112, 245, 195, 231, 144, 132, 37,
  181, 89, 246, 148, 71, 13, 158, 248, 10, 128, 103, 48, 14, 190,
];

const MINT_AUTHORITY_SECRET = [
  108, 245, 129, 97, 228, 242, 189, 218, 213, 121, 37, 221, 134, 241, 235, 213,
  160, 237, 127, 186, 140, 195, 13, 20, 165, 150, 99, 195, 55, 29, 139, 104,
  216, 195, 141, 205, 182, 37, 10, 6, 204, 13, 227, 142, 58, 130, 77, 153, 107,
  17, 108, 74, 189, 161, 218, 7, 115, 161, 94, 246, 161, 5, 196, 117,
];

const PARTICIPANT_A_SECRET = [
  136, 31, 255, 69, 108, 173, 206, 211, 94, 236, 3, 16, 147, 96, 246, 18, 119,
  137, 155, 113, 74, 35, 11, 211, 249, 67, 217, 152, 95, 156, 155, 68, 33, 168,
  99, 253, 93, 21, 231, 116, 7, 227, 99, 98, 57, 82, 88, 60, 34, 211, 218, 98,
  1, 27, 106, 103, 57, 192, 234, 22, 194, 11, 71, 44,
];

const PARTICIPANT_B_SECRET = [
  99, 11, 186, 41, 114, 185, 84, 9, 129, 140, 89, 223, 198, 51, 112, 79, 19, 42,
  207, 163, 169, 150, 128, 203, 0, 103, 31, 105, 105, 17, 145, 204, 193, 66,
  251, 114, 226, 11, 253, 14, 172, 145, 191, 213, 93, 90, 79, 168, 184, 227,
  119, 252, 245, 70, 52, 206, 104, 172, 55, 231, 57, 117, 88, 113,
];

export const DEVNET_MINT_KEYPAIR = Keypair.fromSecretKey(
  new Uint8Array(MINT_ACCOUNT_SECRET)
);

export const DEVNET_MINT_AUTHORITY = Keypair.fromSecretKey(
  new Uint8Array(MINT_AUTHORITY_SECRET)
);

export const DEVNET_PARTICIPANTS = [
  Keypair.fromSecretKey(new Uint8Array(PARTICIPANT_A_SECRET)),
  Keypair.fromSecretKey(new Uint8Array(PARTICIPANT_B_SECRET)),
];
