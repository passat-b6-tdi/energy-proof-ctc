import 'dotenv/config';
import { Contract, JsonRpcProvider, id } from 'ethers';
import {createSigner} from './signer.js';

const METER_ABI = [
  'function recordProduction(tuple(uint32 wattHours, address producer, bytes32 readingId) energyParams)',
];

function required(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

async function main(): Promise<void> {
  const [wattHoursArg, producer, readingIdArg] = process.argv.slice(2);
  if (!wattHoursArg || !producer) {
    throw new Error('Usage: npm run meter:produce -- <watt-hours> <producer> [reading-id]');
  }

  const provider = new JsonRpcProvider(required('SOURCE_CHAIN_RPC_URL'));
  const signer = await createSigner(provider);
  const meter = new Contract(required('ENERGY_METER_ADDRESS'), METER_ABI, signer);
  const readingId = readingIdArg ?? id(`${Date.now()}:${producer}`);
  const transaction = await meter.recordProduction({wattHours: BigInt(wattHoursArg), producer, readingId});
  console.log(`Submitted source transaction: ${transaction.hash}`);
  const receipt = await transaction.wait();
  if (!receipt || receipt.status !== 1) throw new Error('Source transaction failed');
  console.log(`Confirmed in Sepolia block ${receipt.blockNumber}`);
  console.log(`Reading ID: ${readingId}`);
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
