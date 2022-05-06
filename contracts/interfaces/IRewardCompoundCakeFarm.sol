// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IRewardCompoundCakeFarm {
    // Views

    function _share(address account) external view returns (uint256);

    function _shareTotal() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function earned(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    // Mutative

    function exit(uint256 minToken0AmountConverted, uint256 minToken1AmountConverted, uint256 minRewardTokenAmountConverted, uint256 token0Percentage) external;

    function getReward(uint256 minToken0AmountConverted, uint256 minToken1AmountConverted, uint256 minRewardTokenAmountConverted) external;

    function stake(bool isToken0, uint256 amount, uint minReceivedTokenAmountSwap, uint256 minToken0AmountAddLiq, uint256 minToken1AmountAddLiq) external;

    function withdraw(uint256 minToken0AmountConverted, uint256 minToken1AmountConverted, uint256 token0Percentage, uint256 amount) external;
}