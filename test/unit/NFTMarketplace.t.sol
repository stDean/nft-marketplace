// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8;

import {Test, console} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {DeployNFTMarketplace, HelperConfig, NFTMarketplace} from "script/NFTMarketplace.s.sol";

contract NFTMarketplaceTest is Test {
    DeployNFTMarketplace deployer;
    HelperConfig helperConfig;
    NFTMarketplace nftMarketplace;
    HelperConfig.NetworkConfig config;

    address user = makeAddr("user");
    address token1 = makeAddr("token1");
    address token2 = makeAddr("token2");
    address nativeToken;

    function setUp() external {
        deployer = new DeployNFTMarketplace();
        (nftMarketplace, helperConfig) = deployer.run();
        config = helperConfig.getConfig();
        nativeToken = nftMarketplace.NATIVE_TOKEN();
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
}
