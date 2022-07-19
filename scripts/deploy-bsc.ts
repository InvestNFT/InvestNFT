import { ethers, network } from "hardhat"
import { BigNumber, Contract, Signer, Wallet } from "ethers"

async function main() {
  let gatewayImpl: Contract, gateway: Contract
  let operator: Signer
  operator = ethers.provider.getSigner()
  gatewayImpl = await (
      await ethers.getContractFactory("InvestNFTGatewayBNBChain", operator)
  ).deploy()
  await gatewayImpl.deployed();

  console.log("Address:\n", gatewayImpl.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });