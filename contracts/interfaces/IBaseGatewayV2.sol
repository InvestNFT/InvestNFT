// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBaseGatewayV2 {

    function initNftData(address _nft, address _poolA, address _poolB, address _poolC, bool _increaseable, uint256 _delta) external;

    function deposit(uint256 _tokenId, uint256 _amount) external payable;

    function batchDeposit(uint256 _idFrom, uint256 _offset) external payable;

    function depositWithERC20(uint256 _tokenId, uint256 _amount, address _depositToken, uint256 _depositTokenAmounts) external;

    function batchDepositWithERC20(uint256 _idFrom, uint256 _offset, address _depositToken, uint256 _depositTokenAmounts) external;

    function baseValue(address _nft, uint256 _tokenId, uint256 _amount) external view returns (uint256, uint256);

    function redeem(address _nft, uint256 _tokenId, uint256 _amount, bool _isToken0) external;

    function withdraw(address _to) external;

    function withdrawWithERC20(address _token, address _to) external;

    function setPoolBalances(address pool, uint256 amount) external;

    function investWithERC20(address pool, bool isToken0, uint256 minReceivedTokenAmountSwap, uint256 minToken0AmountAddLiq, uint256 minToken1AmountAddLiq) external;

    function getReward(address pool) external;
}