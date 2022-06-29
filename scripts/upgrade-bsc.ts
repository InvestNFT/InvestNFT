import { ethers } from "hardhat"
import { Contract, Signer } from "ethers"

async function main() {
  let gatewayImpl: Contract
  let operator: Signer
  operator = ethers.provider.getSigner()
  gatewayImpl = await (
      await ethers.getContractFactory("InvestNFTGateway", operator)
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