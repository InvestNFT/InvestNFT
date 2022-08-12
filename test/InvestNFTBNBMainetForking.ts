import { expect } from "chai"
import { ethers, network } from "hardhat"
import { Contract, Signer } from "ethers"
import { fastforward } from "./utils/network"

describe.only("InvestNFT on BNB chain mainnet forking", function() {
    let operator: Signer, operatorAddr: string
    let receiver: Signer, receiverAddr: string
    let owner: Signer
    let user: Signer, userAddr: string
    let autoCompoundOperator: Signer

    // Contracts
    let busd: Contract, wbnb: Contract, wbLP: Contract
    let bcnt: Contract, bbLP: Contract
    let pancakeRouter: Contract
    let autoCompound: Contract
    let gatewayImpl: Contract, gatewayImplV2: Contract
    let gateway: Contract
    let erc721byTokenA: Contract, erc721byTokenB: Contract
    let erc721payableA: Contract, erc721payableB: Contract
  
    const MAX_INT = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
  
    const ownerAddr = "0xEEb991702e3472166da495B22F3349A7A3aa638a"
  
    const zeroAddress = "0x0000000000000000000000000000000000000000"
  
    const autoCompoundAddr = "0x674ABa03bCbda010115db089DF7622b8E828a306"
    
    const wbnbAddr = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c"

    const busdAddr = "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56"

    const bcntAddr = "0x30FE275C988d34145851B2f2d171F88329720501"

    const wbLPAddr = "0x58F876857a02D6762E0101bb5C46A8c1ED44Dc16"

    const bbLPAddr = "0xe6ebba768fcb361b23291c81f1eba0fe573dea7f"

    const routerAddr = "0x10ED43C718714eb63d5aA57B78B54704E256024E"

    const autoCompoundOperatorAddr = "0xc8b6a9391E418aCe4F0C7f3D79ECA387f4022E45"
    before(async () => {
      await network.provider.request({
          method: "hardhat_impersonateAccount",
          params: [ownerAddr],
      });
      await network.provider.request({
          method: "hardhat_impersonateAccount",
          params: ["0xDa2f56143BC88F1eA76986E5b14b7B7fC78E8971"],
      });
      await network.provider.request({
          method: "hardhat_impersonateAccount",
          params: ["0xf16bE3C010f0Ea801C3AEfcF20b1fd01b9Ead0B7"],
      });
      await network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [autoCompoundOperatorAddr],
      });
      await network.provider.send("hardhat_setBalance", [
          ownerAddr,
          "0x1000000000000000000",
        ]);
        await network.provider.send("hardhat_setBalance", [
          "0xDa2f56143BC88F1eA76986E5b14b7B7fC78E8971",
          "0x1000000000000000000",
        ]);
        await network.provider.send("hardhat_setBalance", [
          "0xf16bE3C010f0Ea801C3AEfcF20b1fd01b9Ead0B7",
          "0x1000000000000000000",
        ]);
        await network.provider.send("hardhat_setBalance", [
          autoCompoundOperatorAddr,
          "0x1000000000000000000",
        ]);

      receiver = await ethers.getSigner("0xDa2f56143BC88F1eA76986E5b14b7B7fC78E8971");
      operator = await ethers.getSigner("0xf16bE3C010f0Ea801C3AEfcF20b1fd01b9Ead0B7");
      receiverAddr = "0xDa2f56143BC88F1eA76986E5b14b7B7fC78E8971";
      operatorAddr = "0xf16bE3C010f0Ea801C3AEfcF20b1fd01b9Ead0B7";

      autoCompoundOperator = await ethers.getSigner(autoCompoundOperatorAddr);

      wbnb = await ethers.getContractAt("WETH9", wbnbAddr)
      busd = await ethers.getContractAt("mintersBEP2EToken", busdAddr)
      bcnt = await ethers.getContractAt("mintersBEP2EToken", bcntAddr)
      wbLP = await ethers.getContractAt("StubPancakePair", wbLPAddr)
      bbLP = await ethers.getContractAt("StubPancakePair", bbLPAddr)

      pancakeRouter = await ethers.getContractAt("StubPancakeRouter", routerAddr)

      autoCompound = await ethers.getContractAt("RewardCompoundCakeFarm", autoCompoundAddr)

      await wbnb.connect(operator).approve(routerAddr, MAX_INT)
      await busd.connect(operator).approve(routerAddr, MAX_INT)
      await bcnt.connect(operator).approve(routerAddr, MAX_INT)

      const gatewayName = "InvestNFT Gateway"
      gatewayImpl = await (
          await ethers.getContractFactory("InvestNFTGateway", operator)
      ).deploy()
      const gatewayInitData = gatewayImpl.interface.encodeFunctionData("initialize", [
          gatewayName,
          wbnbAddr,
          busdAddr,
          bcntAddr,
          operatorAddr,
          routerAddr,
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
      expect(await gateway.callStatic.wrapperNativeToken()).to.equal(wbnbAddr)
      expect(await gateway.callStatic.stablecoin()).to.equal(busdAddr)
      expect(await gateway.callStatic.rewardToken()).to.equal(bcntAddr)
      expect(await gateway.callStatic.operator()).to.equal(operatorAddr)
      expect(await gateway.callStatic.router()).to.equal(routerAddr)
  
      // Transfer ether to owner
      await operator.sendTransaction({to: ownerAddr, value: ethers.utils.parseUnits('1')})
  
      const depositValue = ethers.utils.parseEther('1000')
      await wbnb.connect(operator).deposit({ value: depositValue })

      // Swap BUSD to receiver
      await pancakeRouter.connect(operator).swapExactTokensForTokens(depositValue, 0, [wbnbAddr, busdAddr], receiverAddr, 1751743450);

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
  
    it("Should be able to upgrade", async () => {
      gatewayImplV2 = await (
          await ethers.getContractFactory("InvestNFTGatewayBNBChain", operator)
      ).deploy()
  
      await gateway.connect(operator).upgradeTo(
        gatewayImplV2.address
      )
  
      gateway = gatewayImplV2.attach(gateway.address)
  
      const contractURI = "ipfs://QmYnjGeLbBhfDM8Y11F5hVMDdGQz91dFCroHT8eiygnXxC/contract.json"
      const blindBoxURI = "ipfs://QmX5CnSJjtunPUp67DwVYUBgPYR2PB18M6riqPa3vercUp/"
      const whitelist = ethers.utils.formatBytes32String("test")
      const freeMintList = ethers.utils.formatBytes32String("test")
  
      erc721payableB = await (
          await ethers.getContractFactory("stubERC721", operator)
      ).deploy(contractURI, blindBoxURI, whitelist, freeMintList);
  
      await erc721payableB.connect(operator).initialize(gateway.address)
      expect(await erc721payableB.callStatic.gateway()).to.equal(gateway.address)
  
      await gateway.connect(operator).initNftData(erc721payableB.address, autoCompoundAddr, zeroAddress, zeroAddress, false, 10)
    })
  
    it("NFT TokenInfo should be updated after minted", async () => {
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
      expect(await gateway.callStatic.poolsBalances(autoCompoundAddr)).to.equal(ethers.utils.parseUnits("570"))
    })
  
    it("Should invest with Stablecoin", async () => {
      await gateway.connect(operator).investWithERC20(autoCompoundAddr, false, 0, 0, 0)
      expect(await gateway.callStatic.poolsBalances(autoCompoundAddr)).to.equal(0)
      await gateway.callStatic.baseValue(erc721byTokenA.address, 1, 1)
    })

    it("Pool rewards should be updated", async () => {
      expect (await gateway.callStatic.poolsTotalRewards(autoCompoundAddr)).to.equals(0)

      await fastforward(3600 * 12)

      await autoCompound.connect(autoCompoundOperator).compound([0,0,0,0,0]);

      await fastforward(3600 * 12)

      await autoCompound.connect(autoCompoundOperator).compound([0,0,0,0,0]);

      await gateway.connect(operator).getReward(autoCompoundAddr)
    })

    it("NFT TokenInfo should be updated after redeemed", async () => {
  
      await erc721byTokenA.connect(receiver).approve(gateway.address, 1)
      await gateway.connect(receiver).redeem(erc721byTokenA.address, 1, 1, false)
      expect (await erc721byTokenA.balanceOf(receiverAddr)).to.equal(1)

      await erc721byTokenA.connect(receiver).approve(gateway.address, 2)
      await gateway.connect(receiver).redeem(erc721byTokenA.address, 2, 1, false)
      expect (await erc721byTokenA.balanceOf(receiverAddr)).to.equal(0)
  
      expect (await erc721byTokenA.balanceOf(gateway.address)).to.equal(2)
      expect(await gateway.callStatic.poolsWeights(autoCompoundAddr)).to.equal(ethers.utils.parseUnits("480"))
  
      await erc721byTokenB.connect(receiver).approve(gateway.address, 1)
      await gateway.connect(receiver).redeem(erc721byTokenB.address, 1, 1, false)
      expect (await erc721byTokenB.balanceOf(receiverAddr)).to.equal(11)
  
      await erc721byTokenB.connect(receiver).approve(gateway.address, 2)
      await gateway.connect(receiver).redeem(erc721byTokenB.address, 2, 1, false)
      expect (await erc721byTokenB.balanceOf(receiverAddr)).to.equal(10)
  
      expect (await erc721byTokenB.balanceOf(gateway.address)).to.equal(2)
      expect(await gateway.callStatic.poolsWeights(autoCompoundAddr)).to.equal(ethers.utils.parseUnits("400"))
    })

    it("VRFConsumer should be set and can draw", async () => {
      await gateway.connect(operator).setVRFConsumer('0xD27c45B307DC6f89e7b575F98eD5471a1250770E')

      await busd.connect(receiver).approve(erc721byTokenA.address, ethers.utils.parseUnits("1000"))
      await erc721byTokenA.connect(receiver).batchPublicMint(10)

      await gateway.connect(operator).setRandomPrizeWinners(erc721byTokenA.address, 4, ethers.utils.parseUnits("100"));
      await expect(gateway.connect(operator).setRandomPrizeWinners(erc721byTokenA.address, 4, ethers.utils.parseUnits("100"))).to.be.revertedWith("requestId be used");
    })
  })