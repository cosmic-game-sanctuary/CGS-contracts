# CGS contracts

Three contracts, deployed to [Arc](https://www.arc.io/) — Circle's EVM L1,
USDC as gas. Reasoning and the full design are in the private docs:
`../docs/arc-port.md` §2 and `../docs/arc-stages.md` Stage 2.

- **`GameRegistry.sol`** — the public listing log the wishlist agent reads via
  `eth_getLogs`. Replaces the Hedera build's HCS listings topic.
- **`GameKey.sol`** — ownership of a purchased game. One ERC-721 collection,
  no admin function, no wipe/freeze/pause. Delisting can't touch it.
- **`SplitVault.sol`** — one per game, deployed at publish, immutable. Splits
  whatever it receives between developers and the platform; nobody but a
  payee can touch their own claim.

## Build and test

Uses [Arc Foundry](https://github.com/circlefin/arc-foundry) — `arc-forge`,
`arc-cast`, `arc-anvil` — not plain Foundry. Plain `anvil` runs a standard EVM
and won't reproduce Arc's own semantics (the runtime blocklist, native-USDC
value-transfer rules), which the tests below depend on.

```shell
arc-forge build
arc-forge test --network arc
```

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
```

## Live integration test

Deploys a fresh `SplitVault` with three genuinely distinct, independently
funded recipients (not mocked test callers), sends it real USDC, has each one
claim with their own gas, and reconciles the total. Needs `.env` filled in and
the recipient's own small USDC balance for gas — the script funds that itself
from the deployer.

```shell
npm install   # viem, once
node script/live-integration-test.mjs
```

## Verify on Blockscout

```shell
arc-forge verify-contract <address> src/<Contract>.sol:<Contract> \
  --chain-id 5042002 --verifier blockscout \
  --verifier-url https://explorer.testnet.arc.io/api/ \
  --compiler-version 0.8.37 \
  --constructor-args $(arc-cast abi-encode "constructor(<types>)" <args>)
```

GameKey and GameRegistry each take one `address` arg. SplitVault takes
`(address[],uint16[],address,uint16)`.
