import { ethers, network } from "hardhat"
import { BigNumber, Contract, Signer, Wallet } from "ethers"

async function main() {
  let vrf: Contract
  let operator: Signer
  operator = ethers.provider.getSigner()

  vrf = await (
    await ethers.getContractFactory("VRFv2Consumer", operator)
  ).deploy(
    322,
    '0x271682deb8c4e0901d1a1550ad2e64d568e69909',
    '0x8af398995b04c28e9951adb9721ef74c74f93e6a478f39e7e0777be13527e7ef',
    500000,
    3,
    4
  )

  console.log("Address:\n", vrf.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });