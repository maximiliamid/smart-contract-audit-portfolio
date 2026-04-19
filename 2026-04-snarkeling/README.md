# SNARKeling Treasure Hunt

*   Starts: April 16, 2026

*   Ends:  April 23, 2026

*   nSLOC: \~220

[//]: # (contest-details-open)

## About the Project

SNARKeling Treasure Hunt is a real-world snorkeling treasure hunt with on-chain reward claiming on an EVM blockchain. Participants physically find hidden treasures and then submit a zero-knowledge proof showing they know the correct treasure secret, without revealing the secret itself. The protocol verifies the proof on-chain and pays out an ETH reward to the designated recipient. This mechanism is built around a Noir circuit and a generated Barretenberg Honk verifier contract (more theory here https://updraft.cyfrin.io/courses/noir-programming-and-zk-circuits). 

Key Features:

*   Real-world treasure hunt with blockchain-based reward settlement 

*   ZK-SNARK based proof verification for treasure discovery 

*   Noir circuit that proves knowledge of a valid treasure secret without revealing it 

*   On-chain ETH reward distribution to a recipient bound into the proof 

*   Replay-resistance through recipient binding as a public input 

*   Owner-controlled pause/unpause, verifier update, emergency withdrawal, and post-hunt fund withdrawal flows 

The protocol works as follows:

1.  The organizer deploys the verifier and `TreasureHunt` contract and funds the hunt with ETH. 

2.  A participant finds a physical treasure associated with a unique secret string. 

3.  Off-chain, the participant generates a ZK proof that:
    *   they know a valid treasure secret,
    *   its Pedersen hash matches one of the allowed treasure hashes baked into the circuit,
    *   and the proof is bound to a specific recipient address. 

4.  The participant submits the proof, treasure hash, and recipient to the `TreasureHunt` contract.

5.  If the proof is valid and the treasure has not already been claimed, the contract transfers the fixed ETH reward to the recipient and marks the treasure as claimed. 


## Actors

**Participant / Treasure Finder:**

*   Powers: Can submit a ZK proof to claim a treasure reward for a valid recipient address. 

*   Limitations: Cannot claim with an invalid proof, cannot claim an already-claimed treasure, cannot claim if the contract lacks sufficient funds, and cannot use invalid recipients such as the zero address, the contract address, the owner, or the caller itself. 


**Owner / Hunt Organizer:**

*   Powers: Deploys and funds the hunt, pauses/unpauses the contract, updates the verifier while paused, emergency-withdraws ETH while paused, and withdraws leftover funds after all treasures have been claimed. Owner is trusted.

*   Limitations: Cannot claim treasure rewards as a participant and cannot set certain invalid recipients in emergency flows. 


[//]: # (contest-details-close)

[//]: # (scope-open)

## Scope

The following files are in scope for this contest: 

```js
contracts/
├── scripts/
│   └── Deploy.s.sol
└── src/
    └── TreasureHunt.sol

circuits/
└── src/
    └── main.nr
```



## Compatibilities

**Blockchains:**

*   Ethereum

**Protocol Assumptions:**

*   The hunt is preconfigured with a baked-in set of 10 valid treasure hashes in the circuit 

*   The contract is expected to be funded with enough ETH to cover all rewards (default deployment flow uses `100 ether`) 

*   The generated verifier contract must match the currently compiled circuit artifacts 


[//]: # (scope-close)



## Setup

System requirements:

*   Linux or WSL2
*   Foundry 
*   Noir / `nargo` (1.0.0-beta.19) https://noir-lang.org/docs/getting_started/quick_start
*   Barretenberg / `bb` (4.0.0-nightly.20260120) https://barretenberg.aztec.network/docs/getting_started/

Build:

Clone the repo.

### 1) Build circuit artifacts and generate verifier

The build script:

*   checks the Noir circuit,
*   reads a selected treasure/hash pair from `circuits/Prover.toml.example`,
*   writes a runtime `Prover.toml`,
*   executes the circuit,
*   generates a proof and verification key,
*   writes `contracts/src/Verifier.sol`,
*   and produces Foundry test fixtures. 

```bash
cd circuits/scripts
./build.sh
```

### 2) Build contracts

Navigate to the project root.

```bash
cd ../../
forge install foundry-rs/forge-std
forge build
```

### 3) Run tests

```bash
cd circuits
forge test
nargo test
```


[//]: # (getting-started-close)

[//]: # (known-issues-open)

## Known Issues

*   The verifier contract is generated from circuit artifacts, so circuit changes require regenerating `Verifier.sol` and related fixtures before tests or deployment. 

*   The set of allowed treasure hashes is baked into the Noir circuit, which means changing treasure inventory requires recompilation/regeneration of the proving artifacts. 

[//]: # (known-issues-close)

