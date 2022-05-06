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

contract InvestNFTGatewayBNBChain is BaseGatewayBNBChain {
    using SafeERC20 for IERC20;

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
        tokenInfo[infoHash].weightsFomulaB = BASE_WEIGHTS;
        tokenInfo[infoHash].weightsFomulaC = BASE_WEIGHTS;
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
        uint256 totalBalanceA = poolsWeights[fomulaA]; // with hotpot, this value will be the sum of deposit and profit.
        uint256 tokenBalanceA = totalBalanceA * tokenWeightsA / poolsWeightA;

        return (tokenWeightsA * _amount, tokenBalanceA * _amount);
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

        uint256 rewardAmount;
        if (poolsRewards[fomulaA] > 0) {
            rewardAmount = poolsRewards[fomulaA] * tokenInfo[infoHash].weightsFomulaA / poolsWeights[fomulaA];
        }
        IERC20(rewardToken).safeTransfer(msg.sender, rewardAmount);

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

        poolsRewards[pool] = poolsRewards[pool] + rewardsAfter - rewardsBefore;
    }
}