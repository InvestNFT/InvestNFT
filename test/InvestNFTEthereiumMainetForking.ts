import { expect } from "chai"
import { ethers, network } from "hardhat"
import { Contract, Signer } from "ethers"
import { fastforward } from "./utils/network"

describe.only("InvestNFT on Ethereum mainnet forking", function() {
    let operator: Signer, operatorAddr: string
    let receiver: Signer, receiverAddr: string
    let owner: Signer
    let user: Signer, userAddr: string
    let stakeOperator: Signer

    // Contracts
    let usdc: Contract, weth: Contract
    let bcnt: Contract
    let swapRouter: Contract
    let autoCompound: Contract
    let gatewayImpl: Contract, gatewayImplV2: Contract
    let gateway: Contract
    let erc721PayableA: Contract, erc721PayableB: Contract
    
    const ownerAddr = "0x8B243DC87Fb34bD1bC5491FD08B730FAdAc88756"
  
    const zeroAddress = "0x0000000000000000000000000000000000000000"
  
    const stakeAddr = "0x7bDa5706fe6F5436C63402870229370F67F247d9"
    
    const wethAddr = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"

    const usdcAddr = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"

    const bcntAddr = "0x9669890e48f330ACD88b78D63E1A6b3482652CD9"

    const curvePoolAddr = "0xA2B47E3D5c44877cca798226B7B8118F9BFb7A56"

    const routerAddr = "0xE592427A0AEce92De3Edee1F18E0157C05861564"

    const stakeOperatorAddr = "0xb0123A6B61F0b5500EA92F33F24134c814364e3a"
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
        params: [stakeOperatorAddr],
      });
      await network.provider.send("hardhat_setBalance", [
          ownerAddr,
          "0x10000000000000000000000",
        ]);
        await network.provider.send("hardhat_setBalance", [
          "0xDa2f56143BC88F1eA76986E5b14b7B7fC78E8971",
          "0x10000000000000000000000",
        ]);
        await network.provider.send("hardhat_setBalance", [
          "0xf16bE3C010f0Ea801C3AEfcF20b1fd01b9Ead0B7",
          "0x10000000000000000000000",
        ]);
        await network.provider.send("hardhat_setBalance", [
          stakeOperatorAddr,
          "0x10000000000000000000000",
        ]);

      receiver = await ethers.getSigner("0xDa2f56143BC88F1eA76986E5b14b7B7fC78E8971");
      operator = await ethers.getSigner("0xf16bE3C010f0Ea801C3AEfcF20b1fd01b9Ead0B7");
      receiverAddr = "0xDa2f56143BC88F1eA76986E5b14b7B7fC78E8971";
      operatorAddr = "0xf16bE3C010f0Ea801C3AEfcF20b1fd01b9Ead0B7";

      stakeOperator = await ethers.getSigner(stakeOperatorAddr);

      weth = await ethers.getContractAt("WETH9", wethAddr)
      usdc = await ethers.getContractAt("mintersBEP2EToken", usdcAddr)
      bcnt = await ethers.getContractAt("mintersBEP2EToken", bcntAddr)

      swapRouter = await ethers.getContractAt("IUniswapV3SwapRouter", routerAddr)

      autoCompound = await ethers.getContractAt("StakeCurveConvex", stakeAddr)

      const gatewayName = "InvestNFT Gateway"
      gatewayImpl = await (
          await ethers.getContractFactory("InvestNFTGatewayEthereum", operator)
      ).deploy()
      const gatewayInitData = gatewayImpl.interface.encodeFunctionData("initialize", [
          gatewayName,
          wethAddr,
          usdcAddr,
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
      expect(await gateway.callStatic.wrapperNativeToken()).to.equal(wethAddr)
      expect(await gateway.callStatic.stablecoin()).to.equal(usdcAddr)
      expect(await gateway.callStatic.rewardToken()).to.equal(bcntAddr)
      expect(await gateway.callStatic.operator()).to.equal(operatorAddr)
      expect(await gateway.callStatic.router()).to.equal(routerAddr)
  
      // Transfer ether to owner
      await operator.sendTransaction({to: ownerAddr, value: ethers.utils.parseUnits('100')})
  
      const depositValue = ethers.utils.parseEther('100')

      owner = ethers.provider.getSigner(ownerAddr)
      user = owner
      userAddr = ownerAddr
  
      const contractURI = "ipfs://QmYnjGeLbBhfDM8Y11F5hVMDdGQz91dFCroHT8eiygnXxC/contract.json"
      const blindBoxURI = "ipfs://QmX5CnSJjtunPUp67DwVYUBgPYR2PB18M6riqPa3vercUp/"
      const whitelist = ethers.utils.formatBytes32String("test")
      const freeMintList = ethers.utils.formatBytes32String("test")
  
      erc721PayableA = await (
          await ethers.getContractFactory("stubERC721", operator)
      ).deploy(contractURI, blindBoxURI, whitelist, freeMintList);
  
      await erc721PayableA.connect(operator).initialize(gateway.address)
      expect(await erc721PayableA.callStatic.gateway()).to.equal(gateway.address)
  
      await gateway.connect(operator).initNftData(erc721PayableA.address, stakeAddr, zeroAddress, false, 10)

      await gateway.connect(operator).setHotpotPoolToCurvePool(stakeAddr, curvePoolAddr)
    })

    it("Should not re-initialize", async () => {
      const gwName = "GW"
      await expect(gateway.connect(user).initialize(
          gwName,
          weth.address,
          usdc.address,
          bcnt.address,
          operatorAddr,
          swapRouter.address,
      )).to.be.revertedWith("Already initialized")
    })
  
    it("Should not upgrade by non-owner", async () => {
      await expect(gateway.connect(receiver).upgradeTo(
          swapRouter.address
      )).to.be.revertedWith("Only the contract owner may perform this action")
    })
  
    it("Should be able to upgrade", async () => {
      gatewayImplV2 = await (
          await ethers.getContractFactory("InvestNFTGatewayEthereum", operator)
      ).deploy()
  
      await gateway.connect(operator).upgradeTo(
        gatewayImplV2.address
      )
  
      gateway = gatewayImplV2.attach(gateway.address)
  
      const contractURI = "ipfs://QmYnjGeLbBhfDM8Y11F5hVMDdGQz91dFCroHT8eiygnXxC/contract.json"
      const blindBoxURI = "ipfs://QmX5CnSJjtunPUp67DwVYUBgPYR2PB18M6riqPa3vercUp/"
      const whitelist = ethers.utils.formatBytes32String("test")
      const freeMintList = ethers.utils.formatBytes32String("test")
  
      erc721PayableB = await (
          await ethers.getContractFactory("stubERC721", operator)
      ).deploy(contractURI, blindBoxURI, whitelist, freeMintList);
  
      await erc721PayableB.connect(operator).initialize(gateway.address)
      expect(await erc721PayableB.callStatic.gateway()).to.equal(gateway.address)
  
      await gateway.connect(operator).initNftData(erc721PayableB.address, stakeAddr, zeroAddress, false, 10)
    })
  
    it("NFT TokenInfo should be updated after minted", async () => {
      const price = ethers.utils.parseUnits("0.1")

      //NFT A contract mint
      await erc721PayableA.connect(receiver).publicMint({ value: price })
      expect(await erc721PayableA.callStatic.totalSupply()).to.equal(1)
      expect(await erc721PayableA.callStatic.balanceOf(receiverAddr)).to.equal(1)
  
      // tokenId: 1 baseValue
      const bva1 = await gateway.callStatic.baseValue(erc721PayableA.address, 1)
  
      expect(await gateway.callStatic.poolsWeights(stakeAddr)).to.equal(bva1[0])
  
      // NFT A updated price
      const nextPrice = ethers.utils.parseUnits("0.2")
      await erc721PayableA.connect(operator).setPrice(nextPrice)
  
      // approve stablecoin to NFT contract and mint
      await usdc.connect(receiver).approve(erc721PayableA.address, nextPrice)
      await erc721PayableA.connect(receiver).publicMint({ value: nextPrice })
      expect(await erc721PayableA.callStatic.totalSupply()).to.equal(2)
  
      expect(await erc721PayableA.callStatic.balanceOf(receiverAddr)).to.equal(2)
      expect(await erc721PayableA.callStatic.tokenByIndex(0)).to.equal(1)
      expect(await erc721PayableA.callStatic.tokenByIndex(1)).to.equal(2)
  
      // tokenId: 2 baseValue
      const bva2 = await gateway.callStatic.baseValue(erc721PayableA.address, 2)
  
      expect(bva2[1]).to.equal(0)
  
      // approve stablecoin to NFT contract and mint
      const batchPriceB = ethers.utils.parseUnits("1")
      await erc721PayableB.connect(receiver).publicMint({ value: price })
      await erc721PayableB.connect(receiver).batchPublicMint(1, { value: price })
      await erc721PayableB.connect(receiver).batchPublicMint(10, { value: batchPriceB })
      expect(await erc721PayableB.callStatic.totalSupply()).to.equal(12)
      expect(await erc721PayableB.callStatic.balanceOf(receiverAddr)).to.equal(12)
      expect(await erc721PayableB.callStatic.tokenByIndex(0)).to.equal(1)
  
      const bvb1 = await gateway.callStatic.baseValue(erc721PayableB.address, 1)
  
      expect(bvb1[1]).to.equal(0)
    })
  
    it("Should invest with Stablecoin", async () => {
      await gateway.connect(operator).investWithERC20(stakeAddr, false, 0)
      expect(await gateway.callStatic.poolsBalances(stakeAddr)).to.equal(0)

      const bva1 = await gateway.callStatic.baseValue(erc721PayableA.address, 1)
      const bva2 = await gateway.callStatic.baseValue(erc721PayableA.address, 2)
      const bvb1 = await gateway.callStatic.baseValue(erc721PayableB.address, 1)
      const bvb2 = await gateway.callStatic.baseValue(erc721PayableB.address, 2)
      console.log(bva1[0], bva1[1])
      console.log(bva2[0], bva2[1])
      console.log(bvb1[0], bvb1[1])
      console.log(bvb2[0], bvb2[1])
    })

    it("Pool rewards should be updated", async () => {
      expect (await gateway.callStatic.poolsTotalRewards(stakeAddr)).to.equals(0)

      await gateway.connect(operator).getReward(stakeAddr)
    })

    it("NFT TokenInfo should be updated after redeemed", async () => {
  
      console.log(await gateway.callStatic.poolsWeights(stakeAddr))
      await erc721PayableA.connect(receiver).approve(gateway.address, 1)
      await gateway.connect(receiver).redeem(erc721PayableA.address, 1, false)
      expect (await erc721PayableA.balanceOf(receiverAddr)).to.equal(1)
      console.log(await gateway.callStatic.poolsWeights(stakeAddr))
      const bva1 = await gateway.callStatic.baseValue(erc721PayableA.address, 1)
      expect(bva1[0]).to.equal(0);
      expect(bva1[1]).to.equal(0);
      await erc721PayableA.connect(receiver).approve(gateway.address, 2)
      await gateway.connect(receiver).redeem(erc721PayableA.address, 2, false)
      expect (await erc721PayableA.balanceOf(receiverAddr)).to.equal(0)
      console.log(await gateway.callStatic.poolsWeights(stakeAddr))

      expect (await erc721PayableA.balanceOf(gateway.address)).to.equal(2)
  
      await erc721PayableB.connect(receiver).approve(gateway.address, 1)
      await gateway.connect(receiver).redeem(erc721PayableB.address, 1, false)
      expect (await erc721PayableB.balanceOf(receiverAddr)).to.equal(11)
      console.log(await gateway.callStatic.poolsWeights(stakeAddr))

      await erc721PayableB.connect(receiver).approve(gateway.address, 2)
      await gateway.connect(receiver).redeem(erc721PayableB.address, 2, false)
      expect (await erc721PayableB.balanceOf(receiverAddr)).to.equal(10)
      console.log(await gateway.callStatic.poolsWeights(stakeAddr))

      expect (await erc721PayableB.balanceOf(gateway.address)).to.equal(2)
    })

    it("VRFConsumer should be set and can draw", async () => {
      await gateway.connect(operator).setVRFConsumer('0x58437Fd814ea38590340ba2EDE1592D587B63875')

      const batchPrice = ethers.utils.parseUnits("2")

      await erc721PayableA.connect(receiver).batchPublicMint(10, { value: batchPrice })

      await gateway.connect(operator).setRandomPrizeWinners(erc721PayableA.address, 4, ethers.utils.parseUnits("100"));
      await expect(gateway.connect(operator).setRandomPrizeWinners(erc721PayableA.address, 4, ethers.utils.parseUnits("100"))).to.be.revertedWith("requestId be used");
    })
  })