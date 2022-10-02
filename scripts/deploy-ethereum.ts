import { ethers, network } from "hardhat"
import { BigNumber, Contract, Signer, Wallet } from "ethers"

async function main() {
  let gatewayImpl: Contract, gateway: Contract
  let operator: Signer
  operator = ethers.provider.getSigner()

  const gatewayName = "InvestNFT Gateway"
  const WETH = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
  const USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
  const BCNT = "0x9669890e48f330ACD88b78D63E1A6b3482652CD9"
  const operatorAddr = "0x8B243DC87Fb34bD1bC5491FD08B730FAdAc88756"
  const routerAddr = "0xE592427A0AEce92De3Edee1F18E0157C05861564"
  const redeemableTime = 1680278400

  gatewayImpl = await (
      await ethers.getContractFactory("InvestNFTGatewayEthereum", operator)
  ).deploy()
  await gatewayImpl.deployed();

  const gatewayInitData = gatewayImpl.interface.encodeFunctionData("initialize", [
      gatewayName,
      WETH,
      USDC,
      BCNT,
      operatorAddr,
      routerAddr,
      redeemableTime,
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