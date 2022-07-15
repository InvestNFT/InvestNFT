import { ethers, network } from "hardhat"
import { BigNumber, Contract, Signer, Wallet } from "ethers"

async function main() {
  let vrf: Contract
  let operator: Signer
  operator = ethers.provider.getSigner()

  vrf = await (
      await ethers.getContractFactory("VRFv2Consumer", operator)
  ).deploy(
    1244,
    '0x6a2aad07396b36fe02a22b33cf443582f682c82f',
    '0xd4bb89654db74673a187bd804519e65e3f71a52bc55f11da7601a13dcf505314',
    1000000,
    3,
    4,
  )

  console.log("Address:\n", vrf.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });