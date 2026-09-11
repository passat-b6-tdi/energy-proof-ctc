const ENERGY_TOPIC =
  "0x55a8ed4ec23678554ec0273389c8fcd2731e1332a662c6661630cf75c191a834";
const SETTLEMENT_TOPIC =
  "0x40f0410c46c73ff597a92da86baa258c46a9d54e621b85a0e4a3175fb41a08cb";
const TOTAL_SELECTOR = "0x067b23c3";
const SETTLED_SELECTOR = "0xd945af1d";
const config = {
  ...(window.ENERGYPROOF_CONFIG || {}),
  ...Object.fromEntries(new URLSearchParams(location.search)),
};
const hasLiveConfig = Boolean(
  config.sourceRpcUrl &&
  config.creditcoinRpcUrl &&
  config.meterAddress &&
  config.ledgerAddress,
);
const toast = document.querySelector("#toast");
const modal = document.querySelector("#modal");
const details = document.querySelector("#modalDetails");
let toastTimer;
let refreshInFlight = false;

function showToast(message) {
  toast.textContent = message;
  toast.classList.add("show");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toast.classList.remove("show"), 3200);
}

async function rpc(url, method, params) {
  const response = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: Date.now(), method, params }),
  });
  if (!response.ok) throw new Error(`${method}: HTTP ${response.status}`);
  const result = await response.json();
  if (result.error) throw new Error(result.error.message || method);
  return result.result;
}

function hexToBigInt(value) {
  return BigInt(value || "0x0");
}
function shortHash(value) {
  if (!value || value.length <= 14) return value || "—";
  return `${value.slice(0, 8)}…${value.slice(-6)}`;
}
function word(value) {
  return BigInt(`0x${value.slice(-64)}`);
}
function formatNumber(value) {
  return Number(value).toLocaleString("en-US");
}
async function call(url, address, data) {
  return rpc(url, "eth_call", [{ to: address, data }, "latest"]);
}

async function getLogsInChunks(url, filter, fromBlock, toBlock) {
  const chunkSize = Number(config.logChunkSize || 5_000);
  const chunks = [];
  for (let start = fromBlock; start <= toBlock; start += chunkSize) {
    const end = Math.min(start + chunkSize - 1, toBlock);
    chunks.push(
      await rpc(url, "eth_getLogs", [
        {
          ...filter,
          fromBlock: `0x${start.toString(16)}`,
          toBlock: `0x${end.toString(16)}`,
        },
      ]),
    );
  }
  return chunks.flat();
}

async function loadLiveData() {
  if (refreshInFlight) return;
  refreshInFlight = true;
  try {
    await fetchLiveData();
  } finally {
    refreshInFlight = false;
  }
}

async function fetchLiveData() {
  if (!hasLiveConfig) {
    document.querySelector("#energyStatus").textContent = "setup required";
    return;
  }
  const [sourceHead, creditHead] = await Promise.all([
    rpc(config.sourceRpcUrl, "eth_blockNumber", []),
    rpc(config.creditcoinRpcUrl, "eth_blockNumber", []),
  ]);
  const head = Number(hexToBigInt(sourceHead));
  const fromBlock =
    Number(config.sourceStartBlock || 0) || Math.max(0, head - 20_000);
  const logs = await getLogsInChunks(
    config.sourceRpcUrl,
    { address: config.meterAddress, topics: [ENERGY_TOPIC] },
    fromBlock,
    head,
  );
  const creditHeadNumber = Number(hexToBigInt(creditHead));
  const settlementLogs = await getLogsInChunks(
    config.creditcoinRpcUrl,
    { address: config.ledgerAddress, topics: [SETTLEMENT_TOPIC] },
    Number(config.creditcoinStartBlock || 0) || Math.max(0, creditHeadNumber - 100_000),
    creditHeadNumber,
  );
  const settlements = new Map(
    settlementLogs.map((log) => [log.topics[2].toLowerCase(), log.transactionHash]),
  );
  const readings = logs
    .slice(-24)
    .reverse()
    .map((log) => ({
      id: log.topics[3],
      producer: `0x${log.topics[2].slice(-40)}`,
      wattHours: Number(word(log.data)),
      block: Number(hexToBigInt(log.blockNumber)),
      txHash: log.transactionHash,
      settlementTx: settlements.get(log.topics[3].toLowerCase()) || "",
    }));
  const withStatus = await Promise.all(
    readings.map(async (reading) => ({
      ...reading,
      isSettled:
        word(
          await call(
            config.creditcoinRpcUrl,
            config.ledgerAddress,
            `${SETTLED_SELECTOR}${reading.id.slice(2)}`,
          ),
        ) === 1n,
      settlementTx: reading.settlementTx,
    })),
  );
  const total = word(
    await call(config.creditcoinRpcUrl, config.ledgerAddress, TOTAL_SELECTOR),
  );
  renderLiveReadings(withStatus);
  renderProofHero(withStatus);
  document.querySelector("#totalEnergy").textContent = formatNumber(total);
  document.querySelector("#proofCount").textContent = formatNumber(
    new Set(settlementLogs.map((log) => log.topics[2].toLowerCase())).size,
  );
  document.querySelector("#producerCount").textContent = new Set(
    withStatus.map((item) => item.producer.toLowerCase()),
  ).size.toString();
  document.querySelector("#duplicateCount").textContent = Math.max(
    0,
    settlementLogs.length -
      new Set(settlementLogs.map((log) => log.topics[2].toLowerCase())).size,
  ).toString();
  document.querySelector("#chainCount").textContent = "2";
  document.querySelector(".live-pill").innerHTML =
    `<i></i> Creditcoin · block #${formatNumber(hexToBigInt(creditHead))}`;
  document.querySelector(".network-name").innerHTML =
    `Sepolia · ${config.sourceCurrency || "ETH"} <span>→</span> Creditcoin · ${config.creditcoinCurrency || "tCTC"} · live`;
}

function renderProofHero(readings) {
  const latest = readings.find((reading) => reading.isSettled) || readings[0];
  if (!latest) return;
  document.querySelector("#heroEnergy").textContent = formatNumber(latest.wattHours);
  document.querySelector("#heroProducer").textContent = `Producer ${shortHash(latest.producer)}`;
  document.querySelector("#heroSourceBlock").textContent = `Sepolia block #${formatNumber(latest.block)}`;
  const settled = latest.isSettled;
  document.querySelector("#heroProofStatus").textContent = settled ? "Proof verified" : "Proof pending";
  document.querySelector("#heroSettlementStatus").textContent = settled ? "Settled" : "Awaiting proof";
  const sourceLink = document.querySelector("#heroSourceLink");
  sourceLink.href = `${config.sourceExplorer}/tx/${latest.txHash}`;
  sourceLink.hidden = false;
  const creditLink = document.querySelector("#heroCreditLink");
  creditLink.hidden = !latest.settlementTx;
  if (latest.settlementTx)
    creditLink.href = `${config.creditcoinExplorer}/tx/${latest.settlementTx}`;
  document.querySelector("#securityStatus").textContent = settled
    ? "Invariant active · live settlement"
    : "Waiting for first proof";
}

function renderLiveReadings(readings) {
  const body = document.querySelector("#readingsBody");
  body.innerHTML = readings.length
    ? readings
        .map(
          (reading) =>
            `<tr><td><button class="reading-link" data-reading="${reading.id}" data-block="${reading.block}" data-producer="${reading.producer}" data-energy="${reading.wattHours}" data-settled="${reading.isSettled}">${shortHash(reading.id)}</button><small>Sepolia block #${formatNumber(reading.block)}</small></td><td><span class="identity"><b>↗</b> ${shortHash(reading.producer)}</span></td><td>${formatNumber(reading.wattHours)} Wh</td><td><span class="mono">#${formatNumber(reading.block)}</span></td><td><span class="status ${reading.isSettled ? "accepted" : "pending"}">${reading.isSettled ? "Settled" : "Awaiting proof"}</span></td></tr>`,
        )
        .join("")
    : `<tr><td colspan="5" class="empty-state">No EnergyProduced events found in the configured range.</td></tr>`;
  body
    .querySelectorAll(".reading-link")
    .forEach((button) =>
      button.addEventListener("click", () => openReading(button.dataset)),
    );
}

function openReading(data) {
  const readingId = data.reading || data.id || "—";
  document.querySelector("#modalTitle").textContent = shortHash(
    readingId,
  );
  details.innerHTML = [
    ["Status", data.settled === "true" ? "Verified and settled" : "Source event indexed"],
    ["Energy", data.energy ? `${formatNumber(data.energy)} Wh` : "—"],
    ["Producer", data.producer || "—"],
    [
      "Source block",
      data.block ? `#${formatNumber(data.block)}` : "—",
    ],
    ["Reading ID", readingId],
  ]
    .map(
      ([label, value]) => {
        if (label === "Reading ID") {
          return `<div class="detail-row detail-row--hash"><span>${label}</span><div class="hash-value"><span>${value}</span></div></div>`;
        }
        return `<div class="detail-row"><span>${label}</span><span>${value}</span></div>`;
      },
    )
    .join("");
  const proofChain = document.querySelector("#proofChain");
  const settled = data.settled === "true";
  proofChain.classList.toggle("settled", settled);
  proofChain.classList.toggle("pending", !settled);
  proofChain.innerHTML = settled
    ? "<span>Source event</span><b>→</b><span>Proof verified</span><b>→</b><span>Credit settled</span>"
    : "<span>Source event</span><b>→</b><span class=\"pending-step\">Proof pending</span><b>→</b><span class=\"pending-step\">Credit pending</span>";
  modal.classList.add("open");
}

document
  .querySelectorAll(".reading-link")
  .forEach((button) =>
    button.addEventListener("click", () => openReading(button.dataset)),
  );
document
  .querySelector("#closeModal")
  .addEventListener("click", () => modal.classList.remove("open"));
modal.addEventListener("click", (event) => {
  if (event.target === modal) modal.classList.remove("open");
});
document
  .querySelector("#connectButton")
  .addEventListener("click", async (event) => {
    const button = event.currentTarget;
    if (!window.ethereum) return showToast("Install a Web3 wallet to connect.");
    try {
      const accounts = await window.ethereum.request({
        method: "eth_requestAccounts",
      });
      if (!accounts?.length) throw new Error("Wallet returned no accounts");
      button.textContent = `${accounts[0].slice(0, 6)}…${accounts[0].slice(-4)}`;
      showToast("Wallet connected. Dashboard reads public chain data.");
    } catch (error) {
      showToast(
        error?.code === 4001
          ? "Wallet connection cancelled."
          : `Wallet connection failed: ${error.message}`,
      );
    }
  });
document.querySelector("#runDemo").addEventListener("click", () =>
  hasLiveConfig
    ? loadLiveData()
        .then(() => showToast("Live chain data refreshed."))
        .catch((error) => showToast(`Live data unavailable: ${error.message}`))
    : showToast(
        "Live mode is not configured yet. Add deployed addresses to ui/config.js.",
      ),
);
document
  .querySelector("#viewAll")
  .addEventListener("click", () =>
    showToast(
      hasLiveConfig
        ? "Showing the latest indexed source events."
        : "Live mode is not configured yet.",
    ),
  );
document
  .querySelector("#provenanceButton")
  .addEventListener("click", () =>
    showToast(
      "The UI reads source events and settlement state directly from both chains.",
    ),
  );
if (hasLiveConfig)
  loadLiveData().catch((error) =>
    showToast(`Live data unavailable: ${error.message}`),
  );
if (hasLiveConfig) {
  setInterval(() => {
    loadLiveData().catch((error) =>
      showToast(`Live data unavailable: ${error.message}`),
    );
  }, 30_000);
}
