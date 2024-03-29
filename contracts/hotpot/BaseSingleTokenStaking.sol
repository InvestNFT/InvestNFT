pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "../upgrade/Pausable.sol";
import "../upgrade/ReentrancyGuard.sol";
import "../interfaces/IStakingRewards.sol";
import "../interfaces/IConverter.sol";
import "../interfaces/IWeth.sol";

// Modified from https://docs.synthetix.io/contracts/source/contracts/stakingrewards
/// @title A wrapper contract over StakingRewards contract that allows single asset in/out.
/// 1. User provide token0 or token1
/// 2. contract converts half to the other token and provide liquidity
/// 3. stake into underlying StakingRewards contract
/// @notice Asset tokens are token0 and token1. Staking token is the LP token of token0/token1.
abstract contract BaseSingleTokenStaking is ReentrancyGuard, Pausable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    string public name;
    IConverter public converter;
    IERC20 public lp;
    IERC20 public token0;
    IERC20 public token1;

    IStakingRewards public stakingRewards;
    bool public isToken0RewardsToken;

    /// @dev Piggyback on StakingRewards' reward accounting
    mapping(address => uint256) internal _userRewardPerTokenPaid;
    mapping(address => uint256) internal _rewards;

    uint256 internal _totalSupply;
    mapping(address => uint256) internal _balances;

    /* ========== FALLBACKS ========== */

    receive() external payable {}

    /* ========== VIEWS ========== */

    /// @dev Get the implementation contract of this proxy contract.
    /// Only to be used on the proxy contract. Otherwise it would return zero address.
    function implementation() external view returns (address) {
        return _getImplementation();
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    /// @notice Get the reward earned by specified account.
    function earned(address account) public virtual view returns (uint256) {}

    /* ========== MUTATIVE FUNCTIONS ========== */

    function _convertAndAddLiquidity(
        bool isToken0,
        bool shouldTransferFromSender, 
        uint256 amount,
        uint256 minReceivedTokenAmountSwap,
        uint256 minToken0AmountAddLiq,
        uint256 minToken1AmountAddLiq
    ) internal returns (uint256 lpAmount) {
        require(amount > 0, "Cannot stake 0");
        uint256 lpAmountBefore = lp.balanceOf(address(this));
        uint256 token0AmountBefore = token0.balanceOf(address(this));
        uint256 token1AmountBefore = token1.balanceOf(address(this));

        // Convert and add liquidity
        if (isToken0) {
            if (shouldTransferFromSender) {
                token0.safeTransferFrom(msg.sender, address(this), amount);
            }
            token0.safeApprove(address(converter), amount);
            converter.convertAndAddLiquidity(
                address(token0),
                amount,
                address(token1),
                minReceivedTokenAmountSwap,
                minToken0AmountAddLiq,
                minToken1AmountAddLiq,
                address(this)
            );
        } else {
            if (shouldTransferFromSender) {
                token1.safeTransferFrom(msg.sender, address(this), amount);
            }

            token1.safeApprove(address(converter), amount);
            converter.convertAndAddLiquidity(
                address(token1),
                amount,
                address(token0),
                minReceivedTokenAmountSwap,
                minToken0AmountAddLiq,
                minToken1AmountAddLiq,
                address(this)
            );
        }

        uint256 lpAmountAfter = lp.balanceOf(address(this));
        uint256 token0AmountAfter = token0.balanceOf(address(this));
        uint256 token1AmountAfter = token1.balanceOf(address(this));

        lpAmount = (lpAmountAfter - lpAmountBefore);

        // Return leftover token to msg.sender
        if (shouldTransferFromSender && (token0AmountAfter - token0AmountBefore) > 0) {
            token0.safeTransfer(msg.sender, (token0AmountAfter - token0AmountBefore));
        }
        if (shouldTransferFromSender && (token1AmountAfter - token1AmountBefore) > 0) {
            token1.safeTransfer(msg.sender, (token1AmountAfter - token1AmountBefore));
        }
    }

    /// @notice Taken token0 or token1 in, convert half to the other token, provide liquidity and stake
    /// the LP tokens into StakingRewards contract. Leftover token0 or token1 will be returned to msg.sender.
    /// @param isToken0 Determine if token0 is the token msg.sender going to use for staking, token1 otherwise
    /// @param amount Amount of token0 or token1 to stake
    /// @param minReceivedTokenAmountSwap Minimum amount of token0 or token1 received when swapping one for the other
    /// @param minToken0AmountAddLiq The minimum amount of token0 received when adding liquidity
    /// @param minToken1AmountAddLiq The minimum amount of token1 received when adding liquidity
    function stake(
        bool isToken0,
        uint256 amount,
        uint256 minReceivedTokenAmountSwap,
        uint256 minToken0AmountAddLiq,
        uint256 minToken1AmountAddLiq
    ) public virtual nonReentrant notPaused updateReward(msg.sender) {
        uint256 lpAmount = _convertAndAddLiquidity(isToken0, true, amount, minReceivedTokenAmountSwap, minToken0AmountAddLiq, minToken1AmountAddLiq);
        lp.safeApprove(address(stakingRewards), lpAmount);
        stakingRewards.stake(lpAmount);

        // Top up msg.sender's balance
        _totalSupply = _totalSupply + lpAmount;
        _balances[msg.sender] = _balances[msg.sender] + lpAmount;
        emit Staked(msg.sender, lpAmount);
    }

    /// @notice Take LP tokens and stake into StakingRewards contract.
    /// @param lpAmount Amount of LP tokens to stake
    function stakeWithLP(uint256 lpAmount) public virtual nonReentrant notPaused updateReward(msg.sender) {
        lp.safeTransferFrom(msg.sender, address(this), lpAmount);
        lp.safeApprove(address(stakingRewards), lpAmount);
        stakingRewards.stake(lpAmount);

        // Top up msg.sender's balance
        _totalSupply = _totalSupply + lpAmount;
        _balances[msg.sender] = _balances[msg.sender] + lpAmount;
        emit Staked(msg.sender, lpAmount);
    }

    /// @notice Take native tokens, convert to wrapped native tokens, convert half to the other token, provide liquidity and stake
    /// the LP tokens into StakingRewards contract. Leftover token0 or token1 will be returned to msg.sender.
    /// @param minReceivedTokenAmountSwap Minimum amount of token0 or token1 received when swapping one for the other
    /// @param minToken0AmountAddLiq The minimum amount of token0 received when adding liquidity
    /// @param minToken1AmountAddLiq The minimum amount of token1 received when adding liquidity
    function stakeWithNative(
        uint256 minReceivedTokenAmountSwap,
        uint256 minToken0AmountAddLiq,
        uint256 minToken1AmountAddLiq
    ) public payable virtual nonReentrant notPaused updateReward(msg.sender) {}

    /// @notice Withdraw stake from StakingRewards, remove liquidity and convert one asset to another.
    /// @param minToken0AmountConverted The minimum amount of token0 received when removing liquidity
    /// @param minToken1AmountConverted The minimum amount of token1 received when removing liquidity
    /// @param token0Percentage Determine what percentage of token0 to return to user. Any number between 0 to 100
    /// @param amount Amount of stake to withdraw
    function withdraw(
        uint256 minToken0AmountConverted,
        uint256 minToken1AmountConverted,
        uint256 token0Percentage,
        uint256 amount
    ) public virtual nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");

        // Update records:
        // substract withdrawing LP amount from total LP amount staked
        _totalSupply = (_totalSupply - amount);
        // substract withdrawing LP amount from user's balance
        _balances[msg.sender] = (_balances[msg.sender] - amount);

        // Withdraw
        stakingRewards.withdraw(amount);

        lp.safeApprove(address(converter), amount);
        converter.removeLiquidityAndConvert(
            IPancakePair(address(lp)),
            amount,
            minToken0AmountConverted,
            minToken1AmountConverted,
            token0Percentage,
            msg.sender
        );

        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Withdraw LP tokens from StakingRewards contract and return to user.
    /// @param lpAmount Amount of LP tokens to withdraw
    function withdrawWithLP(uint256 lpAmount) public virtual nonReentrant notPaused updateReward(msg.sender) {
        require(lpAmount > 0, "Cannot withdraw 0");

        // Update records:
        // substract withdrawing LP amount from total LP amount staked
        _totalSupply = (_totalSupply - lpAmount);
        // substract withdrawing LP amount from user's balance
        _balances[msg.sender] = (_balances[msg.sender] - lpAmount);

        // Withdraw
        stakingRewards.withdraw(lpAmount);

        lp.safeTransfer(msg.sender, lpAmount);

        emit Withdrawn(msg.sender, lpAmount);
    }

    function _validateIsNativeToken() internal view returns (address, bool) {
        address NATIVE_TOKEN = converter.NATIVE_TOKEN();
        bool isToken0 = NATIVE_TOKEN == address(token0);
        require(isToken0 || NATIVE_TOKEN == address(token1), "Native token is not either token0 or token1");
        return (NATIVE_TOKEN, isToken0);
    }

    /// @notice Withdraw stake from StakingRewards, remove liquidity and convert one asset to another.
    /// @param minToken0AmountConverted The minimum amount of token0 received when removing liquidity
    /// @param minToken1AmountConverted The minimum amount of token1 received when removing liquidity
    /// @param amount Amount of stake to withdraw
    function withdrawWithNative(
        uint256 minToken0AmountConverted,
        uint256 minToken1AmountConverted,
        uint256 amount
    ) public virtual nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        (address NATIVE_TOKEN, bool isToken0) = _validateIsNativeToken();

        // Update records:
        // substract withdrawing LP amount from total LP amount staked
        _totalSupply = (_totalSupply - amount);
        // substract withdrawing LP amount from user's balance
        _balances[msg.sender] = (_balances[msg.sender] - amount);

        // Withdraw
        stakingRewards.withdraw(amount);

        // Convert to wrapped native token
        uint256 balBefore = IERC20(NATIVE_TOKEN).balanceOf(address(this));
        lp.safeApprove(address(converter), amount);
        converter.removeLiquidityAndConvert(
            IPancakePair(address(lp)),
            amount,
            minToken0AmountConverted,
            minToken1AmountConverted,
            isToken0 ? 100 : 0,
            address(this)
        );
        uint256 balAfter = IERC20(NATIVE_TOKEN).balanceOf(address(this));
        // Withdraw native token and send to user
        IWETH(NATIVE_TOKEN).withdraw(balAfter - balBefore);
        payable(msg.sender).transfer(balAfter - balBefore);

        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Get the reward out and convert one asset to another.
    function getReward(uint256 token0Percentage, uint256 minTokenAmountConverted) public virtual updateReward(msg.sender) {}

    /// @notice Get the reward out and convert one asset to another.
    function getRewardWithNative(uint256 minTokenAmountConverted) public virtual updateReward(msg.sender) {}

    /// @notice Withdraw all stake from StakingRewards, remove liquidity, get the reward out and convert one asset to another.
    function exit(uint256 minTokenAmountConverted, uint256 minToken0AmountConverted, uint256 minToken1AmountConverted, uint256 token0Percentage) external virtual {}

    /// @notice Withdraw LP tokens from StakingRewards and return to user. Get the reward out and convert one asset to another.
    function exitWithLP(uint256 token0Percentage, uint256 minTokenAmountConverted) external virtual {}

    /// @notice Withdraw all stake from StakingRewards, remove liquidity, get the reward out and convert one asset to another
    /// @param token0Percentage Determine what percentage of token0 to return to user. Any number between 0 to 100
    /// @param minToken0AmountConverted The minimum amount of token0 received when removing liquidity
    /// @param minToken1AmountConverted The minimum amount of token1 received when removing liquidity
    /// @param minTokenAmountConverted The minimum amount of token0 or token1 received when converting reward token to either one of them
    function exitWithNative(uint256 token0Percentage, uint256 minToken0AmountConverted, uint256 minToken1AmountConverted, uint256 minTokenAmountConverted) external virtual {
        withdrawWithNative(minToken0AmountConverted, minToken1AmountConverted, _balances[msg.sender]);
        getReward(token0Percentage, minTokenAmountConverted);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        require(tokenAddress != address(lp), "Cannot withdraw the staking token");
        IERC20(tokenAddress).safeTransfer(owner, tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {}

    /* ========== MODIFIERS ========== */

    modifier updateReward(address account) virtual {
        uint256 rewardPerTokenStored = stakingRewards.rewardPerToken();
        if (account != address(0)) {
            _rewards[account] = earned(account);
            _userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    /* ========== EVENTS ========== */

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event Recovered(address token, uint256 amount);
}