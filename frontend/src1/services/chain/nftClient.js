import { ethers } from 'ethers';
import { CONTRACTS, CONTRACT_ABI } from '../../shared/constants/contracts';

async function getSigner() {
  if (!window.ethereum) throw new Error('Wallet provider not found');
  const provider = new ethers.BrowserProvider(window.ethereum);
  return provider.getSigner();
}

export async function mintReportNft({ address, report }) {
  if (!CONTRACTS.riskReportNft) {
    return {
      simulated: true,
      tokenId: Date.now(),
      txHash: `sim_mint_${Date.now()}`,
      owner: address,
      report,
    };
  }

  const signer = await getSigner();
  const contract = new ethers.Contract(CONTRACTS.riskReportNft, CONTRACT_ABI.riskReportNft, signer);
  const payload = JSON.stringify(report);
  const tx = await contract.mintReport(address, payload);
  const receipt = await tx.wait();

  return {
    simulated: false,
    txHash: receipt.hash,
    tokenId: null,
    owner: address,
    report,
  };
}
