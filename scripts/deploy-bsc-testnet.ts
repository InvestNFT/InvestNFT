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
      '0xae13d989dac2f0debff460ac112a837c89baa7cd',
      '0x78867bbeef44f2326bf8ddd1941a4439382ef2a7',
      '0x78867bbeef44f2326bf8ddd1941a4439382ef2a7',
      '0xf16bE3C010f0Ea801C3AEfcF20b1fd01b9Ead0B7',
      '0x9ac64cc6e4415144c455bd8e4837fea55603e5c3',
  ])
  gateway = await (
      await ethers.getContractFactory("UpgradeProxy", operator)
  ).deploy(
      gatewayImpl.address,
      gatewayInitData
  )

  console.log(gateway.address);
  console.log("Address:\n", gatewayImpl.address, "Data:\n", gatewayInitData);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });