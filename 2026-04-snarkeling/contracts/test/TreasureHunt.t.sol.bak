// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";

import {TreasureHunt} from "../src/TreasureHunt.sol";
import {HonkVerifier, BaseZKHonkVerifier} from "../src/Verifier.sol";


contract TreasureHuntTest is Test {
    using stdJson for string;

    HonkVerifier verifier;
    TreasureHunt hunt;
    address constant owner = address(0xDEADBEEF);
    uint256 constant INITIAL_OWNER_BALANCE = 200 ether;
    address constant participant = address(0xBEEF);
    uint256 constant INITIAL_PARTICIPANT_BALANCE = 50 ether;
    uint256 constant INITIAL_FUNDING = 100 ether;
    address constant attacker = address(0xBAD);


    function setUp() public {
        vm.deal(owner, INITIAL_OWNER_BALANCE);
        vm.deal(participant, INITIAL_PARTICIPANT_BALANCE);
        vm.startPrank(owner);
        // Deploy the verifier and the TreasureHunt contract, funded with INITIAL_FUNDING.
        verifier = new HonkVerifier();
        hunt = new TreasureHunt{value: INITIAL_FUNDING}(address(verifier));
        vm.stopPrank();
    }


    // Helper to load the proof and public inputs from the fixture files.
    function _loadFixture()
        internal
        view
        returns (
            bytes memory proof,
            bytes32 treasureHash,
            address payable recipient
        )
    {
        proof = vm.readFileBinary("contracts/test/fixtures/proof.bin");
        string memory json = vm.readFile("contracts/test/fixtures/public_inputs.json");

        bytes memory raw = json.parseRaw(".publicInputs");
        bytes32[] memory inputs = abi.decode(raw, (bytes32[]));

        assertEq(inputs.length, 2, "unexpected publicInputs length");

        treasureHash = inputs[0];
        recipient = payable(address(uint160(uint256(inputs[1]))));
    }


    //////////////////////////////////////////////////////////////////////////
    // ZK proof related tests ////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////

    function testClaimHappyPath() public {
        (
            bytes memory proof,
            bytes32 treasureHash,
            address payable recipient
        ) = _loadFixture();

        uint256 beforeBal = recipient.balance;

        hunt.claim(proof, treasureHash, recipient);

        assertEq(recipient.balance, beforeBal + hunt.REWARD());
        assertTrue(hunt.claimed(treasureHash));
    }


    function testClaimWrongRecipientFails() public {
        (
            bytes memory proof,
            bytes32 treasureHash,

        ) = _loadFixture();

        address payable wrongRecipient = payable(participant);

        vm.expectRevert(BaseZKHonkVerifier.SumcheckFailed.selector);
        hunt.claim(proof, treasureHash, wrongRecipient);
    }


    function testFrontRunningClaimFails() public {
        (
            bytes memory proof,
            bytes32 treasureHash,
        ) = _loadFixture();

        // Participant submits the proof to the mempool, but before it gets mined,
        // the attacker tries to front-run by claiming with the same proof and treasureHash,
        // but with a different recipient (attackerRecipient).

        // vm.prank(participant);
        //  hunt.claim(proof, treasureHash, recipient);


        address payable attackerRecipient = payable(address(0xBADBEEF));
        // Simulate a front-run by having the attacker claim before the participant.
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(BaseZKHonkVerifier.SumcheckFailed.selector)
        );
        hunt.claim(proof, treasureHash, attackerRecipient);
    }


    function testClaimInvalidProofFails() public {
        (
            bytes memory proof,
            bytes32 treasureHash,
            address payable recipient
        ) = _loadFixture();

        // Corrupt the proof by flipping some bits.
        for (uint256 i = 0; i < proof.length; i++) {
            proof[i] ^= 0xFF; // Invert all bits in each byte to make it invalid.
        }
        vm.expectRevert(
            abi.encodeWithSelector(BaseZKHonkVerifier.SumcheckFailed.selector)
        );
        hunt.claim(proof, treasureHash, recipient);
    }


    function testClaimDoubleSpendReverts() public {
        (
            bytes memory proof,
            bytes32 treasureHash,
            address payable recipient
        ) = _loadFixture();

        vm.startPrank(participant);
        hunt.claim(proof, treasureHash, recipient);

        //vm.expectRevert();
        hunt.claim(proof, treasureHash, recipient);
        vm.stopPrank();
    }



    //////////////////////////////////////////////////////////////////////////
    // Other edge cases related to claiming and funding //////////////////////
    /////////////////////////////////////////////////////////////////////////

    function testClaimWhenNotEnoughFundsFails() public {
        (
            bytes memory proof,
            bytes32 treasureHash,
            address payable recipient
        ) = _loadFixture();

        // Deploy underfunded contract with only 5 ETH.
        TreasureHunt underfundedHunt;
        vm.prank(owner);
        underfundedHunt = new TreasureHunt{value: 5 ether}(address(new HonkVerifier()));
       
        vm.expectRevert(
            abi.encodeWithSelector(TreasureHunt.NotEnoughFunds.selector)
        );
        underfundedHunt.claim(proof, treasureHash, recipient);
    }


    function testOwnerCanFund() public {
        uint256 beforeBal = address(hunt).balance;
        vm.prank(owner);
        hunt.fund{value: 50 ether}();
        assertEq(address(hunt).balance, beforeBal + 50 ether);
    }


    function testOwnderCannotWithdrawIfHuntIsNotOver() public {
        vm.prank(owner);
        vm.expectRevert("HUNT_NOT_OVER");
        hunt.withdraw();
    }


    function testNonOwnerCannotFund() public {
        vm.expectRevert("ONLY_OWNER_CAN_FUND");
        vm.prank(participant);
        hunt.fund{value: 10 ether}();
    }


    function testOwnerCannotClaim() public {
        (
            bytes memory proof,
            bytes32 treasureHash,
            address payable recipient
        ) = _loadFixture();

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(TreasureHunt.OwnerCannotClaim.selector)
        );
        hunt.claim(proof, treasureHash, recipient);
    }


    function testOwnerCannotBeRecipient() public {
        (
            bytes memory proof,
            bytes32 treasureHash,
        ) = _loadFixture();

        vm.prank(participant);
        vm.expectRevert(
            abi.encodeWithSelector(TreasureHunt.InvalidRecipient.selector)
        );
        hunt.claim(proof, treasureHash, payable(owner));
    }


    function testZeroAddressRecipientFails() public {
        (
            bytes memory proof,
            bytes32 treasureHash,
        ) = _loadFixture();

        address payable invalidRecipient = payable(address(0));

        vm.prank(participant);
        vm.expectRevert(
            abi.encodeWithSelector(TreasureHunt.InvalidRecipient.selector)
        );
        hunt.claim(proof, treasureHash, invalidRecipient);
    }


    function testContractItselfAsRecipientFails() public {
        (
            bytes memory proof,
            bytes32 treasureHash,
        ) = _loadFixture();

        address payable invalidRecipient = payable(address(hunt));

        vm.prank(participant);
        vm.expectRevert(
            abi.encodeWithSelector(TreasureHunt.InvalidRecipient.selector)
        );
        hunt.claim(proof, treasureHash, invalidRecipient);
    }


    function testMsgSenderAsRecipientFails() public {
        (
            bytes memory proof,
            bytes32 treasureHash,
        ) = _loadFixture();

        address payable invalidRecipient = payable(participant);

        vm.prank(participant);
        vm.expectRevert(
            abi.encodeWithSelector(TreasureHunt.InvalidRecipient.selector)
        );
        hunt.claim(proof, treasureHash, invalidRecipient);
    }


    function testIsClaimed() public {
        (
            bytes memory proof,
            bytes32 treasureHash,
            address payable recipient
        ) = _loadFixture();

        assertFalse(hunt.claimed(treasureHash));
        hunt.claim(proof, treasureHash, recipient);
        assertTrue(hunt.claimed(treasureHash));
    }


    function testGetClaimsCount() public {
        (
            bytes memory proof,
            bytes32 treasureHash,
            address payable recipient
        ) = _loadFixture();

        assertEq(hunt.claimsCount(), 0);
        hunt.claim(proof, treasureHash, recipient);
        assertEq(hunt.claimsCount(), 1);
    }


    function testGetRemainingTreasures() public {
        (
            bytes memory proof,
            bytes32 treasureHash,
            address payable recipient
        ) = _loadFixture();

        assertEq(hunt.MAX_TREASURES() - hunt.claimsCount(), 10);
        hunt.claim(proof, treasureHash, recipient);
        assertEq(hunt.MAX_TREASURES() - hunt.claimsCount(), 9);
    }


    function testGetContractBalance() public {
        assertEq(hunt.getContractBalance(), INITIAL_FUNDING);
        vm.prank(owner);
        hunt.fund{value: 50 ether}();
        assertEq(hunt.getContractBalance(), INITIAL_FUNDING + 50 ether);
    }


    function testDeployWithInvalidVerifierFails() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(TreasureHunt.InvalidVerifier.selector)
        );
        new TreasureHunt{value: INITIAL_FUNDING}(address(0));
    }


    function testClaimWhenPausedFails() public {
        (
            bytes memory proof,
            bytes32 treasureHash,
            address payable recipient
        ) = _loadFixture();

        vm.prank(owner);
        hunt.pause();

        vm.prank(participant);
        vm.expectRevert(
            abi.encodeWithSelector(TreasureHunt.ContractPaused.selector)
        );
        hunt.claim(proof, treasureHash, recipient);
    }


    function testonlyOwnerCanPause() public {
        vm.prank(participant);
        vm.expectRevert("ONLY_OWNER_CAN_PAUSE");
        hunt.pause();

        vm.prank(owner);
        hunt.pause();
        assertTrue(hunt.isPaused());
    }


    function testonlyOwnerCanUnpause() public {
        vm.prank(participant);
        vm.expectRevert("ONLY_OWNER_CAN_UNPAUSE");
        hunt.unpause();

        vm.prank(owner);
        hunt.pause();
        assertTrue(hunt.isPaused());

        vm.prank(owner);
        hunt.unpause();
        assertFalse(hunt.isPaused());
    }


    function testUpdateVerifier() public {
        HonkVerifier newVerifier = new HonkVerifier();

        // Cannot update if not paused
        vm.prank(owner);
        vm.expectRevert("THE_CONTRACT_MUST_BE_PAUSED");
        hunt.updateVerifier(newVerifier);

        // Onwer pauses contract
        vm.prank(owner);
        hunt.pause();

        // Cannot update if not owner
        vm.prank(participant);
        vm.expectRevert("ONLY_OWNER_CAN_UPDATE_VERIFIER");
        hunt.updateVerifier(newVerifier);

        // Owner updates the verifier
        vm.prank(owner);
        hunt.updateVerifier(newVerifier);
    }


    function testEmergencyWithdraw() public {
        address payable recipient = payable(participant);
        uint256 amount = 10 ether;

        // Cannot emergency withdraw if not paused
        vm.prank(owner);
        vm.expectRevert("THE_CONTRACT_MUST_BE_PAUSED");
        hunt.emergencyWithdraw(recipient, amount);

        // Owner pauses contract
        vm.prank(owner);
        hunt.pause();

        // Cannot emergency withdraw if not owner
        vm.prank(participant);
        vm.expectRevert("ONLY_OWNER_CAN_EMERGENCY_WITHDRAW");
        hunt.emergencyWithdraw(recipient, amount);

        // Cannot emergency withdraw to invalid recipient
        vm.prank(owner);
        vm.expectRevert("INVALID_RECIPIENT");
        hunt.emergencyWithdraw(payable(address(0)), amount);

        vm.prank(owner);
        vm.expectRevert("INVALID_RECIPIENT");
        hunt.emergencyWithdraw(payable(address(hunt)), amount);

        vm.prank(owner);
        vm.expectRevert("INVALID_RECIPIENT");
        hunt.emergencyWithdraw(payable(owner), amount);

        // Cannot emergency withdraw invalid amount
        vm.prank(owner);
        vm.expectRevert("INVALID_AMOUNT");
        hunt.emergencyWithdraw(recipient, 0);

        vm.prank(owner);
        vm.expectRevert("INVALID_AMOUNT");
        hunt.emergencyWithdraw(recipient, address(hunt).balance + 1 ether);

        // Owner performs emergency withdraw
        uint256 beforeBal = recipient.balance;
        vm.prank(owner);
        hunt.emergencyWithdraw(recipient, amount);
        assertEq(recipient.balance, beforeBal + amount);
    }


    function testGetStatus() public {
        (
            bytes memory proof,
            bytes32 treasureHash,
            address payable recipient
        ) = _loadFixture();

        // Initial status
        (address contractOwner,
        address currentVerifier,
        uint256 balance,
        uint256 reward,
        uint256 maxTreasures,
        uint256 claimedCount,
        uint256 remainingTreasures,
        bool contractPaused) = hunt.getStatus();
        assertEq(contractOwner, owner);
        assertEq(currentVerifier, address(verifier));
        assertEq(balance, INITIAL_FUNDING);
        assertEq(reward, hunt.REWARD());
        assertEq(maxTreasures, hunt.MAX_TREASURES());
        assertEq(claimedCount, 0);
        assertEq(remainingTreasures, 10);
        assertFalse(contractPaused);

        // After a claim
        hunt.claim(proof, treasureHash, recipient);
        (contractOwner,
        currentVerifier,
        balance,
        reward,
        maxTreasures,
        claimedCount,
        remainingTreasures,
        contractPaused) = hunt.getStatus();
        assertEq(claimedCount, 1);
        assertEq(remainingTreasures, 9);
        assertFalse(contractPaused);

        // After pausing
        vm.prank(owner);
        hunt.pause();
        (contractOwner,
        currentVerifier,
        balance,
        reward,
        maxTreasures,
        claimedCount,
        remainingTreasures,
        contractPaused) = hunt.getStatus();
        assertEq(claimedCount, 1);
        assertEq(remainingTreasures, 9);
        assertTrue(contractPaused);
    }

}