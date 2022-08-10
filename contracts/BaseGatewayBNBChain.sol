// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "./upgrade/Pausable.sol";
import "./upgrade/ReentrancyGuard.sol";
import "./interfaces/IPancakeRouter.sol";
import "./interfaces/IWeth.sol";
import "./interfaces/IBaseGatewayV2.sol";
import "hardhat/console.sol";

abstract contract BaseGatewayBNBChain is ERC721Holder, ERC1155Holder, ReentrancyGuard, Pausable, UUPSUpgradeable, IBaseGatewayV2 {
    using SafeERC20 for IERC20;
    //https://stackoverflow.com/questions/69706835/how-to-check-if-the-token-on-opensea-is-erc721-or-erc1155-using-node-js
    bytes4 internal constant INTERFACE_ID_ERC721 = 0x80ac58cd;
    bytes4 internal constant INTERFACE_ID_ERC1155 = 0xd9b67a26;
    uint256 public constant BASE_WEIGHTS = 1000000;
    uint256 internal constant DEFAULT_SWAP_DEADLINE_IN_SECOND = 60;

    // weights for different fomula
    struct NFTTokenInfo {
        // list of weights by fomula
        uint256 weightsFomulaA;
        uint256 weightsFomulaB;
        uint256 weightsFomulaC;
        uint256 amounts;
    }
    struct NFTContractInfo {
        // list of weights by fomula
        uint256 weightsFomulaA;
        uint256 weightsFomulaB;
        uint256 weightsFomulaC;
        // pool address for each fomula
        address poolAddressA;
        address poolAddressB;
        address poolAddressC;
        uint256 amounts; // total deposit token amount
        bool increaseable; // applying for the secondary markets transaction weights increasement or not
        uint256 delta; // percentage for each valid transaction increaced
        bool active;
    }

    // key was packed by contract address and token Id
    mapping(bytes32 => NFTTokenInfo) public tokenInfo;
    mapping(bytes32 => uint256) public tokenRewardBalance; // for periodic settlement of lottery reward token
    mapping(address => NFTContractInfo) public contractInfo;
    mapping(address => uint256) public poolsWeights;
    mapping(address => uint256) public poolsBalances;

    string public name;
    address public wrapperNativeToken;
    address public stablecoin;
    address public rewardToken;
    address public operator;
    IPancakeRouter public router;

    uint256 public weightPowerMaximum = 3;

    mapping(address => uint256) public poolsTotalRewards;
    mapping(address => mapping(uint256 => uint256)) public lotteryRewards;

    function initialize(string memory _name, address _wrapperNativeToken, address _stablecoin, address _rewardToken, address _owner, IPancakeRouter _router) virtual external {}

    function implementation() external view returns (address) {
        return _getImplementation();
    }

    function withdraw(address _to) external override onlyOwner {
        uint256 balance = address(this).balance;

        require(payable(_to).send(balance), "Fail to withdraw");

        emit Withdraw(_to, balance);
    }

    function withdrawWithERC20(address _token, address _to) external override onlyOwner {
        uint256 balance = IERC20(_token).balanceOf(address(this));

        IERC20(_token).transfer(_to, balance);

        emit WithdrawERC20(_token, _to, balance);
    }

    function _swap(uint256 _swapAmount, uint256 _minReceiveAmount, address _in, address _out, address _recipient, uint256 _swapDeadlineInSecond) internal returns (uint256) {
        if (_swapAmount == 0) return 0;

        IERC20(_in).safeApprove(address(router), _swapAmount);

        uint256 dealline = _swapDeadlineInSecond > 0 ? _swapDeadlineInSecond : DEFAULT_SWAP_DEADLINE_IN_SECOND;
        address[] memory path;
        if (_in == wrapperNativeToken || _out == wrapperNativeToken) {
            path = new address[](2);
            path[0] = _in;
            path[1] = _out;
        } else {
            path = new address[](3);
            path[0] = _in;
            path[1] = wrapperNativeToken;
            path[2] = _out;
        }
        uint256[] memory amounts = router.swapExactTokensForTokens(
            _swapAmount,
            _minReceiveAmount,
            path,
            _recipient,
            block.timestamp + dealline
        );

        if (_in == wrapperNativeToken || _out == wrapperNativeToken) {
            return amounts[1];
        } else {
            return amounts[2];
        }
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {}

    function setWeightPowerMaximum (uint256 _weight) external override onlyOwner {
        weightPowerMaximum = _weight;
    }

    modifier supportInterface(address _nft) {
        require(IERC1155(_nft).supportsInterface(INTERFACE_ID_ERC1155) || IERC721(_nft).supportsInterface(INTERFACE_ID_ERC721), "Address is not ERC1155 or ERC721");
        _;
    }

    event Withdraw(address _to, uint256 balance);
    event WithdrawERC20(address _token, address _to, uint256 balance);
    event Deposit(address _nft, uint256 _tokenId, uint256 _amounts, uint256 _value);
    event Redeem(address _nft, uint256 _tokenId, uint256 _amounts, uint256 _value);
}