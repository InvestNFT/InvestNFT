// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "./interfaces/IBaseGateway.sol";
import "./interfaces/IPancakeRouter.sol";
import "./interfaces/IWeth.sol";
import "./BaseGatewayBNBChain.sol";
import "./hotpot/RewardCompoundCakeFarm.sol";
import "./LotteryVRF.sol";
import "./interfaces/ERC721PayWithERC20.sol";
import "./interfaces/IPancakePair.sol";

contract InvestNFTGatewayBNBChain is BaseGatewayBNBChain {
    using SafeERC20 for IERC20;

    VRFv2Consumer public VRFConsumer;
    mapping(uint256 => mapping(address => bool)) public requestIds;
    mapping(uint256 => mapping(address => mapping(uint256 => bool))) private winnerBoardCheck;
    mapping(uint256 => mapping(address => uint256[])) private winnerBoard;

    function initialize(
        string memory _name,
        address _wrapperNativeToken,
        address _stablecoin,
        address _rewardToken,
        address _operator,
        IPancakeRouter _router
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

    function initNftData(address _nft, address _poolA, address _poolB, address _poolC, bool _increaseable, uint256 _delta) external onlyOwner override {
        if (_poolA != address(0)) contractInfo[_nft].poolAddressA = _poolA;
        if (_poolB != address(0)) contractInfo[_nft].poolAddressB = _poolB;
        if (_poolC != address(0)) contractInfo[_nft].poolAddressC = _poolC;
        contractInfo[_nft].increaseable = _increaseable;
        contractInfo[_nft].delta = _delta;
        contractInfo[_nft].active = true;
    }

    function deposit(uint256 _tokenId, uint256 _amount) external nonReentrant supportInterface(msg.sender) payable override {
        require(contractInfo[msg.sender].active == true, "NFT data didn't be set yet");
        IWETH(wrapperNativeToken).deposit{ value: msg.value }();
    
        uint256 stablecoinAmount = _swap(msg.value, 0, wrapperNativeToken, stablecoin, address(this), 0);

        // update fomulaA balance
        address fomulaA =  contractInfo[msg.sender].poolAddressA;
        poolsWeights[fomulaA] = poolsWeights[fomulaA] + stablecoinAmount;
        poolsBalances[fomulaA] = poolsBalances[fomulaA] + stablecoinAmount;

        updateInfo(msg.sender, _tokenId, _amount, stablecoinAmount);
        emit Deposit(msg.sender, _tokenId, _amount, stablecoinAmount);
    }

    function batchDeposit(uint256 _idFrom, uint256 _offset) external nonReentrant supportInterface(msg.sender) payable override {
        require(contractInfo[msg.sender].active == true, "NFT data didn't be set yet");
        IWETH(wrapperNativeToken).deposit{ value: msg.value }();
    
        uint256 totalStablecoinAmount = _swap(msg.value, 0, wrapperNativeToken, stablecoin, address(this), 0);

        // update fomulaA balance
        address fomulaA =  contractInfo[msg.sender].poolAddressA;
        poolsWeights[fomulaA] = poolsWeights[fomulaA] + totalStablecoinAmount;
        poolsBalances[fomulaA] = poolsBalances[fomulaA] + totalStablecoinAmount;
        uint256 stablecoinAmount = totalStablecoinAmount / _offset;
        for (uint i = 0; i < _offset; i++) {
            updateInfo(msg.sender, _idFrom + i, 1, stablecoinAmount);
            emit Deposit(msg.sender, _idFrom + i, 1, stablecoinAmount);
        }
    }

    function depositWithERC20(uint256 _tokenId, uint256 _amount, address _depositToken, uint256 _depositTokenAmounts) external nonReentrant supportInterface(msg.sender) override {
        require(contractInfo[msg.sender].active == true, "NFT data didn't be set yet");
        uint256 stablecoinAmount;

        if (_depositToken == stablecoin) {
        // stablecoin
            stablecoinAmount = _depositTokenAmounts;
        } else {
        // non-stablecoin
            stablecoinAmount = _swap(_depositTokenAmounts, 0, _depositToken, stablecoin, address(this), 0);
        }

        address fomulaA =  contractInfo[msg.sender].poolAddressA;
        poolsWeights[fomulaA] = poolsWeights[fomulaA] + stablecoinAmount;
        poolsBalances[fomulaA] = poolsBalances[fomulaA] + stablecoinAmount;
        updateInfo(msg.sender, _tokenId, _amount, stablecoinAmount);
    }

    function batchDepositWithERC20(uint256 _idFrom, uint256 _offset, address _depositToken, uint256 _depositTokenAmounts) external nonReentrant supportInterface(msg.sender) override {
        require(contractInfo[msg.sender].active == true, "NFT data didn't be set yet");

        uint256 depositTokenAmount;
        if (_depositToken == stablecoin) {
        // stablecoin
            depositTokenAmount = _depositTokenAmounts / _offset;
            // update fomulaA balance
            address fomulaA =  contractInfo[msg.sender].poolAddressA;
            poolsWeights[fomulaA] = poolsWeights[fomulaA] + _depositTokenAmounts;
            poolsBalances[fomulaA] = poolsBalances[fomulaA] + _depositTokenAmounts;
            for (uint i = 0; i < _offset; i++) {
                updateInfo(msg.sender, _idFrom + i, 1, depositTokenAmount);
                emit Deposit(msg.sender, _idFrom, 1, depositTokenAmount);
            }
        } else {
        // non-stablecoin
            uint256 stablecoinAmounts = _swap(_depositTokenAmounts, 0, _depositToken, stablecoin, address(this), 0);
            // update fomulaA balance
            address fomulaA =  contractInfo[msg.sender].poolAddressA;
            poolsWeights[fomulaA] = poolsWeights[fomulaA] + stablecoinAmounts;
            poolsBalances[fomulaA] = poolsBalances[fomulaA] + stablecoinAmounts;
            depositTokenAmount = stablecoinAmounts / _offset;
            for (uint i = 0; i < _offset; i++) {
                updateInfo(msg.sender, _idFrom + i, 1, depositTokenAmount);
                emit Deposit(msg.sender, _idFrom + i, 1, depositTokenAmount);
            }
        }
    }

    function updateInfo(address _nft, uint256 _tokenId, uint256 _amount, uint256 _weight) internal {
        bytes32 infoHash = keccak256(abi.encodePacked(_nft, _tokenId));
        // update token info
        tokenInfo[infoHash].weightsFomulaA = tokenInfo[infoHash].weightsFomulaA + _weight;
        tokenInfo[infoHash].weightsFomulaB = tokenInfo[infoHash].weightsFomulaB + BASE_WEIGHTS;
        tokenInfo[infoHash].weightsFomulaC = tokenInfo[infoHash].weightsFomulaC + BASE_WEIGHTS;
        tokenInfo[infoHash].amounts = tokenInfo[infoHash].amounts + _amount;

        // update contract info
        contractInfo[_nft].weightsFomulaA = contractInfo[_nft].weightsFomulaA + _weight;
        contractInfo[_nft].weightsFomulaB = contractInfo[_nft].weightsFomulaB + BASE_WEIGHTS;
        contractInfo[_nft].weightsFomulaC = contractInfo[_nft].weightsFomulaC + BASE_WEIGHTS;
        contractInfo[_nft].amounts = contractInfo[_nft].amounts + _amount;
    }

    function baseValue(address _nft, uint256 _tokenId, uint256 _amount) public supportInterface(_nft) view override returns (uint256, uint256) {
        bytes32 infoHash = keccak256(abi.encodePacked(_nft, _tokenId));
        address fomulaA =  contractInfo[_nft].poolAddressA;
        uint256 tokenWeightsA = tokenInfo[infoHash].weightsFomulaA;
        uint256 poolsWeightA = poolsWeights[fomulaA];

        RewardCompoundCakeFarm pool = RewardCompoundCakeFarm(payable(fomulaA));
        IPancakePair lp = IPancakePair(address(pool.lp()));
        uint256 stablecoinReserve = IERC20(stablecoin).balanceOf(address(lp));
        uint256 gatewayInvestedBalanceA = pool.balanceOf(address(this));

        uint256 investedBalanceA = gatewayInvestedBalanceA > 0 ? stablecoinReserve * 2 * gatewayInvestedBalanceA / lp.totalSupply() : 0;
        uint256 totalBalanceA = investedBalanceA > 0 ? investedBalanceA + poolsBalances[fomulaA] : poolsBalances[fomulaA];
        uint256 tokenBalanceA = totalBalanceA * tokenWeightsA / poolsWeightA;

        return (tokenWeightsA * _amount, tokenBalanceA * _amount);
    }

    function tokenReward(address _nft, uint256 _tokenId, uint256 _amount) public supportInterface(_nft) view override returns (uint256)  {
        bytes32 infoHash = keccak256(abi.encodePacked(_nft, _tokenId));
        address fomulaA =  contractInfo[_nft].poolAddressA;
        uint256 simpleRewardAmount = poolsTotalRewards[fomulaA] > 0 ? 
            poolsTotalRewards[fomulaA] * tokenInfo[infoHash].weightsFomulaA  * _amount / poolsWeights[fomulaA] / tokenInfo[infoHash].amounts :
            0;
        uint256 reward = lotteryRewards[_nft][_tokenId] + simpleRewardAmount;
        return reward;
    }

    function redeem(address _nft, uint256 _tokenId, uint256 _amount, bool _isToken0) external override {
        bytes32 infoHash = keccak256(abi.encodePacked(_nft, _tokenId));
        address fomulaA =  contractInfo[_nft].poolAddressA;
        address fomulaB =  contractInfo[_nft].poolAddressB;
        address fomulaC =  contractInfo[_nft].poolAddressC;

        uint256 stablecoinTotal = IERC20(stablecoin).balanceOf(address(this));
        uint256 lpAmount = RewardCompoundCakeFarm(payable(fomulaA)).balanceOf(address(this));

        RewardCompoundCakeFarm(payable(fomulaA)).withdraw(0, 0, _isToken0 ? 100 : 0, lpAmount * tokenInfo[infoHash].weightsFomulaA / poolsWeights[fomulaA]);

        uint256 tokenBalanceA = IERC20(stablecoin).balanceOf(address(this)) - stablecoinTotal;

        require(poolsBalances[fomulaA] == 0, "Should be invested first");
        require(poolsWeights[fomulaA] >= tokenInfo[infoHash].weightsFomulaA * _amount, "poolsWeightsA insufficent");

        poolsWeights[fomulaA] = poolsWeights[fomulaA] - tokenInfo[infoHash].weightsFomulaA;

        if (poolsWeights[fomulaB] > tokenInfo[infoHash].weightsFomulaB * _amount) {
            poolsWeights[fomulaB] = poolsWeights[fomulaB] - BASE_WEIGHTS * _amount;
        }
        if (poolsWeights[fomulaC] > tokenInfo[infoHash].weightsFomulaC * _amount) {
            poolsWeights[fomulaC] = poolsWeights[fomulaC] - BASE_WEIGHTS * _amount;
        }

        contractInfo[_nft].weightsFomulaA = contractInfo[_nft].weightsFomulaA - tokenInfo[infoHash].weightsFomulaA * _amount;
        contractInfo[_nft].weightsFomulaB = contractInfo[_nft].weightsFomulaB - BASE_WEIGHTS * _amount;
        contractInfo[_nft].weightsFomulaC = contractInfo[_nft].weightsFomulaC - BASE_WEIGHTS * _amount;
        contractInfo[_nft].amounts = contractInfo[_nft].amounts - _amount;

        tokenInfo[infoHash].weightsFomulaA = tokenInfo[infoHash].weightsFomulaA - tokenInfo[infoHash].weightsFomulaA * _amount;
        tokenInfo[infoHash].weightsFomulaB = tokenInfo[infoHash].weightsFomulaB - BASE_WEIGHTS * _amount;
        tokenInfo[infoHash].weightsFomulaC = tokenInfo[infoHash].weightsFomulaC - BASE_WEIGHTS * _amount;
        tokenInfo[infoHash].amounts = tokenInfo[infoHash].amounts - _amount;
        
        if (IERC1155(_nft).supportsInterface(INTERFACE_ID_ERC1155)) {
            bytes memory data = abi.encodePacked("0");
            IERC1155(_nft).safeTransferFrom(msg.sender, address(this), _tokenId, _amount, data);
        } else {
            IERC721(_nft).safeTransferFrom(msg.sender, address(this), _tokenId);
        }
        
        IERC20(stablecoin).safeTransfer(msg.sender, tokenBalanceA);

        uint256 simpleRewardAmount;
        if (poolsTotalRewards[fomulaA] > 0) {
            simpleRewardAmount = poolsTotalRewards[fomulaA] * tokenInfo[infoHash].weightsFomulaA / poolsWeights[fomulaA];
            poolsTotalRewards[_nft] = poolsTotalRewards[_nft] - simpleRewardAmount;
        }
        IERC20(rewardToken).safeTransfer(msg.sender, simpleRewardAmount + lotteryRewards[_nft][_tokenId]);

        emit Redeem(msg.sender, _tokenId, _amount, tokenBalanceA);
    }

    function setPoolBalances(address pool, uint256 amount) external onlyOwner override {
        poolsBalances[pool] = amount;
    }

    function investWithERC20(address pool, bool isToken0, uint256 minReceivedTokenAmountSwap, uint256 minToken0AmountAddLiq, uint256 minToken1AmountAddLiq) external nonReentrant override {
        uint256 amount = poolsBalances[pool];
        IERC20(stablecoin).safeApprove(pool, amount);
        poolsBalances[pool] = 0;
        RewardCompoundCakeFarm(payable(pool)).stake(isToken0, amount, minReceivedTokenAmountSwap, minToken0AmountAddLiq, minToken1AmountAddLiq);
    }

    function getReward(address pool) external onlyOwner override {
        uint256 rewardsBefore = IERC20(rewardToken).balanceOf(address(this));

        RewardCompoundCakeFarm(payable(pool)).getReward(0, 0, 0);

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

            if (tokenInfo[infoHash].weightsFomulaC > 0) {
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
    event SelectWinner(address _nft, uint256 _tokenId, uint256 _amounts);
}