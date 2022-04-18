import { expect } from "chai"
import { ethers, network } from "hardhat"
import { BigNumber, Contract, Signer, Wallet } from "ethers"


describe("InvestNFT", function() {
  let operator: Signer, operatorAddr: string
  let receiver: Signer, receiverAddr: string
  let owner: Signer
  let user: Signer, userAddr: string

  // Contracts
  let busd: Contract, wbnb: Contract, wbLP: Contract
  let bcnt: Contract, bbLP: Contract
  let pancakeRouter: Contract
  let gatewayImpl: Contract
  let gateway: Contract
  let erc721byTokenA: Contract, erc721byTokenB: Contract
  let erc721payableA: Contract, erc721payableB: Contract

  const MAX_INT = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

  const ownerAddr = "0xEEb991702e3472166da495B22F3349A7A3aa638a"

  const zeroAddress = "0x0000000000000000000000000000000000000000"

  const autoCompoundAddr = "0x674ABa03bCbda010115db089DF7622b8E828a306"

  before(async () => {
    [receiver, operator] = await ethers.getSigners()
    receiverAddr = await receiver.getAddress()
    operatorAddr = await operator.getAddress()

    const deciaml = 18
    const initSupply = ethers.utils.parseUnits("10000000")

    wbnb = await (
        await ethers.getContractFactory("WETH9", operator)
    ).deploy()
    const depositValue = ethers.utils.parseEther('1000')
    await wbnb.connect(operator).deposit({ value: depositValue })
    busd = await (
        await ethers.getContractFactory("mintersBEP2EToken", operator)
    ).deploy("BUSD", "BUSD", deciaml, initSupply)
    bcnt = await (
        await ethers.getContractFactory("mintersBEP2EToken", operator)
    ).deploy("BCNT", "BCNT", deciaml, initSupply)
    wbLP = await (
        await ethers.getContractFactory("StubPancakePair", operator)
    ).deploy(wbnb.address, busd.address)
    bbLP = await (
      await ethers.getContractFactory("StubPancakePair", operator)
  ).deploy(bcnt.address, busd.address)

    pancakeRouter = await (
        await ethers.getContractFactory("StubPancakeRouter", operator)
    ).deploy()
    await pancakeRouter.setLPAddr(wbnb.address, busd.address, wbLP.address)
    expect(await pancakeRouter.lpAddr(wbnb.address, busd.address)).to.equal(wbLP.address)
    await pancakeRouter.setLPAddr(bcnt.address, busd.address, bbLP.address)
    expect(await pancakeRouter.lpAddr(bcnt.address, busd.address)).to.equal(bbLP.address)

    await wbnb.connect(operator).approve(pancakeRouter.address, MAX_INT)
    await busd.connect(operator).approve(pancakeRouter.address, MAX_INT)
    await bcnt.connect(operator).approve(pancakeRouter.address, MAX_INT)

    await pancakeRouter.connect(operator).addLiquidity(
        busd.address,
        bcnt.address,
        ethers.utils.parseUnits("1000000"),
        ethers.utils.parseUnits("1000000"),
        0,
        0,
        operatorAddr,
        0
    )
    expect(await bbLP.callStatic.balanceOf(operatorAddr)).to.equal(ethers.utils.parseUnits("2000000"))

    await pancakeRouter.connect(operator).addLiquidity(
        busd.address,
        wbnb.address,
        ethers.utils.parseUnits("1000000"),
        ethers.utils.parseUnits("100"),
        0,
        0,
        operatorAddr,
        0
    )
    expect(await wbLP.callStatic.balanceOf(operatorAddr)).to.equal(ethers.utils.parseUnits("1000100"))

    const gatewayName = "InvestNFT Gateway"
    gatewayImpl = await (
        await ethers.getContractFactory("InvestNFTGateway", operator)
    ).deploy()
    const gatewayInitData = gatewayImpl.interface.encodeFunctionData("initialize", [
        gatewayName,
        wbnb.address,
        busd.address,
        bcnt.address,
        operatorAddr,
        pancakeRouter.address,
    ])
    gateway = await (
        await ethers.getContractFactory("UpgradeProxy", operator)
    ).deploy(
        gatewayImpl.address,
        gatewayInitData
    )
    gateway = gatewayImpl.attach(gateway.address)
    expect(await gateway.callStatic.implementation()).to.equal(gatewayImpl.address)
    expect(await gateway.callStatic.name()).to.equal(gatewayName)
    expect(await gateway.callStatic.wrapperNativeToken()).to.equal(wbnb.address)
    expect(await gateway.callStatic.stablecoin()).to.equal(busd.address)
    expect(await gateway.callStatic.rewardToken()).to.equal(bcnt.address)
    expect(await gateway.callStatic.operator()).to.equal(operatorAddr)
    expect(await gateway.callStatic.router()).to.equal(pancakeRouter.address)

    // Transfer ether to owner
    await operator.sendTransaction({to: ownerAddr, value: ethers.utils.parseUnits('1')})

    const receiverAmount = ethers.utils.parseUnits("2000")
    await busd.connect(operator).transfer(receiverAddr, receiverAmount)

    await network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [ownerAddr]
    })

    owner = ethers.provider.getSigner(ownerAddr)
    user = owner
    userAddr = ownerAddr

    const contractURI = "ipfs://QmYnjGeLbBhfDM8Y11F5hVMDdGQz91dFCroHT8eiygnXxC/contract.json"
    const blindBoxURI = "ipfs://QmX5CnSJjtunPUp67DwVYUBgPYR2PB18M6riqPa3vercUp/"
    const whitelist = ethers.utils.formatBytes32String("test")
    const freeMintList = ethers.utils.formatBytes32String("test")

    erc721byTokenA = await (
        await ethers.getContractFactory("stubERC721PayWithERC20", operator)
    ).deploy(contractURI, blindBoxURI, whitelist, freeMintList);

    await erc721byTokenA.connect(operator).initialize(busd.address, gateway.address)
    expect(await erc721byTokenA.callStatic.payERC20()).to.equal(busd.address)
    expect(await erc721byTokenA.callStatic.gateway()).to.equal(gateway.address)

    await gateway.connect(operator).setNftData(erc721byTokenA.address, autoCompoundAddr, zeroAddress, zeroAddress, false, 10)

    erc721byTokenB = await (
        await ethers.getContractFactory("stubERC721PayWithERC20", operator)
    ).deploy(contractURI, blindBoxURI, whitelist, freeMintList);

    await erc721byTokenB.connect(operator).initialize(busd.address, gateway.address)
    expect(await erc721byTokenB.callStatic.payERC20()).to.equal(busd.address)
    expect(await erc721byTokenB.callStatic.gateway()).to.equal(gateway.address)

    await gateway.connect(operator).setNftData(erc721byTokenB.address, autoCompoundAddr, zeroAddress, zeroAddress, false, 10)

    erc721payableA = await (
        await ethers.getContractFactory("stubERC721", operator)
    ).deploy(contractURI, blindBoxURI, whitelist, freeMintList);

    await erc721payableA.connect(operator).initialize(gateway.address)
    expect(await erc721payableA.callStatic.gateway()).to.equal(gateway.address)

    await gateway.connect(operator).setNftData(erc721payableA.address, autoCompoundAddr, zeroAddress, zeroAddress, false, 10)

    erc721payableB = await (
        await ethers.getContractFactory("stubERC721", operator)
    ).deploy(contractURI, blindBoxURI, whitelist, freeMintList);

    await erc721payableB.connect(operator).initialize(gateway.address)
    expect(await erc721payableB.callStatic.gateway()).to.equal(gateway.address)

    await gateway.connect(operator).setNftData(erc721payableB.address, autoCompoundAddr, zeroAddress, zeroAddress, false, 10)

  })

  it("Should not re-initialize", async () => {
    const gwName = "GW"
    await expect(gateway.connect(user).initialize(
        gwName,
        wbnb.address,
        busd.address,
        bcnt.address,
        operatorAddr,
        pancakeRouter.address,
    )).to.be.revertedWith("Already initialized")
  })

  it("Should not upgrade by non-owner", async () => {
    await expect(gateway.connect(receiver).upgradeTo(
        pancakeRouter.address
    )).to.be.revertedWith("Only the contract owner may perform this action")
  })

  it("NFT TokenInfo must be updated after minted", async () => {
    // transfer stablecoin to receiver
    const receiverAmount = ethers.utils.parseUnits("2000")
    expect(await busd.callStatic.balanceOf(receiverAddr)).to.equal(receiverAmount)

    // NFT price
    const price = ethers.utils.parseUnits("80")

    // approve stablecoin to NFT A contract and mint
    await busd.connect(receiver).approve(erc721byTokenA.address, price)
    await erc721byTokenA.connect(receiver).publicMint()
    expect(await erc721byTokenA.callStatic.totalSupply()).to.equal(1)
    expect(await erc721byTokenA.callStatic.balanceOf(receiverAddr)).to.equal(1)

    // tokenId: 1 baseValue
    const bva1 = await gateway.callStatic.baseValue(erc721byTokenA.address, 1, 1)

    expect(bva1[0]).to.equal(ethers.utils.parseUnits("40"))
    expect(bva1[1]).to.equal(ethers.utils.parseUnits("40"))
    expect(await gateway.callStatic.poolsWeights(autoCompoundAddr)).to.equal(ethers.utils.parseUnits("40"))

    // NFT A updated price
    const nextPrice = ethers.utils.parseUnits("100")
    await erc721byTokenA.connect(operator).setPrice(nextPrice)

    // approve stablecoin to NFT contract and mint
    await busd.connect(receiver).approve(erc721byTokenA.address, nextPrice)
    await erc721byTokenA.connect(receiver).publicMint()
    expect(await erc721byTokenA.callStatic.totalSupply()).to.equal(2)

    expect(await erc721byTokenA.callStatic.balanceOf(receiverAddr)).to.equal(2)
    expect(await erc721byTokenA.callStatic.tokenByIndex(0)).to.equal(1)
    expect(await erc721byTokenA.callStatic.tokenByIndex(1)).to.equal(2)

    // tokenId: 2 baseValue
    const bva2 = await gateway.callStatic.baseValue(erc721byTokenA.address, 2, 1)

    expect(bva2[0]).to.equal(ethers.utils.parseUnits("50"))
    expect(bva2[1]).to.equal(ethers.utils.parseUnits("50"))
    expect(await gateway.callStatic.poolsWeights(autoCompoundAddr)).to.equal(ethers.utils.parseUnits("90"))

    // approve stablecoin to NFT contract and mint
    const triplePrice = ethers.utils.parseUnits("1120")
    await busd.connect(receiver).approve(erc721byTokenB.address, triplePrice)
    await erc721byTokenB.connect(receiver).publicMint()
    await erc721byTokenB.connect(receiver).batchPublicMint(1)
    await erc721byTokenB.connect(receiver).batchPublicMint(10)
    expect(await erc721byTokenB.callStatic.totalSupply()).to.equal(12)
    expect(await erc721byTokenB.callStatic.balanceOf(receiverAddr)).to.equal(12)
    expect(await erc721byTokenB.callStatic.tokenByIndex(0)).to.equal(1)

    const bvb1 = await gateway.callStatic.baseValue(erc721byTokenA.address, 1, 1)

    expect(bvb1[0]).to.equal(ethers.utils.parseUnits("40"))
    expect(bvb1[1]).to.equal(ethers.utils.parseUnits("40"))
    expect(await gateway.callStatic.poolsWeights(autoCompoundAddr)).to.equal(ethers.utils.parseUnits("570"))
  })

  it("NFT TokenInfo must be updated after redeemed", async () => {
    await erc721byTokenA.connect(receiver).approve(gateway.address, 1)
    await gateway.connect(receiver).redeem(erc721byTokenA.address, 1, 1)
    expect (await erc721byTokenA.balanceOf(receiverAddr)).to.equal(1)

    await erc721byTokenA.connect(receiver).approve(gateway.address, 2)
    await gateway.connect(receiver).redeem(erc721byTokenA.address, 2, 1)
    expect (await erc721byTokenA.balanceOf(receiverAddr)).to.equal(0)

    expect (await erc721byTokenA.balanceOf(gateway.address)).to.equal(2)
    expect(await gateway.callStatic.poolsWeights(autoCompoundAddr)).to.equal(ethers.utils.parseUnits("480"))

    await erc721byTokenB.connect(receiver).approve(gateway.address, 1)
    await gateway.connect(receiver).redeem(erc721byTokenB.address, 1, 1)
    expect (await erc721byTokenB.balanceOf(receiverAddr)).to.equal(11)

    await erc721byTokenB.connect(receiver).approve(gateway.address, 2)
    await gateway.connect(receiver).redeem(erc721byTokenB.address, 2, 1)
    expect (await erc721byTokenB.balanceOf(receiverAddr)).to.equal(10)

    expect (await erc721byTokenB.balanceOf(gateway.address)).to.equal(2)
    expect(await gateway.callStatic.poolsWeights(autoCompoundAddr)).to.equal(ethers.utils.parseUnits("400"))

    await busd.connect(receiver).approve(erc721byTokenA.address, ethers.utils.parseUnits("100"))
    await erc721byTokenA.connect(receiver).publicMint()
    expect(await erc721byTokenA.callStatic.totalSupply()).to.equal(3)
    expect(await erc721byTokenA.callStatic.balanceOf(receiverAddr)).to.equal(1)

    const bva3 = await gateway.callStatic.baseValue(erc721byTokenA.address, 3, 1)

    expect(bva3[0]).to.equal(ethers.utils.parseUnits("50"))
    expect(bva3[1]).to.equal(ethers.utils.parseUnits("50"))
    expect (await erc721byTokenA.balanceOf(receiverAddr)).to.equal(1)
    expect(await gateway.callStatic.poolsWeights(autoCompoundAddr)).to.equal(ethers.utils.parseUnits("450"))

    await erc721byTokenA.connect(receiver).approve(gateway.address, 3)
    await gateway.connect(receiver).redeem(erc721byTokenA.address, 3, 1)
    expect (await erc721byTokenA.balanceOf(receiverAddr)).to.equal(0)

    expect(await gateway.callStatic.poolsWeights(autoCompoundAddr)).to.equal(ethers.utils.parseUnits("400"))
  })
})