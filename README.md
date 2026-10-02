# CGS contracts

Three contracts, deployed to [Arc](https://www.arc.io/) — Circle's EVM L1,
USDC as gas. Reasoning and the full design are in the private docs:
`../docs/arc-port.md` §2 and `../docs/arc-stages.md` Stages 2–3.

- **`GameRegistry.sol`** — the public listing log the wishlist agent reads via
  `eth_getLogs`: `Listed`, `PriceChanged` (with the sale's deadline),
  `BuildUpdated`, `Delisted`, `Relisted`. Only the operator writes; nothing in it
  can touch a key or a vault. Replaces the Hedera build's HCS listings topic.
- **`GameKey.sol`** — ownership of a purchased game. One enumerable ERC-721
  collection, no admin function, no wipe/freeze/pause. `keysOf` and `keyFor`
  answer "what does this wallet hold" in one call. Delisting can't touch it.
- **`SplitVault.sol`** — one per game, deployed at publish, immutable. Splits
  whatever it receives between developers and the platform; nobody but a
  payee can touch their own claim. `claimFor` lets anyone pay the gas to
  release a payee's share — necessary because gas on Arc is USDC, so a
  developer whose first earnings are still in the vault cannot afford the
  transaction that would release them.

- **`VaultFactory.sol`** — deploys one vault per game, exactly once. Publishing
  is a deploy *and* a registry write, and `vaultOf` is what makes the pair safe
  to retry when the second half fails.

## Testnet deployment (Arc Testnet, chain 5042002)

All source-verified on the explorer.

| | Address |
|---|---|
| GameRegistry | [`0xE7aa837c45caE001bAc6f026B23edf6e96Ee490e`](https://explorer.testnet.arc.io/address/0xE7aa837c45caE001bAc6f026B23edf6e96Ee490e) |
| GameKey | [`0xaDC0757f81680c7014FbCE73d664653c5c629c41`](https://explorer.testnet.arc.io/address/0xaDC0757f81680c7014FbCE73d664653c5c629c41) |
| VaultFactory | [`0xc267BB087a1Bd1aAAB16c807e3f57980C78005ef`](https://explorer.testnet.arc.io/address/0xc267BB087a1Bd1aAAB16c807e3f57980C78005ef) |
| SplitVault (example: one developer, 5% platform) | [`0x0F4cbd4cd4C80868459865D996A62F6AfA0ac760`](https://explorer.testnet.arc.io/address/0x0F4cbd4cd4C80868459865D996A62F6AfA0ac760) |

`GameRegistry` was redeployed when it gained the `Demand` event, so the address
above replaces an earlier one; `GameKey` did not change and is deliberately the
original, so the keys already minted against it stay checkable on chain.

## Build and test

Uses [Arc Foundry](https://github.com/circlefin/arc-foundry) — `arc-forge`,
`arc-cast`, `arc-anvil` — not plain Foundry. Plain `anvil` runs a standard EVM
and won't reproduce Arc's own semantics (the runtime blocklist, native-USDC
value-transfer rules), which the tests below depend on.

```shell
arc-forge build
arc-forge test --network arc
```

`foundry.toml` pins `solc` to 0.8.35 and turns the optimizer on. Both matter:
the explorer only knows compilers up to 0.8.36, and `arc-forge` otherwise picks
the newest it finds, which then cannot be verified. Run `arc-forge clean` after
changing either, or `out/` keeps artifacts from the old compiler.

One thing the local tests can't check: Arc's blocklist is enforced by the live
network, not by `arc-anvil`'s local simulator. `test_onePayeeNeverBlocksAnother`
in `SplitVault.t.sol` checks the structural guarantee that's actually ours to
prove; the real enforcement is confirmed separately, live, in
`script/live-integration-test.mjs`.

## Deploy

```shell
cp .env.example .env   # fill in a fresh testnet-only key, never reused
arc-forge script script/Deploy.s.sol:Deploy \
  --rpc-url $ARC_TESTNET_RPC_URL --private-key $PRIVATE_KEY --broadcast
arc-forge script script/DeployVault.s.sol:DeployVault \
  --rpc-url $ARC_TESTNET_RPC_URL --private-key $PRIVATE_KEY --broadcast
```

`Deploy` makes the deployer both `GameRegistry`'s operator and `GameKey`'s
minter. Both are immutable, so whatever key the backend runs with has to be that
address.

To redeploy a single contract, put `--constructor-args` last:
`arc-forge create src/GameKey.sol:GameKey --rpc-url … --private-key … --broadcast --constructor-args <addr>`.

## Live integration test

Deploys a fresh `SplitVault` with three genuinely distinct, independently
funded recipients (not mocked test callers), sends it real USDC, has each one
claim with their own gas, and reconciles the total.

```shell
npm install   # viem, once
node script/live-integration-test.mjs
```

## Verify on Blockscout

```shell
script/verify-blockscout.sh <address> src/<Contract>.sol:<Contract> [testnet|mainnet]
```

Submits the standard-JSON input to the explorer's v2 API and waits for the
result. Constructor arguments are detected from the deployment. It does not go
through `arc-forge verify-contract`, whose pre-flight ABI lookup is rate limited.
