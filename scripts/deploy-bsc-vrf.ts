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
    '0x17cd473250a9a479dc7f234c64332ed4bc8af9e8ded7556aa6e66d83da49f470',
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