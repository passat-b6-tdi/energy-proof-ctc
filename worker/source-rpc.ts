import {
  JsonRpcProvider,
  TransactionReceipt,
  TransactionResponse,
} from "ethers";

const PUBLIC_SEPOLIA_RPCS = [
  "https://rpc.sepolia.ethpandaops.io",
  "https://ethereum-sepolia-rpc.publicnode.com",
  "https://public.1rpc.io/sepolia",
];

export function sourceRpcUrls(): string[] {
  const configured = (process.env.SOURCE_CHAIN_RPC_URLS ?? "")
    .split(",")
    .map((url) => url.trim())
    .filter(Boolean);
  const single = process.env.SOURCE_CHAIN_RPC_URL?.trim();

  return [
    ...new Set([
      ...PUBLIC_SEPOLIA_RPCS,
      ...configured,
      ...(single ? [single] : []),
    ]),
  ];
}

export async function findSourceTransaction(txHash: string): Promise<{
  provider: JsonRpcProvider;
  transaction: TransactionResponse;
  receipt: TransactionReceipt;
}> {
  let lastError: unknown;

  for (const url of sourceRpcUrls()) {
    const provider = new JsonRpcProvider(url);
    try {
      const [transaction, receipt] = await Promise.all([
        provider.getTransaction(txHash),
        provider.getTransactionReceipt(txHash),
      ]);
      if (transaction && receipt) return { provider, transaction, receipt };
    } catch (error) {
      lastError = error;
    }
  }

  if (lastError instanceof Error) {
    throw new Error(
      `Unable to find source transaction on configured Sepolia RPCs: ${lastError.message}`,
    );
  }
  throw new Error(`Source transaction not found: ${txHash}`);
}
