# PreFlight Frontend

## What this frontend is
PreFlight frontend is the public website for the extension-first version of the product.
It is no longer a DEX host or iframe runtime.

The website now has three responsibilities:
1. Explain what PreFlight does and why it exists.
2. Guide users through installing and activating the browser extension.
3. Let connected users view their PreFlight report portfolio.

## Product model
PreFlight is split into two user-facing surfaces:
1. `frontend/` website
   - Home
   - Install guide
   - Portfolio
2. `extension/` browser runtime
   - Runs on the real Camelot and SaucerSwap pages
   - Intercepts transaction intent before signature
   - Runs checks and shows the report UI on the live DEX page

This separation is intentional.
Wallet-critical behavior belongs on the official DEX page where the extension can see the real transaction request.

## Current website pages
### 1. Home
The home page is the main trust surface.
It explains:
1. what PreFlight verifies
2. why an extension is required
3. which DEXs are supported first
4. how the transaction verification workflow works
5. what the website does versus what the extension does

### 2. Install
The install page is for the Chrome unpacked demo flow.
It shows:
1. install checklist
2. activation steps
3. what users should expect on the live DEX page
4. browser and compatibility notes

### 3. Portfolio
The portfolio page is wallet-gated.
It shows:
1. connected wallet identity
2. on-chain RiskReport NFT discovery when configured
3. locally cached report history
4. reward point preview

## Supported DEX coverage
The website currently documents these first targets:
1. Camelot on Arbitrum
2. SaucerSwap on Hedera

The extension architecture is designed so both can live under one browser extension shell while using separate protocol adapters where needed.

## Workflow shown to users
1. User installs the PreFlight extension from the website.
2. User opens Camelot or SaucerSwap normally.
3. User activates PreFlight from the extension popup.
4. The extension injects its launcher and sidebar onto the supported DEX page.
5. User interacts with the official DEX as usual.
6. PreFlight intercepts the transaction intent before final wallet signature.
7. Off-chain CRE checks and on-chain guard reads run.
8. A report is shown to the user.
9. User mints the report NFT.
10. User executes through `PreFlightRouter`.

## Environment configuration
Optional environment variables:

```bash
VITE_PREFLIGHT_REPORT_NFT_ADDRESS=<deployed RiskReportNFT address>
VITE_PREFLIGHT_EXTENSION_ID=<chrome extension id>
```

`VITE_PREFLIGHT_REPORT_NFT_ADDRESS`
- Enables on-chain report discovery on the portfolio page.

`VITE_PREFLIGHT_EXTENSION_ID`
- Lets the site know an extension ID is configured for future handshake/status features.

## Local development
Run the frontend normally:

```bash
cd frontend
npm install
npm run dev
```

Build for production:

```bash
cd frontend
npm run build
```

Lint the codebase:

```bash
cd frontend
npm run lint
```

## Notes
1. `frontend/src` is now the single active website codebase.
2. `frontend/src1` and the `src1`-only Vite config were removed.
3. `contracts/` and `cre-simulations/` were intentionally left unchanged.
4. Live DEX interception is planned for the separate `extension/` workspace, not the website.
