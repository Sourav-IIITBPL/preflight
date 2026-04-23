# PreFlight Contracts

Smart contracts powering **PreFlight** - a pre-transaction security and risk analysis system for DeFi.

These contracts include:
- Routers (user entry points)
- Guards (validation + protection layer)
- Risk Policies (risk evaluation logic)
- Reporting (on-chain NFT risk reports)

---

## Setup & Installation

```bash
git clone https://github.com/Sourav-IIITBPL/preflight
cd contracts
forge install
forge build
```

## Deployments 

> Contracts are currently deployed **only on testnets** (Sepolia, Arbitrum Sepolia, Base Sepolia).

- Network: Ethereum Sepolia Testnet
- Chain ID: 11155111 

| Contract Name              | Address |
|---------------------------|--------|
| ERC4626 Router            | [0xb683c879a6a8C311F4B462486aF9f489A4e3EDFe](https://sepolia.etherscan.io/address/0xb683c879a6a8C311F4B462486aF9f489A4e3EDFe#code) |
| Swap V2 Router            | [0x8274cA1585600eA8ba3f22e5a4fD15cF5EE2Fcc1](https://sepolia.etherscan.io/address/0x8274cA1585600eA8ba3f22e5a4fD15cF5EE2Fcc1#code) |
| Liquidity V2 Router       | [0xf7e64cb94678a111D0C9207FD335678882aDcaF7](https://sepolia.etherscan.io/address/0xf7e64cb94678a111D0C9207FD335678882aDcaF7#code) |
| ERC4626 Vault Guard       | [0x83D02Cf1c6104705A933FC5a913848a443B0eA7e](https://sepolia.etherscan.io/address/0x83D02Cf1c6104705A933FC5a913848a443B0eA7e#code) |
| Swap V2 Guard             | [0x44A6D48bEd281Bc185e836bc2865Baf104927620](https://sepolia.etherscan.io/address/0x44A6D48bEd281Bc185e836bc2865Baf104927620#code) |
| Liquidity V2 Guard        | [0x746c1DEF9774d346b1E58121CC4DccE182eE031b](https://sepolia.etherscan.io/address/0x746c1DEF9774d346b1E58121CC4DccE182eE031b#code) |
| Token Guard               | [0x3fd02d6aC70ec3Ee8583f08e61293b6bbb3c33FD](https://sepolia.etherscan.io/address/0x3fd02d6aC70ec3Ee8583f08e61293b6bbb3c33FD#code) |
| ERC4626 Risk Policy       | [0x1e7FC50e985f7E3812B0403ad70F9D1Fd780E88b](https://sepolia.etherscan.io/address/0x1e7FC50e985f7E3812B0403ad70F9D1Fd780E88b#code) |
| Swap V2 Risk Policy       | [0xc3b5252C2610A4e62d32581433301403C9De3e64](https://sepolia.etherscan.io/address/0xc3b5252C2610A4e62d32581433301403C9De3e64#code) |
| Liquidity V2 Risk Policy  | [0x95144CeDb8D9cE55bAfB5a5048515FcF3d6Eafb8](https://sepolia.etherscan.io/address/0x95144CeDb8D9cE55bAfB5a5048515FcF3d6Eafb8#code) |
| Risk Report NFT           | [0xf2FC782E0ceBb7D352BF8e5356456Bd4C9d657f4](https://sepolia.etherscan.io/address/0xf2FC782E0ceBb7D352BF8e5356456Bd4C9d657f4#code) |
| SVG Renderer              | [0xeFA2Ce549445Ea626550a945A7e9d282ec12E7c2](https://sepolia.etherscan.io/address/0xeFA2Ce549445Ea626550a945A7e9d282ec12E7c2#code) |

---

- Network: Arbitrum Sepolia Testnet 
- Chain ID: 421614 

| Contract Name              | Address |
|---------------------------|--------|
| ERC4626 Router            | [0x95144CeDb8D9cE55bAfB5a5048515FcF3d6Eafb8](https://sepolia.arbiscan.io/address/0x95144CeDb8D9cE55bAfB5a5048515FcF3d6Eafb8#code) |
| Swap V2 Router            | [0x3fd02d6aC70ec3Ee8583f08e61293b6bbb3c33FD](https://sepolia.arbiscan.io/address/0x3fd02d6aC70ec3Ee8583f08e61293b6bbb3c33FD#code) |
| Liquidity V2 Router       | [0xde4d5568f452Ca2f6C3F452B2AEA78277EBE7Ee3](https://sepolia.arbiscan.io/address/0xde4d5568f452Ca2f6C3F452B2AEA78277EBE7Ee3#code) |
| ERC4626 Vault Guard       | [0xf2FC782E0ceBb7D352BF8e5356456Bd4C9d657f4](https://sepolia.arbiscan.io/address/0xf2FC782E0ceBb7D352BF8e5356456Bd4C9d657f4#code) |
| Swap V2 Guard             | [0x1e7FC50e985f7E3812B0403ad70F9D1Fd780E88b](https://sepolia.arbiscan.io/address/0x1e7FC50e985f7E3812B0403ad70F9D1Fd780E88b#code) |
| Liquidity V2 Guard        | [0xc3b5252C2610A4e62d32581433301403C9De3e64](https://sepolia.arbiscan.io/address/0xc3b5252C2610A4e62d32581433301403C9De3e64#code) |
| Token Guard               | [0x552DDEF48C388b43192f6e5410eF106961851907](https://sepolia.arbiscan.io/address/0x552DDEF48C388b43192f6e5410eF106961851907#code) |
| ERC4626 Risk Policy       | [0xfe8D3CA6c7208E49A8626DF66C4cE5dFb25B3f18](https://sepolia.arbiscan.io/address/0xfe8D3CA6c7208E49A8626DF66C4cE5dFb25B3f18#code) |
| Swap V2 Risk Policy       | [0x583C384853aF62242922A1124B2ed282B8409BA1](https://sepolia.arbiscan.io/address/0x583C384853aF62242922A1124B2ed282B8409BA1#code) |
| Liquidity V2 Risk Policy  | [0x5E868b0A2cd21246B2C4E78283a84dBB9E5c1566](https://sepolia.arbiscan.io/address/0x5E868b0A2cd21246B2C4E78283a84dBB9E5c1566#code) |
| Risk Report NFT           | [0xb3b57023A4936865A143ACEDE2A67edD5E16e145](https://sepolia.arbiscan.io/address/0xb3b57023A4936865A143ACEDE2A67edD5E16e145#code) |
| SVG Renderer              | [0x8C398A7147527b423930922AD72cb6eA3044A293](https://sepolia.arbiscan.io/address/0x8C398A7147527b423930922AD72cb6eA3044A293#code) |

---

- Network: Base Sepolia Testnet 
- Chain ID: 84532

| Contract Name              | Address |
|---------------------------|--------|
| ERC4626 Router            | [0x66e37fd517C909254Cd9Fb89c839543c0DD5b2dd](https://sepolia.basescan.org/address/0x66e37fd517C909254Cd9Fb89c839543c0DD5b2dd#code) |
| Swap V2 Router            | [0x8C398A7147527b423930922AD72cb6eA3044A293](https://sepolia.basescan.org/address/0x8C398A7147527b423930922AD72cb6eA3044A293#code) |
| Liquidity V2 Router       | [0xb3b57023A4936865A143ACEDE2A67edD5E16e145](https://sepolia.basescan.org/address/0xb3b57023A4936865A143ACEDE2A67edD5E16e145#code) |
| ERC4626 Vault Guard       | [0x5C79eeF4D8eE4DC95877a4c0b4D6F21075f867a1](https://sepolia.basescan.org/address/0x5C79eeF4D8eE4DC95877a4c0b4D6F21075f867a1#code) |
| Swap V2 Guard             | [0x327C5c4ce847820bE73d6a833C6948233086A468](https://sepolia.basescan.org/address/0x327C5c4ce847820bE73d6a833C6948233086A468#code) |
| Liquidity V2 Guard        | [0xFAA7151673D4854cD253BeA6cc86be80AD0917Fc](https://sepolia.basescan.org/address/0xFAA7151673D4854cD253BeA6cc86be80AD0917Fc#code) |
| Token Guard               | [0x0d507FA4A80018168168558f6806A8D4f4a624a9](https://sepolia.basescan.org/address/0x0d507FA4A80018168168558f6806A8D4f4a624a9#code) |
| ERC4626 Risk Policy       | [0x730F97a459Eb90F016229b7585992d4e38bb7490](https://sepolia.basescan.org/address/0x730F97a459Eb90F016229b7585992d4e38bb7490#code) |
| Swap V2 Risk Policy       | [0xE343Fb214086617026C26bCb334e715586DD648B](https://sepolia.basescan.org/address/0xE343Fb214086617026C26bCb334e715586DD648B#code) |
| Liquidity V2 Risk Policy  | [0x31809a9a78Ca953EfbbF3422575ff7e4Ff1FD0Cf](https://sepolia.basescan.org/address/0x31809a9a78Ca953EfbbF3422575ff7e4Ff1FD0Cf#code) |
| Risk Report NFT           | [0xb0025D3e03191c5B7cc1ac608f6aB4cB03149885](https://sepolia.basescan.org/address/0xb0025D3e03191c5B7cc1ac608f6aB4cB03149885#code) |
| SVG Renderer              | [0x87eDc5e4f8D3663a8327E38a22e5E24f6222a637](https://sepolia.basescan.org/address/0x87eDc5e4f8D3663a8327E38a22e5E24f6222a637#code) |

---

---

## ⚠️ Disclaimer

These contracts are **experimental and unaudited**.  
They are in early-stage development . 

Do **not** use with real funds in production environments without proper audits.

---