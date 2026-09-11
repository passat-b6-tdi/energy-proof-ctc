import "dotenv/config";
import { Contract, JsonRpcProvider, id } from "ethers";
import { createSigner } from "./signer.js";

const METER_ABI = [
  "function recordProduction(tuple(uint32 wattHours, address producer, bytes32 readingId) energyParams)",
];

function required(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

async function main(): Promise<void> {
  const [countArg, ...producers] = process.argv.slice(2);
  const count = Number(countArg ?? "10");
  if (
    !Number.isInteger(count) ||
    count < 1 ||
    count > 10 ||
    producers.length === 0
  ) {
    throw new Error(
      "Usage: npm run demo:produce -- [1-10] <producer> [producer ...]",
    );
  }

  const provider = new JsonRpcProvider(required("SOURCE_CHAIN_RPC_URL"));
  const signer = await createSigner(provider);
  const meter = new Contract(
    required("ENERGY_METER_ADDRESS"),
    METER_ABI,
    signer,
  );
  const base = Date.now();

  for (let index = 0; index < count; index += 1) {
    const wattHours = 900 + index * 125;
    const producer = producers[index % producers.length];
    const readingId = id(`demo:${base}:${index}:${producer}`);
    const transaction = await meter.recordProduction({
      wattHours,
      producer,
      readingId,
    });
    const receipt = await transaction.wait();
    if (!receipt || receipt.status !== 1)
      throw new Error(`Transaction failed: ${transaction.hash}`);
    console.log(
      `${index + 1}/${count} ${transaction.hash} block=${receipt.blockNumber} producer=${producer} wattHours=${wattHours} readingId=${readingId}`,
    );
  }
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
