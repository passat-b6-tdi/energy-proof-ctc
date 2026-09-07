import 'dotenv/config';
import { chainInfo, proofProvider } from '@gluwa/usc-sdk';
import { Contract, JsonRpcProvider } from 'ethers';
import {createSigner} from './signer.js';

const CONSUMER_ABI = [
  'function execute(uint64 chainKey, uint64 blockHeight, bytes encodedTransaction, tuple(bytes32 root, tuple(bytes32 hash, bool isLeft)[] siblings) merkleProof, tuple(bytes32 lowerEndpointDigest, bytes32[] roots) continuityProof) returns (bool)',
];

function required(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

function explorerUrl(base: string, hash: string): string {
  return `${base.replace(/\/$/, '')}/tx/${hash}`;
}

async function main(): Promise<void> {
  const txHash = process.argv[2];
  if (!txHash) throw new Error('Usage: npm run demo -- <source-transaction-hash>');

  const sourceRpcUrl = required('SOURCE_CHAIN_RPC_URL');
  const creditcoinRpcUrl = required('CREDITCOIN_RPC_URL');
  const consumerAddress = required('ENERGY_PROOF_CONSUMER_ADDRESS');
  const proofBuilderUrl = required('PROOF_BUILDER_URL');
  const chainKey = Number(process.env.SOURCE_CHAIN_KEY ?? '1');
  const sourceExplorer = process.env.SOURCE_CHAIN_EXPLORER ?? 'https://sepolia.etherscan.io';
  const creditcoinExplorer = process.env.CREDITCOIN_EXPLORER ?? 'https://creditcoin-testnet.blockscout.com';

  const sourceProvider = new JsonRpcProvider(sourceRpcUrl);
  const creditcoinProvider = new JsonRpcProvider(creditcoinRpcUrl);
  const signer = await createSigner(creditcoinProvider);
  const consumer = new Contract(consumerAddress, CONSUMER_ABI, signer);

  const sourceTx = await sourceProvider.getTransaction(txHash);
  if (!sourceTx) throw new Error(`Source transaction not found: ${txHash}`);
  if (sourceTx.blockNumber === null) throw new Error('Source transaction is still pending');

  console.log(`Source transaction: ${explorerUrl(sourceExplorer, txHash)}`);
  console.log(`Source block: ${sourceTx.blockNumber}`);
  console.log(`Waiting for Attestcoin attestation for chain key ${chainKey}...`);

  const chainInfoProvider = new chainInfo.PrecompileChainInfoProvider(creditcoinProvider);
  await chainInfoProvider.waitUntilHeightAttested(chainKey, sourceTx.blockNumber, 15_000, 1_200_000);

  const builder = new proofProvider.service.ProofBuilder(chainKey, proofBuilderUrl);
  const result = await builder.getProof(txHash);
  if (!result.success || !result.data) throw new Error(`Proof generation failed: ${result.error ?? 'unknown error'}`);

  const proof = result.data;
  const merkleProof = {
    root: proof.merkleProof.root,
    siblings: proof.merkleProof.siblings.map((sibling) => ({hash: sibling.hash, isLeft: sibling.isLeft})),
  };
  const continuityProof = {
    lowerEndpointDigest: proof.continuityProof.lowerEndpointDigest,
    roots: proof.continuityProof.roots,
  };
  const args = [proof.chainKey, proof.headerNumber, proof.txBytes, merkleProof, continuityProof] as const;

  let gasLimit: bigint;
  try {
    gasLimit = await consumer.execute.estimateGas(...args);
  } catch {
    gasLimit = 21_000n + BigInt(continuityProof.roots.length) * 5_000n + 20_000n;
    console.log(`Gas estimation unavailable; using fallback gas limit ${gasLimit}`);
  }

  console.log(`Submitting proof for attested block ${proof.headerNumber}...`);
  const submission = await consumer.execute(...args, {gasLimit});
  console.log(`Creditcoin execute transaction: ${explorerUrl(creditcoinExplorer, submission.hash)}`);
  const receipt = await submission.wait();
  if (!receipt || receipt.status !== 1) throw new Error('Creditcoin execute transaction failed');
  console.log(`Confirmed in Creditcoin block ${receipt.blockNumber}`);
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
