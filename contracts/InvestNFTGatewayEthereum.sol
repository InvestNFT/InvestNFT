// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "./interfaces/IBaseGateway.sol";
import "./interfaces/IUniswapV3SwapRouter.sol";
import "./interfaces/IWeth.sol";
import "./BaseGatewayEthereum.sol";
import "./hotpot/StakeCurveConvex.sol";
import "./LotteryVRF.sol";
import "./interfaces/ERC721PayWithERC20.sol";
import "./interfaces/IPancakePair.sol";
import "./compound/interfaces/ICurvePool.sol";

contract InvestNFTGatewayEthereum is BaseGatewayEthereum {
    using SafeERC20 for IERC20;

    VRFv2Consumer public VRFConsumer;
    mapping(uint256 => mapping(address => bool)) public requestIds;
    mapping(uint256 => mapping(address => mapping(uint256 => bool))) private winnerBoardCheck;
    mapping(uint256 => mapping(address => uint256[])) private winnerBoard;
    mapping(address => address) private hotpotPoolToCurvePool;

    function initialize(
        string memory _name,
        address _wrapperNativeToken,
        address _stablecoin,
        address _rewardToken,
        address _operator,
        IUniswapV3SwapRouter _router
    ) external override {
        require(keccak256(abi.encodePacked(name)) == keccak256(abi.encodePacked("")), "Already initialized");
        super.initializePausable(_operator);
        super.initializeReentrancyGuard();

        name = _name;
        wrapperNativeToken = _wrapperNativeToken;
        stablecoin = _stablecoin;
        rewardToken= _rewardToken;
        operator = _operator;
        router = _router;
    }

    function initNftData(address _nft, address _poolBase, address _poolLottery, bool _increaseable, uint256 _delta) external onlyOwner override {
        if (_poolBase != address(0)) contractInfo[_nft].poolAddressBase = _poolBase;
        if (_poolLottery != address(0)) contractInfo[_nft].poolAddressLottery = _poolLottery;
        contractInfo[_nft].increaseable = _increaseable;
        contractInfo[_nft].delta = _delta;
        contractInfo[_nft].active = true;
    }

    function deposit(uint256 _tokenId) external nonReentrant supportInterface(msg.sender) payable override {
        require(contractInfo[msg.sender].active == true, "NFT data didn't be set yet");
        IWETH(wrapperNativeToken).deposit{ value: msg.value }();
        IWETH(wrapperNativeToken).approve(address(router), msg.value);

        uint256 stablecoinAmount = convertExactWEthToStablecoin(msg.value, 0);

        // update fomulaBase balance
        address fomulaBase =  contractInfo[msg.sender].poolAddressBase;
        poolsWeights[fomulaBase] = poolsWeights[fomulaBase] + stablecoinAmount;
        poolsBalances[fomulaBase] = poolsBalances[fomulaBase] + stablecoinAmount;

        updateInfo(msg.sender, _tokenId, stablecoinAmount);
        emit Deposit(msg.sender, _tokenId, stablecoinAmount);
    }

    function batchDeposit(uint256 _idFrom, uint256 _offset) external nonReentrant supportInterface(msg.sender) payable override {
        require(contractInfo[msg.sender].active == true, "NFT data didn't be set yet");
        IWETH(wrapperNativeToken).deposit{ value: msg.value }();
        IWETH(wrapperNativeToken).approve(address(router), msg.value);

        uint256 totalStablecoinAmount = convertExactWEthToStablecoin(msg.value, 0);

        // update fomulaBase balance
        address fomulaBase =  contractInfo[msg.sender].poolAddressBase;
        poolsWeights[fomulaBase] = poolsWeights[fomulaBase] + totalStablecoinAmount;
        poolsBalances[fomulaBase] = poolsBalances[fomulaBase] + totalStablecoinAmount;
        uint256 stablecoinAmount = totalStablecoinAmount / _offset;
        for (uint i = 0; i < _offset; i++) {
            updateInfo(msg.sender, _idFrom + i, stablecoinAmount);
            emit Deposit(msg.sender, _idFrom + i, stablecoinAmount);
        }
    }

    function updateInfo(address _nft, uint256 _tokenId, uint256 _weight) internal {
        bytes32 infoHash = keccak256(abi.encodePacked(_nft, _tokenId));
        // update token info
        tokenInfo[infoHash].weightsFomulaBase = tokenInfo[infoHash].weightsFomulaBase + _weight;
        tokenInfo[infoHash].weightsFomulaLottery = tokenInfo[infoHash].weightsFomulaLottery + BASE_WEIGHTS;
        tokenInfo[infoHash].amounts = tokenInfo[infoHash].amounts + 1;

        // update contract info
        contractInfo[_nft].weightsFomulaBase = contractInfo[_nft].weightsFomulaBase + _weight;
        contractInfo[_nft].weightsFomulaLottery = contractInfo[_nft].weightsFomulaLottery + BASE_WEIGHTS;
        contractInfo[_nft].amounts = contractInfo[_nft].amounts + 1;
    }

    function baseValue(address _nft, uint256 _tokenId) public supportInterface(_nft) view override returns (uint256, uint256) {
        bytes32 infoHash = keccak256(abi.encodePacked(_nft, _tokenId));
        address fomulaBase =  contractInfo[_nft].poolAddressBase;
        uint256 tokenWeightsBase = tokenInfo[infoHash].weightsFomulaBase;
        uint256 poolsWeightBase = poolsWeights[fomulaBase];

        ICurvePool curvePool = ICurvePool(hotpotPoolToCurvePool[fomulaBase]);
        uint256 lpVirtualPrice = curvePool.get_virtual_price();
        StakeCurveConvex hotpotPool = StakeCurveConvex(payable(fomulaBase));
        // LP from invested stablecoin
        uint256 lpAmount = hotpotPool.balanceOf(address(this));
        uint256 lpTotalPrice = lpAmount * lpVirtualPrice / 1e18;

        uint256 tokenBalanceBase = lpTotalPrice * tokenWeightsBase / poolsWeightBase;
        return (tokenWeightsBase, tokenBalanceBase);
    }

    function tokenReward(address _nft, uint256 _tokenId) public supportInterface(_nft) view override returns (uint256)  {
        bytes32 infoHash = keccak256(abi.encodePacked(_nft, _tokenId));
        address fomulaBase =  contractInfo[_nft].poolAddressBase;
        uint256 simpleRewardAmount = poolsTotalRewards[fomulaBase] > 0 ? 
            poolsTotalRewards[fomulaBase] * tokenInfo[infoHash].weightsFomulaBase / poolsWeights[fomulaBase] / tokenInfo[infoHash].amounts :
            0;
        uint256 reward = lotteryRewards[_nft][_tokenId] + simpleRewardAmount;
        return reward;
    }

    function redeem(address _nft, uint256 _tokenId, bool _isToken0) external override {
        bytes32 infoHash = keccak256(abi.encodePacked(_nft, _tokenId));
        address fomulaBase =  contractInfo[_nft].poolAddressBase;
        address fomulaLottery =  contractInfo[_nft].poolAddressLottery;

        uint256 stablecoinTotal = IERC20(stablecoin).balanceOf(address(this));
        uint256 lpAmount = StakeCurveConvex(payable(fomulaBase)).balanceOf(address(this));

        StakeCurveConvex(payable(fomulaBase)).withdraw(_isToken0, 0, lpAmount * tokenInfo[infoHash].weightsFomulaBase / poolsWeights[fomulaBase]);

        uint256 tokenBalanceBase = IERC20(stablecoin).balanceOf(address(this)) - stablecoinTotal;

        require(poolsBalances[fomulaBase] == 0, "Should be invested first");
        require(poolsWeights[fomulaBase] >= tokenInfo[infoHash].weightsFomulaBase, "poolsWeightsBase insufficent");

        poolsWeights[fomulaBase] = poolsWeights[fomulaBase] - tokenInfo[infoHash].weightsFomulaBase;

        if (poolsWeights[fomulaLottery] > tokenInfo[infoHash].weightsFomulaLottery) {
            poolsWeights[fomulaLottery] = poolsWeights[fomulaLottery] - BASE_WEIGHTS;
        }

        contractInfo[_nft].weightsFomulaBase = contractInfo[_nft].weightsFomulaBase - tokenInfo[infoHash].weightsFomulaBase;
        contractInfo[_nft].weightsFomulaLottery = contractInfo[_nft].weightsFomulaLottery - BASE_WEIGHTS;
        contractInfo[_nft].amounts = contractInfo[_nft].amounts - 1;

        tokenInfo[infoHash].weightsFomulaBase = tokenInfo[infoHash].weightsFomulaBase - tokenInfo[infoHash].weightsFomulaBase;
        tokenInfo[infoHash].weightsFomulaLottery = tokenInfo[infoHash].weightsFomulaLottery - BASE_WEIGHTS;
        tokenInfo[infoHash].amounts = tokenInfo[infoHash].amounts - 1;
        
        IERC721(_nft).safeTransferFrom(msg.sender, address(this), _tokenId);
        
        IERC20(stablecoin).safeTransfer(msg.sender, tokenBalanceBase);

        uint256 simpleRewardAmount;
        if (poolsTotalRewards[fomulaBase] > 0) {
            simpleRewardAmount = poolsTotalRewards[fomulaBase] * tokenInfo[infoHash].weightsFomulaBase / poolsWeights[fomulaBase];
            poolsTotalRewards[_nft] = poolsTotalRewards[_nft] - simpleRewardAmount;
        }
        IERC20(rewardToken).safeTransfer(msg.sender, simpleRewardAmount + lotteryRewards[_nft][_tokenId]);

        emit Redeem(msg.sender, _tokenId, tokenBalanceBase);
    }

    function setPoolBalances(address pool, uint256 amount) external onlyOwner override {
        poolsBalances[pool] = amount;
    }

    function investWithERC20(address pool, bool isToken0, uint256 minReceivedTokenAmountSwap) external onlyOwner override {
        uint256 amount = poolsBalances[pool];
        IERC20(stablecoin).safeApprove(pool, amount);
        poolsBalances[pool] = 0;
        StakeCurveConvex(payable(pool)).stake(isToken0, amount, minReceivedTokenAmountSwap);
    }

    function getReward(address pool) external onlyOwner override {
        uint256 rewardsBefore = IERC20(rewardToken).balanceOf(address(this));

        StakeCurveConvex(payable(pool)).getReward();

        uint256 rewardsAfter = IERC20(rewardToken).balanceOf(address(this));

        poolsTotalRewards[pool] = poolsTotalRewards[pool] + rewardsAfter - rewardsBefore;
    }

    function setVRFConsumer(address vrf) external onlyOwner override {
        VRFConsumer = VRFv2Consumer(vrf);
    }

    function getNFTTotalSupply(ERC721PayWithERC20 _nft) internal view returns (uint256) {
        return _nft.totalSupply();
    }

    function getRandomWord(uint256 _index) internal view returns (uint256) {
        return VRFConsumer.s_randomWords(_index);
    }

    function getRequestId() internal view returns (uint256) {
        return VRFConsumer.s_requestId();
    }

    function setRandomPrizeWinners(address nft, uint256 totalWinner, uint256 prizePerWinner) external onlyOwner override {
        uint256 requestId = getRequestId();
        require(requestIds[requestId][nft] == false, "requestId be used");

        uint256 totalSupply = getNFTTotalSupply(ERC721PayWithERC20(nft));
        uint256 totalCount = totalWinner;

        for (uint256 index = 0; index < totalCount; index++) {
            
            uint256 randomWord = getRandomWord(index);
            uint256 winnerId = (randomWord % totalSupply) + 1;
            bytes32 infoHash = keccak256(abi.encodePacked(nft, winnerId));

            if (tokenInfo[infoHash].weightsFomulaLottery > 0) {
                lotteryRewards[nft][winnerId] = lotteryRewards[nft][winnerId] + prizePerWinner;
                winnerBoard[requestId][nft].push(winnerId);
                emit SelectWinner(nft, winnerId, prizePerWinner);
            }
        }
        requestIds[requestId][nft] = true;
    }
    function getWinnerBoard(uint256 requestId, address nft) external view override returns (uint256[] memory) {
        return winnerBoard[requestId][nft];
    }
    function setWinnerBoard(uint256 requestId, address nft, uint256[] memory ids) external onlyOwner override {
        winnerBoard[requestId][nft] = ids;
    }
    function complementWinner(address nft, uint256 id, uint256 prizePerWinner) external onlyOwner override {
        lotteryRewards[nft][id] = lotteryRewards[nft][id] + prizePerWinner;
    }
    function complementAndSetWinner(address nft, uint256 id, uint256 prizePerWinner) external onlyOwner override {
        lotteryRewards[nft][id] = lotteryRewards[nft][id] + prizePerWinner;
        emit SelectWinner(nft, id, prizePerWinner);
    }

    function setHotpotPoolToCurvePool(address hotpotPoolAddress, address curvePoolAddress) external onlyOwner override {
        hotpotPoolToCurvePool[hotpotPoolAddress] = curvePoolAddress;
    }

    function getHotpotPoolToCurvePool(address hotpotPoolAddress) external view override returns (address) {
        return hotpotPoolToCurvePool[hotpotPoolAddress];
    }
    event SelectWinner(address _nft, uint256 _tokenId, uint256 _amounts);
}