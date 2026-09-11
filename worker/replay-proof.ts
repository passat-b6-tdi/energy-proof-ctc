import "dotenv/config";
import { chainInfo, proofProvider } from "@gluwa/usc-sdk";
import { Contract, Interface, JsonRpcProvider } from "ethers";
import { createSigner } from "./signer.js";
import { findSourceTransaction } from "./source-rpc.js";

const CONSUMER_ABI = [
  "function execute(uint64 chainKey, uint64 blockHeight, bytes encodedTransaction, tuple(bytes32 root, tuple(bytes32 hash, bool isLeft)[] siblings) merkleProof, tuple(bytes32 lowerEndpointDigest, bytes32[] roots) continuityProof) returns (bool)",
  "error QueryAlreadyProcessed(bytes32 queryId)",
];
const LEDGER_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function totalCredited() view returns (uint256)",
];
const METER_INTERFACE = new Interface([
  "event EnergyProduced(address indexed oracle, address indexed producer, bytes32 indexed readingId, uint32 wattHours)",
]);

function required(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

function explorerUrl(base: string, hash: string): string {
  return `${base.replace(/\/$/, "")}/tx/${hash}`;
}

function extractErrorData(error: any): string | undefined {
  const candidates = [
    error?.data,
    error?.info?.error?.data,
    error?.error?.data,
    error?.info?.data,
    error?.revert?.data,
  ];
  return candidates.find(
    (value): value is string =>
      typeof value === "string" && value.startsWith("0x") && value.length >= 10,
  );
}

function decodeErrorName(contract: Contract, error: any): string {
  const data = extractErrorData(error);
  if (!data) return "UnknownRevert";
  try {
    return contract.interface.parseError(data)?.name ?? "UnknownRevert";
  } catch {
    return "UnknownRevert";
  }
}

async function main(): Promise<void> {
  const txHash = process.argv[2];
  if (!txHash)
    throw new Error("Usage: npm run demo:replay -- <source-transaction-hash>");

  const creditcoinRpcUrl = required("CREDITCOIN_RPC_URL");
  const consumerAddress = required("ENERGY_PROOF_CONSUMER_ADDRESS");
  const ledgerAddress = required("ENERGY_CREDIT_LEDGER_ADDRESS");
  const proofBuilderUrl = required("PROOF_BUILDER_URL");
  const chainKey = Number(process.env.SOURCE_CHAIN_KEY ?? "1");
  const sourceExplorer =
    process.env.SOURCE_CHAIN_EXPLORER ?? "https://sepolia.etherscan.io";
  const creditcoinExplorer =
    process.env.CREDITCOIN_EXPLORER ??
    "https://creditcoin-testnet.blockscout.com";

  const creditcoinProvider = new JsonRpcProvider(creditcoinRpcUrl);
  const signer = await createSigner(creditcoinProvider);
  const consumer = new Contract(consumerAddress, CONSUMER_ABI, signer);
  const ledger = new Contract(ledgerAddress, LEDGER_ABI, creditcoinProvider);

  const { transaction: sourceTx, receipt: sourceReceipt } =
    await findSourceTransaction(txHash);
  const eventLog = sourceReceipt.logs
    .map((log) => {
      try {
        return METER_INTERFACE.parseLog(log);
      } catch {
        return null;
      }
    })
    .find((log) => log?.name === "EnergyProduced");
  if (!eventLog)
    throw new Error("EnergyProduced event not found in source transaction");

  const producer = eventLog.args.producer as string;
  const readingId = eventLog.args.readingId as string;
  const beforeBalance = await ledger.balanceOf(producer);
  const beforeTotal = await ledger.totalCredited();

  console.log(
    `Original source transaction: ${explorerUrl(sourceExplorer, txHash)}`,
  );
  console.log(`Reading ID: ${readingId}`);
  console.log(`Balance before replay: ${beforeBalance.toString()}`);
  console.log(`totalCredited before replay: ${beforeTotal.toString()}`);

  const chainInfoProvider = new chainInfo.PrecompileChainInfoProvider(
    creditcoinProvider,
  );
  await chainInfoProvider.waitUntilHeightAttested(
    chainKey,
    sourceTx.blockNumber!,
    15_000,
    1_200_000,
  );
  const builder = new proofProvider.service.ProofBuilder(
    chainKey,
    proofBuilderUrl,
  );
  const result = await builder.getProof(txHash);
  if (!result.success || !result.data)
    throw new Error(
      `Proof generation failed: ${result.error ?? "unknown error"}`,
    );

  const proof = result.data;
  const args = [
    proof.chainKey,
    proof.headerNumber,
    proof.txBytes,
    {
      root: proof.merkleProof.root,
      siblings: proof.merkleProof.siblings.map((sibling) => ({
        hash: sibling.hash,
        isLeft: sibling.isLeft,
      })),
    },
    {
      lowerEndpointDigest: proof.continuityProof.lowerEndpointDigest,
      roots: proof.continuityProof.roots,
    },
  ] as const;

  const gasLimit =
    21_000n + BigInt(proof.continuityProof.roots.length) * 5_000n + 20_000n;
  let preflightErrorName = "UnknownRevert";
  try {
    await consumer.execute.staticCall(...args, { gasLimit });
    throw new Error("Replay unexpectedly passed preflight");
  } catch (error: any) {
    preflightErrorName = decodeErrorName(consumer, error);
    if (preflightErrorName !== "QueryAlreadyProcessed")
      throw new Error(`Replay preflight reverted with ${preflightErrorName}`);
    console.log(`Replay preflight: ${preflightErrorName}`);
  }

  let replayTxHash = "";
  try {
    const submission = await consumer.execute(...args, { gasLimit });
    replayTxHash = submission.hash;
    await submission.wait();
    throw new Error("Replay unexpectedly succeeded");
  } catch (error: any) {
    replayTxHash ||=
      error?.receipt?.hash ??
      error?.receipt?.transactionHash ??
      error?.transactionHash ??
      "";
    const errorName = decodeErrorName(consumer, error);
    // Some Creditcoin RPC responses omit revert data from a failed receipt.
    const resolvedErrorName =
      errorName === "UnknownRevert" &&
      preflightErrorName === "QueryAlreadyProcessed"
        ? preflightErrorName
        : errorName;
    if (resolvedErrorName !== "QueryAlreadyProcessed")
      throw new Error(`Replay reverted with ${resolvedErrorName}`);
    console.log(`Replay rejected: ${resolvedErrorName}`);
    if (replayTxHash)
      console.log(
        `Replay transaction: ${explorerUrl(creditcoinExplorer, replayTxHash)}`,
      );
  }

  const afterBalance = await ledger.balanceOf(producer);
  const afterTotal = await ledger.totalCredited();
  console.log(`Balance after replay: ${afterBalance.toString()}`);
  console.log(`totalCredited after replay: ${afterTotal.toString()}`);
  if (afterBalance !== beforeBalance || afterTotal !== beforeTotal) {
    throw new Error(
      "SECURITY CHECK FAILED: ledger state changed during replay",
    );
  }
  console.log("Security check passed: balance and totalCredited unchanged.");
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
