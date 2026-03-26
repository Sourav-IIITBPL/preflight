When a user clicks "Swap" on a DEX like Camelot or Uniswap, the website sends a request to their wallet (like MetaMask) called eth_sendTransaction. This request contains a data field—a long string of hex code that includes the function name and all parameters, including the swap path.

Your extension can intercept this data, decode it, and run your security checks before the user ever sees the "Sign" button.

How the Preflight Extension Fetches the Path
1. The Interception Mechanism
As an extension, you inject a "provider wrapper" into the browser page. This wrapper "listens" for the eth_sendTransaction method. When Camelot tries to send a transaction to the wallet, your extension catches it first.

2. Decoding the Path from Calldata
Once you have the data hex string, you use the protocol's ABI (the "dictionary" for the contract) to decode it.

For Camelot/Uniswap V2: The path is usually the 3rd or 4th parameter in functions like swapExactTokensForTokens. It appears as an array of addresses: ["0xTokenA...", "0xTokenB..."].

For Uniswap V3: The path is "packed" into a single string of bytes (e.g., TokenA + Fee + TokenB). Your extension must slice this hex string every 20 or 23 bytes to extract each token address.