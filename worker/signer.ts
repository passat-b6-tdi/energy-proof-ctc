import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { stdin as input, stdout as output } from "node:process";
import { HDNodeWallet, JsonRpcProvider, Wallet } from "ethers";

async function readPassword(prompt: string): Promise<string> {
  if (!input.isTTY || !input.setRawMode) {
    throw new Error("Keystore password requires an interactive terminal");
  }

  output.write(prompt);
  input.setRawMode(true);
  input.resume();

  return new Promise((resolve, reject) => {
    let password = "";

    const cleanup = (): void => {
      input.setRawMode?.(false);
      input.removeListener("data", onData);
      output.write("\n");
    };

    const onData = (chunk: Buffer): void => {
      for (const character of chunk.toString()) {
        if (character === "\u0003") {
          cleanup();
          reject(new Error("Password input cancelled"));
          return;
        }
        if (character === "\r" || character === "\n") {
          cleanup();
          resolve(password);
          return;
        }
        if (character === "\u007f") {
          password = password.slice(0, -1);
        } else {
          password += character;
        }
      }
    };

    input.on("data", onData);
  });
}

export async function createSigner(
  provider: JsonRpcProvider,
): Promise<Wallet | HDNodeWallet> {
  const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
  if (privateKey) return new Wallet(privateKey, provider);

  const account = process.env.DEPLOYER_ACCOUNT ?? "deployer";
  const keystorePath =
    process.env.DEPLOYER_KEYSTORE ??
    join(homedir(), ".foundry", "keystores", account);
  const password = await readPassword(`Keystore password for ${account}: `);
  const encryptedJson = await readFile(keystorePath, "utf8");
  const wallet = await Wallet.fromEncryptedJson(encryptedJson, password);
  return wallet.connect(provider);
}
