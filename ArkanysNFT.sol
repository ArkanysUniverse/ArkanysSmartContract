// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract ArkanysNFT is ERC721Enumerable, Ownable, ReentrancyGuard {
    using Strings for uint256;
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    string public baseURI;
    string public constant baseExtension = ".json";
    uint256 public usdCost = 30 * 1e18; // Coût défini en USD, ajusté pour 18 décimales
    uint256 public constant maxSupply = 10000;
    uint256 public constant maxMintAmount = 10;
    bool public paused = false;
    bool public onlyWhitelisted = true; // Variable ajoutée

    AggregatorV3Interface internal immutable priceFeed;
    address public immutable signerAddress;
    address[] private payoutAddresses = [
    0x1BDd1c5a567aB35dcAA896799DBdAC6ac94c35b4,
    0x4CFF54A06fB792Cb5E75F9490D7BAb8058d62c09
    ];
    uint256[] private payoutShares = [50, 50];

    event Minted(address indexed minter, uint256 amount, uint256 totalCost);
    event Paused(bool paused);
    event UsdCostUpdated(uint256 newUsdCost);

    constructor(
        string memory name_,
        string memory symbol_,
        string memory initialBaseURI,
        address priceFeedAddress,
        address signerAddress_
    ) ERC721(name_, symbol_) Ownable(msg.sender) {
        require(signerAddress_ != address(0), "Signer address cannot be zero");
        setBaseURI(initialBaseURI);
        priceFeed = AggregatorV3Interface(priceFeedAddress);
        signerAddress = signerAddress_;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function setBaseURI(string memory newBaseURI) public onlyOwner {
        baseURI = newBaseURI;
    }

    function setUsdCost(uint256 usdCost_) public onlyOwner {
        usdCost = usdCost_ * 1e18;
        emit UsdCostUpdated(usdCost);
    }

    function getLatestPrice() public view returns (int) {
        (, int price, , ,) = priceFeed.latestRoundData();
        return price;
    }

    function getCostInEth() public view returns (uint256) {
        int ethPrice = getLatestPrice();
        require(ethPrice > 0, "Invalid ETH price");
        return (usdCost * 1e8) / uint256(ethPrice); // Chainlink retourne le prix avec 8 décimales
    }

    function verifySignature(address user, bytes memory signature) public view returns (bool) {
        bytes32 message = keccak256(abi.encodePacked(user, address(this))).toEthSignedMessageHash();
        return ECDSA.recover(message, signature) == signerAddress;
    }

    function setOnlyWhitelisted(bool state) public onlyOwner {
        onlyWhitelisted = state;
    }

    function mint(uint256 mintAmount, bytes memory signature) public payable nonReentrant {
        require(!paused, "Minting is paused");
        require(mintAmount > 0 && mintAmount <= maxMintAmount, "Cannot mint that amount at once");
        require(totalSupply() + mintAmount <= maxSupply, "Max supply exceeded");

        if (onlyWhitelisted) {
            require(verifySignature(msg.sender, signature), "Invalid signature");
        }

        uint256 totalCost = getCostInEth() * mintAmount;
        require(msg.value >= totalCost, "Insufficient ETH sent");

        for (uint256 i = 0; i < mintAmount; i++) {
            _safeMint(msg.sender, totalSupply() + 1);
        }

        distributeFunds(msg.value);

        emit Minted(msg.sender, mintAmount, totalCost);
    }

    function distributeFunds(uint256 totalReceived) internal {
        uint256 payoutLength = payoutAddresses.length;
        for (uint256 i = 0; i < payoutLength; i++) {
            (bool success, ) = payoutAddresses[i].call{value: (totalReceived * payoutShares[i]) / 100}("");
            require(success, "Transfer to payout address failed");
        }
    }

    function pause() public onlyOwner {
        paused = true;
        emit Paused(paused);
    }

    function unpause() public onlyOwner {
        paused = false;
        emit Paused(paused);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(ownerOf(tokenId) != address(0), "ERC721Metadata: URI query for nonexistent token");
        string memory currentBaseURI = _baseURI();
        return bytes(currentBaseURI).length > 0 ?
            string.concat(currentBaseURI, tokenId.toString(), baseExtension) : "";
    }

    function withdraw() public onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ether left to withdraw");
        (bool success, ) = msg.sender.call{value: balance}("");
        require(success, "Transfer failed.");
    }
}
