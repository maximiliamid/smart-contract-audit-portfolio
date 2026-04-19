// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.34;
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract NFTDealers is ERC721 {
    using SafeERC20 for IERC20;
    using Strings for uint256;

    error InvalidAddress();
    error ListingNotActive(uint256 listingId);

    event NFT_Dealers_Listed(address indexed listedBy, uint256 listingId);
    event NFT_Dealers_ListingCanceled(uint256 listingId);
    event NFT_Dealers_Sold(address indexed soldTo, uint256 price);
    event NFT_Dealers_Price_Updated(uint256 indexed listingId, uint256 oldPrice, uint256 newPrice);
    event NFT_Dealers_Fees_Withdrawn(uint256 amount);

    uint32 private constant MAX_BPS = 10_000;

    uint32 private constant LOW_FEE_BPS = 100; // 1%
    uint32 private constant MID_FEE_BPS = 300; // 3%
    uint32 private constant HIGH_FEE_BPS = 500; // 5%

    uint256 private constant LOW_FEE_THRESHOLD = 1000e6; // 1.000 USDC
    uint256 private constant MID_FEE_THRESHOLD = 10_000e6; // 10.000 USDC

    uint256 public constant MAX_SUPPLY = 1000;
    uint256 public constant MIN_PRICE = 1e6; // 1 USDC

    uint256 public immutable lockAmount; // 20 USDC in this case
    IERC20 public immutable usdc;
    string private collectionImage;

    address public owner;
    string public collectionName;
    string public tokenSymbol;
    bool public metadataFrozen;
    bool public isCollectionRevealed;

    uint256 public totalFeesCollected;

    uint32 listingsCounter = 0;
    uint32 tokenIdCounter = 0;
    uint32 activeListingsCounter = 0;

    mapping(uint256 => Listing) public s_listings;
    mapping(uint256 => uint256) public collateralForMinting;
    mapping(address => bool) public whitelistedUsers;

    struct Listing {
        address seller;
        uint32 price;
        address nft;
        uint256 tokenId;
        bool isActive;
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "Only owner can call this function");
        _;
    }

    modifier onlyWhenRevealed() {
        require(isCollectionRevealed, "Collection is not revealed yet");
        _;
    }

    modifier onlySeller(uint256 _listingId) {
        require(s_listings[_listingId].seller == msg.sender, "Only seller can call this function");
        _;
    }

    modifier onlyWhitelisted() {
        require(whitelistedUsers[msg.sender], "Only whitelisted users can call this function");
        _;
    }

    constructor(
        address _owner,
        address _usdc,
        string memory _collectionName,
        string memory _symbol,
        string memory _collectionImage,
        uint256 _lockAmount
    ) ERC721(_collectionName, _symbol) {
        owner = _owner;
        usdc = IERC20(_usdc);
        collectionName = _collectionName;
        tokenSymbol = _symbol;
        collectionImage = _collectionImage;
        lockAmount = _lockAmount;
    }

    function revealCollection() external onlyOwner {
        isCollectionRevealed = true;
    }

    function whitelistWallet(address _wallet) external onlyOwner {
        whitelistedUsers[_wallet] = true;
    }

    function removeWhitelistedWallet(address _wallet) external onlyOwner {
        whitelistedUsers[_wallet] = false;
    }

    function _baseURI() internal view override returns (string memory) {
        return collectionImage;
    }

    function mintNft() external payable onlyWhenRevealed onlyWhitelisted {
        if (msg.sender == address(0)) revert InvalidAddress();
        require(tokenIdCounter < MAX_SUPPLY, "Max supply reached");
        require(msg.sender != owner, "Owner can't mint NFTs");

        require(usdc.transferFrom(msg.sender, address(this), lockAmount), "USDC transfer failed");

        tokenIdCounter++;

        collateralForMinting[tokenIdCounter] = lockAmount;
        _safeMint(msg.sender, tokenIdCounter);
    }

    function list(uint256 _tokenId, uint32 _price) external onlyWhitelisted {
        require(_price >= MIN_PRICE, "Price must be at least 1 USDC");
        require(ownerOf(_tokenId) == msg.sender, "Not owner of NFT");
        require(s_listings[_tokenId].isActive == false, "NFT is already listed");
        require(_price > 0, "Price must be greater than 0");

        listingsCounter++;
        activeListingsCounter++;

        s_listings[_tokenId] =
            Listing({seller: msg.sender, price: _price, nft: address(this), tokenId: _tokenId, isActive: true});
        emit NFT_Dealers_Listed(msg.sender, listingsCounter);
    }

    function buy(uint256 _listingId) external payable {
        Listing memory listing = s_listings[_listingId];
        if (!listing.isActive) revert ListingNotActive(_listingId);
        require(listing.seller != msg.sender, "Seller cannot buy their own NFT");

        activeListingsCounter--;

        bool success = usdc.transferFrom(msg.sender, address(this), listing.price);
        require(success, "USDC transfer failed");
        _safeTransfer(listing.seller, msg.sender, listing.tokenId, "");

        s_listings[_listingId].isActive = false;

        emit NFT_Dealers_Sold(msg.sender, listing.price);
    }

    function cancelListing(uint256 _listingId) external {
        Listing memory listing = s_listings[_listingId];
        if (!listing.isActive) revert ListingNotActive(_listingId);
        require(listing.seller == msg.sender, "Only seller can cancel listing");

        s_listings[_listingId].isActive = false;
        activeListingsCounter--;

        usdc.safeTransfer(listing.seller, collateralForMinting[listing.tokenId]);
        collateralForMinting[listing.tokenId] = 0;

        emit NFT_Dealers_ListingCanceled(_listingId);
    }

    function collectUsdcFromSelling(uint256 _listingId) external onlySeller(_listingId) {
        Listing memory listing = s_listings[_listingId];
        require(!listing.isActive, "Listing must be inactive to collect USDC");

        uint256 fees = _calculateFees(listing.price);
        uint256 amountToSeller = listing.price - fees;
        uint256 collateralToReturn = collateralForMinting[listing.tokenId];

        totalFeesCollected += fees;
        amountToSeller += collateralToReturn;
        usdc.safeTransfer(address(this), fees);
        usdc.safeTransfer(msg.sender, amountToSeller);
    }

    function updatePrice(uint256 _listingId, uint32 _newPrice) external onlySeller(_listingId) {
        Listing memory listing = s_listings[_listingId];
        uint256 oldPrice = listing.price;
        if (!listing.isActive) revert ListingNotActive(_listingId);
        require(_newPrice > 0, "Price must be greater than 0");

        s_listings[_listingId].price = _newPrice;
        emit NFT_Dealers_Price_Updated(_listingId, oldPrice, _newPrice);
    }

    function withdrawFees() external onlyOwner {
        require(totalFeesCollected > 0, "No fees to withdraw");
        uint256 amount = totalFeesCollected;
        totalFeesCollected = 0;
        usdc.safeTransfer(owner, amount);
        emit NFT_Dealers_Fees_Withdrawn(amount);
    }

    function calculateFees(uint256 price) external pure returns (uint256) {
        // for testing purposes, we want to be able to call this function directly to check the fee calculation logic
        // must be removed before production deployment, as it can be gamed by malicious actors to calculate the fees for a given price and then use that information to game the system
        return _calculateFees(price);
    }

    function totalMinted() external view returns (uint256) {
        return tokenIdCounter;
    }

    function totalListings() external view returns (uint256) {
        return listingsCounter;
    }

    function totalActiveListings() external view returns (uint256) {
        return activeListingsCounter;
    }

    function baseURI() external view returns (string memory) {
        return _baseURI();
    }

    function isWhitelisted(address _user) external view returns (bool) {
        return whitelistedUsers[_user];
    }

    function _calculateFees(uint256 _price) internal pure returns (uint256) {
        if (_price <= LOW_FEE_THRESHOLD) {
            return (_price * LOW_FEE_BPS) / MAX_BPS;
        } else if (_price <= MID_FEE_THRESHOLD) {
            return (_price * MID_FEE_BPS) / MAX_BPS;
        }
        return (_price * HIGH_FEE_BPS) / MAX_BPS;
    }
}
