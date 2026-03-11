import { ethers } from 'ethers';
import { CONTRACTS, CONTRACT_ABI } from '../../shared/constants/contracts';

function toWeiAmount(amount) {
  if (!amount) return 0n;
  try {
    return ethers.parseUnits(String(amount), 18);
  } catch {
    return 0n;
  }
}

async function getSigner() {
  if (!window.ethereum) throw new Error('Wallet provider not found');
  const provider = new ethers.BrowserProvider(window.ethereum);
  return provider.getSigner();
}

export async function executeGuardedTx({ intent, allowRisk = false }) {
  if (!CONTRACTS.router) {
    return {
      simulated: true,
      txHash: `sim_exec_${Date.now()}`,
      mode: intent.type,
    };
  }

  const signer = await getSigner();
  const contract = new ethers.Contract(CONTRACTS.router, CONTRACT_ABI.router, signer);

  if (intent.type === 'VAULT') {
    const vault = intent.payload.vaultAddress ?? ethers.ZeroAddress;
    const amount = toWeiAmount(intent.payload.amount);
    const receiver = await signer.getAddress();
    const tx = await contract.executeDeposit(vault, amount, receiver, allowRisk);
    const receipt = await tx.wait();
    return { simulated: false, txHash: receipt.hash, mode: 'VAULT' };
  }

  const pool = intent.payload.poolAddress ?? ethers.ZeroAddress;
  const tokenIn = intent.payload.tokenInAddress ?? ethers.ZeroAddress;
  const amountIn = toWeiAmount(intent.payload.amount);
  const tx = await contract.executeSwap(pool, tokenIn, amountIn, allowRisk);
  const receipt = await tx.wait();

  return {
    simulated: false,
    txHash: receipt.hash,
    mode: intent.type,
  };
}
