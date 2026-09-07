import 'dotenv/config';
import {Contract, JsonRpcProvider, Wallet, id, parseEther} from 'ethers';
import {createSigner} from './signer.js';

const METER_ABI = [
  'function addOracle(address oracle)',
  'function removeOracle(address oracle)',
  'function recordProduction(tuple(uint32 wattHours, address producer, bytes32 readingId) energyParams)',
];

function required(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

async function main(): Promise<void> {
  const provider = new JsonRpcProvider(required('SOURCE_CHAIN_RPC_URL'));
  const deployer = await createSigner(provider);
  const meterAddress = required('ENERGY_METER_ADDRESS');
  const meter = new Contract(meterAddress, METER_ABI, deployer);
  const producers = Array.from({length: 3}, () => Wallet.createRandom().connect(provider));
  const base = Date.now();

  console.log('Created demo producers:');
  producers.forEach((producer, index) => console.log(`${index + 1}. ${producer.address}`));

  for (const producer of producers) {
    const funding = await deployer.sendTransaction({to: producer.address, value: parseEther('0.001')});
    await funding.wait();
    const permission = await meter.addOracle(producer.address);
    await permission.wait();
  }

  try {
    for (let index = 0; index < producers.length; index += 1) {
      const producer = producers[index];
      const producerMeter = new Contract(meterAddress, METER_ABI, producer);
      for (let reading = 0; reading < 3; reading += 1) {
        const wattHours = 900 + index * 250 + reading * 125;
        const readingId = id(`producer-demo:${base}:${index}:${reading}`);
        const transaction = await producerMeter.recordProduction({wattHours, producer: producer.address, readingId});
        const receipt = await transaction.wait();
        if (!receipt || receipt.status !== 1) throw new Error(`Transaction failed: ${transaction.hash}`);
        console.log(`${producer.address} ${transaction.hash} block=${receipt.blockNumber} wattHours=${wattHours} readingId=${readingId}`);
      }
    }
  } finally {
    for (const producer of producers) {
      const permission = await meter.removeOracle(producer.address);
      await permission.wait();
    }
  }
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
