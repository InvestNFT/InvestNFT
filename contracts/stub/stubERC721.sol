// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "../interfaces/IBaseGatewayEthereum.sol";
import "hardhat/console.sol";

contract stubERC721 is Ownable, ERC721Enumerable {
    using MerkleProof for bytes32[];

    uint256 public constant MAX_TOTAL_TOKEN_MINT = 1000;

    mapping(address => bool) public isMinted;

    bytes32 immutable private PRE_WHITELIST;
    bytes32 immutable private PRE_FREE_LIST;

    uint256 public price = 0.1 ether;

    mapping(address => bool) public whitelist;
    mapping(address => bool) public freeMintList;

    uint256 constant private BASE_VALUE_PERCENTAGE = 50;

    bool public isWhitelistEnabled = true;
    bool public isFreeMintListEnable = true;

    bool private isBlindBoxOpened = false;
    string private BLIND_BOX_URI;

    bool private isMetadataFrozen = false;
    string private contractDataURI;

    string private metadataURI;

    IBaseGatewayEthereum public gateway;

    event Withdraw(address _address, uint256 balance);
    event Initialize(IBaseGatewayEthereum _gateway);
    event SetContractDataURI(string _contractDataURI);
    event SetURI(string _uri);
    event MetadataFrozen();
    event BlindBoxOpened();
    event SetPrice(uint256 newPrice);
    event EnableWhitelist(bool enable);
    event AddWhitelist(address[] _addresses);
    event RemoveWhitelist(address[] _addresses);
    event EnableFreeMintList(bool enable);
    event AddFreeMintList(address[] _addresses);
    event RemovedFreeMintList(address[] _addresses);

    constructor(
        string memory _contractDataURI,
        string memory _blindBoxURI,
        bytes32 _whitelist,
        bytes32 _freeMintList
    ) ERC721("My NFT", "MYNFT") {
        require(keccak256(abi.encodePacked(_contractDataURI)) != keccak256(abi.encodePacked("")), "init from empty uri");
        require(keccak256(abi.encodePacked(_blindBoxURI)) != keccak256(abi.encodePacked("")), "init from empty uri");
        require(_whitelist != 0 && _freeMintList != 0, "init from the zero");
        contractDataURI = _contractDataURI;
        BLIND_BOX_URI = _blindBoxURI;
        PRE_WHITELIST = _whitelist;
        PRE_FREE_LIST = _freeMintList;
    }

    function _initialized() internal view returns (bool) {
        return !(address(gateway) == address(0));
    }

    function initialize(IBaseGatewayEthereum _gateway) onlyOwner external {
        require(!_initialized(), "Already initialized");
        gateway = _gateway;
        emit Initialize(_gateway);
    }

    function tokenURI(uint256 _tokenId) public view virtual override returns (string memory) {
        require(_exists(_tokenId), "ERC721Metadata: URI query for nonexistent token");

        if (isBlindBoxOpened) {
            return string(abi.encodePacked(metadataURI, Strings.toString(_tokenId), ".json"));
        }
        return BLIND_BOX_URI;
    }

    /// @dev https://docs.opensea.io/docs/contract-level-metadata
    function contractURI() public view returns (string memory) {
        return contractDataURI;
    }

    /// @dev Allow the deployer to change the smart contract meta-data.
    function setContractDataURI(string memory _contractDataURI) external onlyOwner {
        contractDataURI = _contractDataURI;
        emit SetContractDataURI(_contractDataURI);
    }

    /// @dev Allow the deployer to change the ERC-1155 URI
    function setURI(string memory _uri) external onlyOwner {
        require(!isMetadataFrozen, "URI Already Frozen");
        metadataURI = _uri;
        emit SetURI(_uri);
    }

    function metadataFrozen() external onlyOwner {
        isMetadataFrozen = true;
        emit MetadataFrozen();
    }

    function blindBoxOpened() external onlyOwner {
        isBlindBoxOpened = true;
        emit BlindBoxOpened();
    }

    function withdraw(address payable _address, uint256 _amount) external onlyOwner payable {
        require(_amount != 0, "Amount cannot be 0");
        _address.transfer(msg.value);
        emit Withdraw(_address, _amount);
    }

    function setPrice(uint256 newPrice) external onlyOwner {
        require(newPrice > 0, "price cannot be 0");
        price = newPrice;
        emit SetPrice(newPrice);
    }

    /// https://github.com/EthWorks/ethworks-solidity/blob/master/contracts/Whitelist.sol
    function enableWhitelist(bool enable) external onlyOwner {
        isWhitelistEnabled = enable;
        emit EnableWhitelist(enable);
    }

    function addWhitelist(address[] memory _addresses) external onlyOwner {
        for (uint256 i = 0; i < _addresses.length; i++) {
            address _address = _addresses[i];
            whitelist[_address] = true;
        }
        emit AddWhitelist(_addresses);
    }

    function removeWhitelist(address[] memory _addresses) external onlyOwner {
        for (uint256 i = 0; i < _addresses.length; i++) {
            address _address = _addresses[i];
            whitelist[_address] = false;
        }
        emit RemoveWhitelist(_addresses);
    }

    function enableFreeMintList(bool enable) external onlyOwner {
        isFreeMintListEnable = enable;
        emit EnableFreeMintList(enable);
    }

    function addFreeMintList(address[] memory _addresses) external onlyOwner {
        for (uint256 i = 0; i < _addresses.length; i++) {
            address _address = _addresses[i];
            freeMintList[_address] = true;
        }
        emit AddFreeMintList(_addresses);
    }

    function removedFreeMintList(address[] memory _addresses) external onlyOwner {
        for (uint256 i = 0; i < _addresses.length; i++) {
            address _address = _addresses[i];
            freeMintList[_address] = false;
        }
        emit RemovedFreeMintList(_addresses);
    }

    function _mint(uint256 id) internal {
        _safeMint(msg.sender, id);
    }

    function _mint(uint256 _numberTokens, bytes32[] memory proof) hasInitialized canMint(_numberTokens) external {

        if (msg.sender != owner()) {
            require(isFreeMintListEnable, "Free mint is disable");
            bytes32 leaf = keccak256(abi.encodePacked(msg.sender, _numberTokens));
            require(freeMintList[msg.sender] || proof.verify(PRE_FREE_LIST, leaf), "You need to in free mint list");
            require(!isMinted[msg.sender], "You already minted once");
        }

        isMinted[msg.sender] = true;

        uint256 id = totalSupply() + 1;

        for (uint256 i = 0; i < _numberTokens; i++) {
            _mint(id + i);
        }
    }

    function mint(uint256 id) internal {
        _safeMint(msg.sender, id);
    }

    function publicMint() hasInitialized canMint(1) external payable {
        require(msg.value >= price, "Insufficent amount for publicMint");
        uint256 investPrice = msg.value * BASE_VALUE_PERCENTAGE / 100;
        uint256 id = totalSupply() + 1;
        mint(id);
        gateway.deposit{ value: investPrice }(id);
    }

    function batchPublicMint(uint256 _numberTokens) hasInitialized canMint(_numberTokens) external payable {
        uint256 unitPrice = price;
        require(msg.value >= unitPrice * _numberTokens, "Insufficent amount for batchPublicMint");
        uint256 investPrice = msg.value * BASE_VALUE_PERCENTAGE / 100;
        uint256 id = totalSupply() + 1;

        for (uint256 i = 0; i < _numberTokens; i++) {
            mint(id + i);
        }
        gateway.batchDeposit{ value: investPrice }(id, _numberTokens);
    }
    modifier hasInitialized() {
        require(_initialized(), "Not initialized yet!");
        _;
    }

    modifier canMint(uint256 _amount) {
        require(_amount > 0, "Amount cannot be 0");
        require(totalSupply() + _amount <= MAX_TOTAL_TOKEN_MINT, "Over maximum minted amount");
        _;
    }
}