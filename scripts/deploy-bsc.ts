import { ethers, network } from "hardhat"
import { BigNumber, Contract, Signer, Wallet } from "ethers"

async function main() {
  let gatewayImpl: Contract, gateway: Contract
  let operator: Signer
  operator = ethers.provider.getSigner()
  const gatewayName = "InvestNFT Gateway"
  gatewayImpl = await (
      await ethers.getContractFactory("InvestNFTGateway", operator)
  ).deploy()
  await gatewayImpl.deployed();
  const gatewayInitData = gatewayImpl.interface.encodeFunctionData("initialize", [
      gatewayName,
      '0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c',
      '0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56',
      '0x30FE275C988d34145851B2f2d171F88329720501',
      '0x8B243DC87Fb34bD1bC5491FD08B730FAdAc88756',
      '0x10ED43C718714eb63d5aA57B78B54704E256024E',
  ])
  gateway = await (
      await ethers.getContractFactory("UpgradeProxy", operator)
  ).deploy(
      gatewayImpl.address,
      gatewayInitData
  )

  console.log(gateway.address);
  console.log("Address:\n", gatewayImpl.address, "\nData:\n", gatewayInitData);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });