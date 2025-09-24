// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8;

import {Test, console} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {DeployNFTMarketplace, HelperConfig, NFTMarketplace} from "script/NFTMarketplace.s.sol";
import {MockERC721} from "test/mocks/MockERC721.sol";

contract NFTMarketplaceTest is Test {
    DeployNFTMarketplace deployer;
    HelperConfig helperConfig;
    NFTMarketplace nftMarketplace;
    HelperConfig.NetworkConfig config;
    MockERC721 mockNFT;

    address user = makeAddr("user");
    address token1 = makeAddr("token1");
    address token2 = makeAddr("token2");
    uint256 tokenId = 1;
    address nativeToken;

    uint256 constant LISTING_PRICE = 1 ether;
    uint256 immutable expiry = block.timestamp + 7 days;

    function setUp() external {
        deployer = new DeployNFTMarketplace();
        (nftMarketplace, helperConfig) = deployer.run();
        config = helperConfig.getConfig();
        nativeToken = nftMarketplace.NATIVE_TOKEN();

        mockNFT = new MockERC721();
        mockNFT.mint(user, tokenId);
        vm.prank(user);
        mockNFT.approve(address(nftMarketplace), tokenId);
    }

    // ========================== CONSTRUCTOR/INITIALIZATION TEST =============================
    function test_ConstructorRevertIFProtocolFeeTooHigh() public {
        vm.expectRevert(NFTMarketplace.NFTMarketplace__FeeTooHigh.selector);
        new NFTMarketplace(5_000, config.treasury);
    }

    function test_ConstructorRevertIFTreasuryIsZeroAddress() public {
        vm.expectRevert(NFTMarketplace.NFTMarketplace__InvalidTreasury.selector);
        new NFTMarketplace(config.protocolFee, address(0));
    }

    function test_ConstructorShouldInitializeCorrectly() public view {
        assertEq(nftMarketplace.s_treasury(), config.treasury);
        assertEq(nftMarketplace.s_protocolFee(), config.protocolFee);
        assertEq(nftMarketplace.getSupportedTokens().length, 1);
        assertEq(nftMarketplace.getSupportedTokens()[0], nativeToken);
    }

    // ========================== PAYMENT TOKEN MANAGEMENT TESTS =============================
    function test_AddPaymentToken() public {
        vm.prank(nftMarketplace.owner());
        nftMarketplace.addPaymentToken(token1);

        address[] memory tokens = nftMarketplace.getSupportedTokens();
        assertEq(tokens.length, 2);
        assertEq(tokens[0], nativeToken);
        assertEq(tokens[1], token1);
    }

    function test_AddPaymentTokenRevertWhenNotOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        nftMarketplace.addPaymentToken(token1);
    }

    function test_AddPaymentTokenEmitsEvent() public {
        vm.prank(nftMarketplace.owner());
        vm.expectEmit(true, true, true, true);
        emit NFTMarketplace.PaymentTokenAdded(token1);
        nftMarketplace.addPaymentToken(token1);
    }

    function test_AddPaymentTokenRevertWhenNativeToken() public {
        vm.prank(nftMarketplace.owner());
        vm.expectRevert(NFTMarketplace.NFTMarketplace__NativeTokenAlreadySupported.selector);
        nftMarketplace.addPaymentToken(nativeToken);
    }

    function test_AddPaymentTokenRevertWhenAlreadySupported() public {
        vm.startPrank(nftMarketplace.owner());
        nftMarketplace.addPaymentToken(token1);

        vm.expectRevert(NFTMarketplace.NFTMarketplace__TokenAlreadySupported.selector);
        nftMarketplace.addPaymentToken(token1);
        vm.stopPrank();
    }

    function test_RemovePaymentToken() public {
        vm.startPrank(nftMarketplace.owner());
        nftMarketplace.addPaymentToken(token1);
        nftMarketplace.addPaymentToken(token2);

        address[] memory tokensBefore = nftMarketplace.getSupportedTokens();
        assertEq(tokensBefore.length, 3);

        nftMarketplace.removePaymentToken(token1);

        address[] memory tokensAfter = nftMarketplace.getSupportedTokens();
        assertEq(tokensAfter.length, 2);
        assertEq(tokensAfter[0], nativeToken);
        assertEq(tokensAfter[1], token2);
        vm.stopPrank();
    }

    function test_RemovePaymentTokenEmitsEvent() public {
        vm.startPrank(nftMarketplace.owner());
        nftMarketplace.addPaymentToken(token1);

        vm.expectEmit(true, true, true, true);
        emit NFTMarketplace.PaymentTokenRemoved(token1);
        nftMarketplace.removePaymentToken(token1);
        vm.stopPrank();
    }

    function test_RemovePaymentTokenRevertWhenNotOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        nftMarketplace.removePaymentToken(token1);
    }

    function test_RemovePaymentTokenRevertWhenNativeToken() public {
        vm.prank(nftMarketplace.owner());
        vm.expectRevert(NFTMarketplace.NFTMarketplace__NativeTokenCannotBeRemoved.selector);
        nftMarketplace.removePaymentToken(nativeToken);
    }

    function test_RemovePaymentTokenRevertWhenNotSupported() public {
        vm.prank(nftMarketplace.owner());
        vm.expectRevert(NFTMarketplace.NFTMarketplace__TokenAlreadySupported.selector);
        nftMarketplace.removePaymentToken(token1);
    }

    // ========================== PROTOCOL FEE MANAGEMENT TESTS =============================
    function test_UpdateProtocolFee() public {
        uint256 newFee = 300; // 3%

        vm.prank(nftMarketplace.owner());
        nftMarketplace.updateProtocolFee(newFee);

        assertEq(nftMarketplace.s_protocolFee(), newFee);
    }

    function test_UpdateProtocolFeeEmitsEvent() public {
        vm.prank(nftMarketplace.owner());
        vm.expectEmit(true, true, true, true);
        emit NFTMarketplace.ProtocolFeeUpdated(300);
        nftMarketplace.updateProtocolFee(300);
    }

    function test_UpdateProtocolFeeRevertWhenNotOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        nftMarketplace.updateProtocolFee(300);
    }

    function test_UpdateProtocolFeeRevertWhenFeeTooHigh() public {
        vm.prank(nftMarketplace.owner());
        vm.expectRevert(NFTMarketplace.NFTMarketplace__FeeTooHigh.selector);
        nftMarketplace.updateProtocolFee(1500); // 15% - too high
    }

    // ========================== TREASURY MANAGEMENT TESTS =============================
    function test_UpdateTreasury() public {
        address newTreasury = makeAddr("newTreasury");

        vm.prank(nftMarketplace.owner());
        nftMarketplace.updateTreasury(newTreasury);

        assertEq(nftMarketplace.s_treasury(), newTreasury);
    }

    function test_UpdateTreasuryEmitsEvent() public {
        address newTreasury = makeAddr("newTreasury");

        vm.prank(nftMarketplace.owner());
        vm.expectEmit(true, true, true, true);
        emit NFTMarketplace.TreasuryUpdated(newTreasury);
        nftMarketplace.updateTreasury(newTreasury);
    }

    function test_UpdateTreasuryRevertWhenNotOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        nftMarketplace.updateTreasury(makeAddr("newTreasury"));
    }

    function test_UpdateTreasuryRevertWhenZeroAddress() public {
        vm.prank(nftMarketplace.owner());
        vm.expectRevert(NFTMarketplace.NFTMarketplace__InvalidTreasury.selector);
        nftMarketplace.updateTreasury(address(0));
    }

    // ========================== List Item TESTS =============================

    function test_ItemListRevertsWhenPriceIsZero() public {
        vm.prank(user);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__PriceMustBeGreaterThanZero.selector);
        nftMarketplace.listItem(address(mockNFT), tokenId, nativeToken, 0, 0);
    }

    function test_ItemListRevertsForUnsupportedPaymentToken() public {
        address unsupportedToken = makeAddr("unsupportedToken");
        vm.prank(user);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__UnsupportedPaymentToken.selector);
        nftMarketplace.listItem(address(mockNFT), tokenId, unsupportedToken, 1 ether, 0);
    }

    function test_ItemListRevertsForInvalidExpiry() public {
        uint256 currentTime = 1000; // Arbitrary future timestamp
        vm.warp(currentTime);
        // Test case 1: expiry is in the past (definitely invalid)
        uint256 pastExpiry = currentTime - 100; // 900 (non-zero and in the past)

        // vm.prank(user);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__InvalidExpiry.selector);
        nftMarketplace.listItem(address(mockNFT), tokenId, nativeToken, 1 ether, pastExpiry);

        // Test case 2: expiry is exactly current time (also invalid)
        uint256 currentExpiry = block.timestamp;

        vm.prank(user);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__InvalidExpiry.selector);
        nftMarketplace.listItem(address(mockNFT), tokenId, nativeToken, 1 ether, currentExpiry);
    }

    function test_ListItemRevertsWhenNotNFTOwner() public {
        // User doesn't own the token they're trying to list
        MockERC721 anotherNFT = new MockERC721();
        anotherNFT.mint(makeAddr("otherUser"), tokenId); // Mint to different user

        vm.prank(user); // But user tries to list it
        vm.expectRevert(); // Should revert on transferFrom
        nftMarketplace.listItem(address(anotherNFT), tokenId, nativeToken, LISTING_PRICE, expiry);
    }

    function test_ListItemRevertsWhenNotApproved() public {
        // User owns but didn't approve marketplace
        MockERC721 anotherNFT = new MockERC721();
        anotherNFT.mint(user, tokenId);

        vm.prank(user);
        vm.expectRevert(); // Should revert on transferFrom
        nftMarketplace.listItem(address(anotherNFT), tokenId, nativeToken, LISTING_PRICE, expiry);
    }

    function test_ItemListSuccessfully() public {
        vm.prank(user);
        nftMarketplace.listItem(address(mockNFT), tokenId, nativeToken, LISTING_PRICE, expiry);

        // Verify the listing was created correctly
        (address seller, address paymentToken, uint256 price, uint256 _expiry, bool active) =
            nftMarketplace.s_listings(address(mockNFT), tokenId);
        assertEq(seller, user);
        assertEq(paymentToken, nativeToken);
        assertEq(price, LISTING_PRICE);
        assertEq(_expiry, expiry);
        assertTrue(active);

        // Verify NFT was transferred to marketplace
        assertEq(mockNFT.ownerOf(tokenId), address(nftMarketplace));
    }

    function test_ListItemEmitsEvent() public {
        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit NFTMarketplace.ItemListed(user, address(mockNFT), tokenId, nativeToken, LISTING_PRICE, expiry);
        nftMarketplace.listItem(address(mockNFT), tokenId, nativeToken, LISTING_PRICE, expiry);
    }

    function test_ListItemOverwritesExistingListing() public {
        // Create first listing
        vm.prank(user);
        nftMarketplace.listItem(address(mockNFT), tokenId, nativeToken, LISTING_PRICE, expiry);

        // Create second listing for same NFT - should overwrite without transferring
        uint256 newPrice = 2 ether;
        uint256 newExpiry = expiry + 1 days;

        vm.prank(user);
        nftMarketplace.listItem(address(mockNFT), tokenId, nativeToken, newPrice, newExpiry);

        // Verify the listing was updated
        (,, uint256 price, uint256 _expiry,) = nftMarketplace.s_listings(address(mockNFT), tokenId);
        assertEq(price, newPrice);
        assertEq(_expiry, newExpiry);

        // NFT should still be with marketplace
        assertEq(mockNFT.ownerOf(tokenId), address(nftMarketplace));
    }
}
