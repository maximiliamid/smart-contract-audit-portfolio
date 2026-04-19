// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {NFTDealers} from "../src/NFTDealers.sol";
import {MockUSDC} from "../src/MockUSDC.sol";

contract NFTDealersTest is Test {
    NFTDealers public nftDealers;
    MockUSDC public usdc;
    string internal constant BASE_IMAGE = "https://images.unsplash.com/photo-1541781774459-bb2af2f05b55";
    error InvalidAddress();

    uint32 private constant MAX_BPS = 10_000;

    uint32 private constant LOW_FEE_BPS = 100; // 1%
    uint32 private constant MID_FEE_BPS = 300; // 3%
    uint32 private constant HIGH_FEE_BPS = 500; // 5%

    address public userWithCash = makeAddr("userWithCash");
    address public userWithEvenMoreCash = makeAddr("userWithEvenMoreCash");

    address public owner = makeAddr("owner");

    function setUp() public {
        usdc = new MockUSDC();
        nftDealers = new NFTDealers(owner, address(usdc), "NFTDealers", "NFTD", BASE_IMAGE, 20e6);
        usdc.mint(userWithCash, 20e6);
        usdc.mint(userWithEvenMoreCash, 200_000e6);
    }

    modifier revealed() {
        vm.prank(owner);
        nftDealers.revealCollection();
        _;
    }

    modifier whitelisted() {
        vm.prank(owner);
        nftDealers.whitelistWallet(userWithCash);
        _;
    }

    function mintNFTForTesting() private revealed whitelisted {
        vm.startBroadcast(userWithCash);
        usdc.approve(address(nftDealers), 20e6);
        nftDealers.mintNft();
        vm.stopBroadcast();
    }

    function mintAndListNFTForTesting(uint256 _tokenId, uint256 _price) private revealed whitelisted {
        vm.startBroadcast(userWithCash);
        usdc.approve(address(nftDealers), 20e6);
        nftDealers.mintNft();
        nftDealers.list(_tokenId, uint32(_price));
        vm.stopBroadcast();
    }

    function testMintNftSuccess() public {
        uint256 tokenId = 1;
        mintNFTForTesting();
        assertEq(nftDealers.ownerOf(tokenId), userWithCash);
    }

    function testCollateralLocked() public {
        mintNFTForTesting();
        assertEq(usdc.balanceOf(address(nftDealers)), 20e6);
    }

    function testListNft() public revealed {
        uint256 tokenId = 1;
        uint256 nftPrice = 1000e6;

        mintAndListNFTForTesting(tokenId, nftPrice);
        vm.startBroadcast(userWithCash);
        (address seller, uint32 price, address nft, uint256 listedTokenId, bool isActive) = nftDealers.s_listings(1);
        assertEq(seller, userWithCash);
        assertEq(price, nftPrice);
        assertEq(nft, address(nftDealers));
        assertEq(listedTokenId, tokenId);
        assertTrue(isActive);
        assertEq(usdc.balanceOf(address(nftDealers)), nftDealers.lockAmount());
        assertEq(nftDealers.collateralForMinting(tokenId), nftDealers.lockAmount());
        vm.stopBroadcast();
    }

    function testListWithWrongAddress() public revealed {
        uint256 tokenId = 1;

        mintNFTForTesting();

        vm.prank(address(0x2341999));
        vm.expectRevert("Only whitelisted users can call this function");
        nftDealers.list(tokenId, 1000e6);
    }

    function testBuyNft() public revealed {
        uint256 tokenId = 1;
        uint256 nftPrice = 1000e6;
        mintNFTForTesting();
        vm.startBroadcast(userWithCash);
        nftDealers.list(tokenId, uint32(nftPrice));
        vm.stopBroadcast();

        vm.startBroadcast(userWithEvenMoreCash);
        usdc.approve(address(nftDealers), nftPrice);
        nftDealers.buy(1);
        vm.stopBroadcast();

        (address seller, uint32 price,, uint256 listedTokenId, bool isActive) = nftDealers.s_listings(1);

        assertEq(nftDealers.ownerOf(tokenId), userWithEvenMoreCash);
        assertEq(usdc.balanceOf(seller), 0);
        assertEq(usdc.balanceOf(userWithEvenMoreCash), 199_000e6);
        assertEq(usdc.balanceOf(address(nftDealers)), nftDealers.lockAmount() + price);
        assertEq(nftDealers.collateralForMinting(listedTokenId), nftDealers.lockAmount());
        assertEq(nftDealers.ownerOf(listedTokenId), userWithEvenMoreCash);
        assertFalse(isActive);
    }

    function testBuyNftNotActive() public {
        vm.startBroadcast(userWithEvenMoreCash);
        usdc.approve(address(nftDealers), 1000e6);
        vm.expectRevert(abi.encodeWithSelector(NFTDealers.ListingNotActive.selector, 1));
        nftDealers.buy(1);
        vm.stopBroadcast();
    }

    function testSellerCantBuyHisOwnNft() public revealed {
        uint256 tokenId = 1;
        uint256 nftPrice = 1000e6;

        mintAndListNFTForTesting(tokenId, nftPrice);
        vm.startBroadcast(userWithCash);
        usdc.approve(address(nftDealers), nftPrice);
        vm.expectRevert("Seller cannot buy their own NFT");
        nftDealers.buy(1);
        vm.stopBroadcast();
    }

    function testCancelListing() public revealed {
        uint256 tokenId = 1;

        mintNFTForTesting();
        vm.startBroadcast(userWithCash);
        nftDealers.list(tokenId, 1000e6);
        vm.stopBroadcast();

        assertEq(nftDealers.totalActiveListings(), 1);
        assertEq(nftDealers.totalListings(), 1);

        vm.startBroadcast(userWithCash);
        nftDealers.cancelListing(tokenId);
        vm.stopBroadcast();

        (,,,, bool isActive) = nftDealers.s_listings(1);

        assertFalse(isActive);
        assertEq(usdc.balanceOf(address(nftDealers)), 0);
        assertEq(nftDealers.collateralForMinting(tokenId), 0);
        assertEq(nftDealers.ownerOf(tokenId), userWithCash);
        assertEq(usdc.balanceOf(userWithCash), 20e6);
        assertEq(nftDealers.balanceOf(userWithCash), 1);
        assertEq(nftDealers.balanceOf(address(nftDealers)), 0);
        assertEq(nftDealers.totalActiveListings(), 0);
        assertEq(nftDealers.totalListings(), 1);
        assertEq(nftDealers.totalMinted(), 1);
    }

    function testCancelListingNotActive() public revealed {
        mintNFTForTesting();
        vm.startBroadcast(userWithCash);
        vm.expectRevert(abi.encodeWithSelector(NFTDealers.ListingNotActive.selector, 1));
        nftDealers.cancelListing(1);
        vm.stopBroadcast();
    }

    function testCancelListingNotSeller() public revealed {
        uint256 tokenId = 1;

        mintAndListNFTForTesting(tokenId, 1000e6);

        vm.startBroadcast(userWithEvenMoreCash);
        vm.expectRevert("Only seller can cancel listing");
        nftDealers.cancelListing(1);
        vm.stopBroadcast();
        assertEq(nftDealers.totalActiveListings(), 1);
        assertEq(nftDealers.totalListings(), 1);
    }

    function testCollectUsdcFromSelling() public revealed {
        uint256 tokenId = 1;
        uint32 nftPrice = 1000e6;
        uint256 fees = nftDealers.calculateFees(nftPrice);
        uint256 collateralToReturn = nftDealers.lockAmount();
        uint256 amountToSeller = (nftPrice + collateralToReturn) - fees;

        mintAndListNFTForTesting(tokenId, nftPrice);

        vm.startBroadcast(userWithEvenMoreCash);
        usdc.approve(address(nftDealers), nftPrice);
        nftDealers.buy(1);
        vm.stopBroadcast();

        vm.prank(userWithCash);
        nftDealers.collectUsdcFromSelling(tokenId);

        assertEq(usdc.balanceOf(userWithCash), amountToSeller);
        assertEq(usdc.balanceOf(address(nftDealers)), fees);
        assertEq(nftDealers.totalFeesCollected(), fees);
    }

    function testUpdatePrice() public revealed {
        uint256 tokenId = 1;
        uint32 initialPrice = 1000e6;
        uint32 newPrice = 1500e6;

        mintAndListNFTForTesting(tokenId, initialPrice);

        vm.startBroadcast(userWithCash);
        nftDealers.updatePrice(1, newPrice);
        vm.stopBroadcast();

        (,,,, bool isActive) = nftDealers.s_listings(1);

        assertTrue(isActive);
        (address seller, uint32 price,, uint256 listedTokenId,) = nftDealers.s_listings(1);
        assertEq(seller, userWithCash);
        assertEq(price, newPrice);
        assertEq(listedTokenId, tokenId);
    }

    function testUpdatePriceNotActive() public revealed {
        uint256 tokenId = 1;
        uint32 initialPrice = 1000e6;
        uint32 newPrice = 1500e6;

        mintAndListNFTForTesting(tokenId, initialPrice);

        vm.startBroadcast(userWithCash);
        nftDealers.cancelListing(1);
        vm.expectRevert(abi.encodeWithSelector(NFTDealers.ListingNotActive.selector, 1));
        nftDealers.updatePrice(1, newPrice);
        vm.stopBroadcast();
    }

    function testWithdrawFees() public revealed {
        uint256 tokenId = 1;
        uint32 nftPrice = 1000e6;
        uint256 fees = nftDealers.calculateFees(nftPrice);

        mintAndListNFTForTesting(tokenId, nftPrice);

        vm.startBroadcast(userWithEvenMoreCash);
        usdc.approve(address(nftDealers), nftPrice);
        nftDealers.buy(1);
        vm.stopBroadcast();

        vm.prank(userWithCash);
        nftDealers.collectUsdcFromSelling(tokenId);

        vm.prank(owner);
        nftDealers.withdrawFees();

        assertEq(usdc.balanceOf(owner), fees);
        assertEq(nftDealers.totalFeesCollected(), 0);
    }

    function testNotOwnerCannotWithdrawFees() public {
        vm.prank(userWithCash);
        vm.expectRevert("Only owner can call this function");
        nftDealers.withdrawFees();
    }

    function testBaseURI() public revealed {
        assertEq(nftDealers.baseURI(), BASE_IMAGE);
    }

    function testWhitelistWallet() public revealed {
        address whitelistedWallet = makeAddr("whitelistedWallet");
        vm.prank(owner);
        nftDealers.whitelistWallet(whitelistedWallet);
        assertTrue(nftDealers.isWhitelisted(whitelistedWallet));
    }

    function testCalculateFeesMin() public view {
        uint256 price = 500e6;
        uint256 expectedFees = (price * LOW_FEE_BPS) / MAX_BPS;
        assertEq(nftDealers.calculateFees(price), expectedFees);
    }

    function testCalculateFeesMid() public view {
        uint256 price = 5500e6;
        uint256 expectedFees = (price * MID_FEE_BPS) / MAX_BPS;
        assertEq(nftDealers.calculateFees(price), expectedFees);
    }

    function testCalculateFeesHigh() public view {
        uint256 price = 15500e6;
        uint256 expectedFees = (price * HIGH_FEE_BPS) / MAX_BPS;
        assertEq(nftDealers.calculateFees(price), expectedFees);
    }
}
