import { ethers, network } from "hardhat"
import { BigNumber, Contract, Signer, Wallet } from "ethers"

async function main() {
  let vrf: Contract
  let operator: Signer
  operator = ethers.provider.getSigner()

  vrf = await (
    await ethers.getContractFactory("VRFv2Consumer", operator)
  ).deploy(
    105,
    '0xc587d9053cd1118f25f645f9e08bb98c9712a4ee',
    '0x114f3da0a805b6a67d6e9cd2ec746f7028f1b7376365af575cfea3550dd1aa04',
    500000,
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