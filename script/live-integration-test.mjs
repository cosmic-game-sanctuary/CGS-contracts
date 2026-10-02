import { readFileSync } from "node:fs";
import {
  createPublicClient,
  createWalletClient,
  http,
  formatUnits,
  parseEther,
} from "viem";
import { privateKeyToAccount, generatePrivateKey } from "viem/accounts";
import { arcTestnet } from "viem/chains";

// Real end-to-end test against live Arc Testnet: deploy a SplitVault with
// three genuinely distinct, independently-funded recipients (not mocked
// callers the way forge tests use vm.prank), send it real USDC, have each
// recipient claim their own share with their own gas, and confirm the sum
// paid out matches exactly what was sent in. Proves the pull-based design
// and the rounding-remainder logic on the actual network, not a simulator.

const artifact = JSON.parse(readFileSync(new URL("../out/SplitVault.sol/SplitVault.json", import.meta.url)));
const deployerPk = process.env.PRIVATE_KEY;
if (!deployerPk) throw new Error("set PRIVATE_KEY");

const transport = http("https://rpc.testnet.arc.io");
const deployer = privateKeyToAccount(deployerPk);
const publicClient = createPublicClient({ chain: arcTestnet, transport });
const deployerWallet = createWalletClient({ account: deployer, chain: arcTestnet, transport });

const fmt = (wei) => `${formatUnits(wei, 18)} USDC`;

console.log("deployer:", deployer.address);
console.log("deployer balance:", fmt(await publicClient.getBalance({ address: deployer.address })));

// Three fresh throwaway recipients, generated locally, funded by nobody but
// this script. 3333/3333/3333 bps + platformBps=1 — same odd total the local
// rounding test uses, now proven for real rather than in a simulator.
const recipients = [generatePrivateKey(), generatePrivateKey(), generatePrivateKey()].map((pk) => ({
  pk,
  account: privateKeyToAccount(pk),
}));
const bps = [3333, 3333, 3333];
const platformBps = 1;
console.log("recipients:", recipients.map((r) => r.account.address));

console.log("\n--- deploying SplitVault ---");
const deployHash = await deployerWallet.deployContract({
  abi: artifact.abi,
  bytecode: artifact.bytecode.object,
  args: [recipients.map((r) => r.account.address), bps, deployer.address, platformBps],
});
const deployReceipt = await publicClient.waitForTransactionReceipt({ hash: deployHash });
const vault = deployReceipt.contractAddress;
console.log("SplitVault deployed:", vault, "gas used:", deployReceipt.gasUsed.toString());

// Fund each recipient with just enough native value to pay their own claim's
// gas — the whole point of pull-based payouts. ~0.002 USDC each is generous
// at a 20 Gwei floor.
console.log("\n--- funding recipients' gas ---");
for (const r of recipients) {
  const hash = await deployerWallet.sendTransaction({ to: r.account.address, value: parseEther("0.01") });
  await publicClient.waitForTransactionReceipt({ hash });
}
console.log("funded.");

// Send the vault a deliberately-odd amount so the rounding remainder is
// exercised for real, not just in the local unit test.
const amount = parseEther("0.01") + 1n;
console.log(`\n--- sending vault ${fmt(amount)} ---`);
const fundHash = await deployerWallet.sendTransaction({ to: vault, value: amount });
await publicClient.waitForTransactionReceipt({ hash: fundHash });
console.log("vault balance:", fmt(await publicClient.getBalance({ address: vault })));

console.log("\n--- claiming ---");
let totalClaimed = 0n;
for (const [i, r] of recipients.entries()) {
  const wallet = createWalletClient({ account: r.account, chain: arcTestnet, transport });
  const before = await publicClient.getBalance({ address: r.account.address });
  const hash = await wallet.writeContract({ address: vault, abi: artifact.abi, functionName: "claim" });
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  const after = await publicClient.getBalance({ address: r.account.address });
  const gasCost = receipt.gasUsed * receipt.effectiveGasPrice;
  const received = after - before + gasCost;
  totalClaimed += received;
  console.log(`recipient ${i} (${r.account.address}) claimed ${fmt(received)}, paid ${fmt(gasCost)} gas`);
}

const platformWallet = deployerWallet;
const platformBefore = await publicClient.getBalance({ address: deployer.address });
const platformHash = await platformWallet.writeContract({ address: vault, abi: artifact.abi, functionName: "claim" });
const platformReceipt = await publicClient.waitForTransactionReceipt({ hash: platformHash });
const platformAfter = await publicClient.getBalance({ address: deployer.address });
const platformGasCost = platformReceipt.gasUsed * platformReceipt.effectiveGasPrice;
const platformReceived = platformAfter - platformBefore + platformGasCost;
totalClaimed += platformReceived;
console.log(`platform (${deployer.address}) claimed ${fmt(platformReceived)}, paid ${fmt(platformGasCost)} gas`);

const vaultFinalBalance = await publicClient.getBalance({ address: vault });
console.log("\n--- result ---");
console.log("amount sent to vault:   ", fmt(amount));
console.log("total claimed by all:   ", fmt(totalClaimed));
console.log("vault balance remaining:", fmt(vaultFinalBalance));
console.log(
  totalClaimed === amount && vaultFinalBalance === 0n
    ? "PASS: every unit sent was claimed, nothing stranded."
    : "FAIL: totals don't reconcile.",
);
