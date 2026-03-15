# PreFlight Extension

## Stack
- React + Vite + TypeScript
- Manifest V3
- Tailwind CSS for popup UI
- `viem` for calldata decoding
- `webextension-polyfill` in the background runtime

## What is implemented
1. Popup app with `Home` and `Portfolio` views.
2. Content script that activates on Camelot and SaucerSwap pages.
3. Injected page hook that intercepts wallet transaction requests before signature when PreFlight is active.
4. Protocol adapters for Camelot and SaucerSwap normalization.
5. Background service worker that runs mock-or-HTTP off-chain checks and stores session/report data.
6. Floating launcher, sidebar timeline, centered report view, local report storage, and execute handoff back into the page context.

## Environment variables
Optional:

```bash
VITE_PREFLIGHT_SIM_URL=<public CRE HTTP endpoint>
```

If `VITE_PREFLIGHT_SIM_URL` is not set, the extension uses a deterministic mock result so the UX remains testable.

## Local development
```bash
cd extension
npm install
npm run build
```

Load the built extension in Chrome:
1. Open `chrome://extensions`
2. Enable `Developer mode`
3. Click `Load unpacked`
4. Select `extension/dist`

## Notes
1. The popup is the control center for activation and local report history.
2. The live transaction interception and report UI run on the official DEX page through the content + injected runtime.
3. Minting and routed execution need deployed contract/runtime configuration to move beyond local evidence mode.
