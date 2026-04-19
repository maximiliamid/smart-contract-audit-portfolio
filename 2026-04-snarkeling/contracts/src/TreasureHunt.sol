// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IVerifier} from "./Verifier.sol";

contract TreasureHunt {
    // ----- errors -----
    error AlreadyClaimed(bytes32 treasureHash);
    error InvalidProof();
    error NotEnoughFunds();
    error InvalidRecipient();
    error AllTreasuresClaimed();
    error OwnerCannotClaim();
    error OwnerCannotBeRecipient();
    error InvalidVerifier();
    error HuntNotOver();
    error NoFundsToWithdraw();
    error OnlyOwnerCanFund();
    error OnlyOwnerCanPause();
    error OnlyOwnerCanUnpause();
    error ContractPaused();
    error TheContractMustBePaused();
    error OnlyOwnerCanUpdateVerifier();
    error OnlyOwnerCanEmergencyWithdraw();
    error InvalidAmount();

    // ----- constants -----
    uint256 public constant REWARD = 10 ether;
    uint256 public constant MAX_TREASURES = 10;
    

    // ----- immutable config -----
    IVerifier private verifier;
    address private immutable owner;
    bytes32 private immutable _treasureHash;

    // ----- state -----
    mapping(bytes32 => bool) public claimed;
    uint256 public claimsCount;
    bool private paused;
    bool private locked; 

    // ----- events -----
    event Claimed(bytes32 indexed treasureHash, address indexed recipient);
    event Funded(uint256 amount, uint256 newBalance);
    event Withdrawn(uint256 amount, uint256 newBalance);
    event VerifierUpdated(address indexed newVerifier);
    event EmergencyWithdraw(address indexed recipient, uint256 amount);
    event Paused(address indexed by);
    event Unpaused(address indexed by);

    // ----- modifiers -----
    modifier onlyOwner() {
        require(msg.sender == owner, "ONLY_OWNER");
        _;
    }


    modifier nonReentrant() {
        require(!locked, "REENTRANCY_GUARD");
        locked = true;
        _;
        locked = false;
    }


    constructor(address _verifier) payable {
        if (_verifier == address(0)) revert InvalidVerifier();
   
        owner = msg.sender;  
        verifier = IVerifier(_verifier);
        paused = false;

        // Owner should fund 100 ETH at deployment (10 treasures × 10 ETH).
    }



    /// @notice Claim a treasure reward using a ZK proof.
    /// @param proof Barretenberg/Noir proof bytes (as emitted by bb prove).
    /// @param treasureHash Treasure identifier (public input). Reveals which treasure was found.
    /// @param recipient Recipient for the payout (public input).
    function claim(bytes calldata proof, bytes32 treasureHash, address payable recipient) external nonReentrant() {
        if (paused) revert ContractPaused();
        if (address(this).balance < REWARD) revert NotEnoughFunds();
        if (recipient == address(0) || recipient == address(this) || recipient == owner || recipient == msg.sender) revert InvalidRecipient();
        if (claimsCount >= MAX_TREASURES) revert AllTreasuresClaimed();
        if (claimed[_treasureHash]) revert AlreadyClaimed(treasureHash);
        if (msg.sender == owner) revert OwnerCannotClaim();


        // Public inputs must match Noir circuit order:
        // treasure_hash, recipient (recipient encoded into 160-bit integer in a Field).
        bytes32[] memory publicInputs = new bytes32[](2);
        publicInputs[0] = treasureHash;
        publicInputs[1] = bytes32(uint256(uint160(address(recipient))));

        // Verify proof against the public inputs. 
        // If valid, transfer the reward and mark the treasure as claimed.
        bool ok = verifier.verify(proof, publicInputs);
        if (!ok) revert InvalidProof();

        _incrementClaimsCount();
        _markClaimed(treasureHash);


        (bool sent, ) = recipient.call{value: REWARD}("");
        require(sent, "ETH_TRANSFER_FAILED");

      
        emit Claimed(treasureHash, msg.sender);
    }



    // ----- view functions -----

    /// @notice Check if a treasure has already been claimed.
    /// @param treasureHash Treasure identifier.
    /// @return True if the treasure has been claimed, false otherwise.
    function isClaimed(bytes32 treasureHash) external view returns (bool) {
        return claimed[treasureHash];           
    }


    /// @notice Get the number of treasures claimed so far.
    /// @return The count of claimed treasures.
    function getClaimsCount() external view returns (uint256) {
        return claimsCount; 
    }


    /// @notice Get the number of treasures remaining to be claimed.
    /// @return The count of remaining treasures.
    function getRemainingTreasures() external view returns (uint256) {
        return MAX_TREASURES - claimsCount;
    }


    /// @notice Get contract balance (total unclaimed funds).
    /// @return The current balance of the contract in wei.
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }


    /// @notice Check if contract is paused.
    /// @return True if the contract is paused, false otherwise.
    function isPaused() external view returns (bool) {
        return paused;
    }


    /// @notice Get the address of the current verifier.
    /// @return The address of the verifier contract.
    function getVerifier() external view returns (address) {
        return address(verifier);
    }


    /// @notice Get the owner of the contract.
    /// @return The address of the owner.
    function getOwner() external view returns (address) {
        return owner;
    }


    /// @notice Get the full status of the treasure hunt.
    /// @return contractOwner The address of the contract owner.
    /// @return currentVerifier The address of the current verifier contract.
    /// @return balance The current balance of the contract in wei.
    /// @return reward The reward amount for each treasure in wei.
    /// @return maxTreasures The maximum number of treasures to be claimed.
    /// @return claimedCount The number of treasures claimed so far.
    /// @return remainingTreasures The number of treasures remaining to be claimed.
    /// @return contractPaused Whether the contract is currently paused.
    function getStatus()
    external
    view
    returns (
        address contractOwner,
        address currentVerifier,
        uint256 balance,
        uint256 reward,
        uint256 maxTreasures,
        uint256 claimedCount,
        uint256 remainingTreasures,
        bool contractPaused
    )
    {
        return (
            owner,
            address(verifier),
            address(this).balance,
            REWARD,
            MAX_TREASURES,
            claimsCount,
            MAX_TREASURES - claimsCount,
            paused
        );
    }



    // ----- internal functions -----

    /// @notice Mark a treasure as claimed.
    /// @param treasureHash Treasure identifier.
    function _markClaimed(bytes32 treasureHash) internal {
        claimed[treasureHash] = true;
    }

    /// @notice Increment the count of claimed treasures.
    function _incrementClaimsCount() internal {
        claimsCount += 1;
    }



    // ----- admin functions -----

    /// @notice Allow the owner to withdraw unclaimed funds after the hunt is over.
    function withdraw() external {
        require(claimsCount >= MAX_TREASURES, "HUNT_NOT_OVER");     

        uint256 balance = address(this).balance;
        require(balance > 0, "NO_FUNDS_TO_WITHDRAW");
        (bool sent, ) = owner.call{value: balance}("");
        require(sent, "ETH_TRANSFER_FAILED");

        emit Withdrawn(balance, address(this).balance);
    }   


    /// @notice Allow the owner to add more funds if needed.
    function fund() external payable {
        require(msg.sender==owner, "ONLY_OWNER_CAN_FUND");
        require(msg.value > 0, "NO_ETH_SENT");

        emit Funded(msg.value, address(this).balance);
    }


    /// @notice Pause the contract.
    function pause() external {
        require(msg.sender == owner, "ONLY_OWNER_CAN_PAUSE");
        paused = true;

        emit Paused(msg.sender);
    }


    /// @notice Unpause the contract.
    function unpause() external {
        require(msg.sender == owner, "ONLY_OWNER_CAN_UNPAUSE");
        paused = false; 

        emit Unpaused(msg.sender);
    }


    /// @notice In case of a bug, allow the owner to update the verifier address.
    function updateVerifier(IVerifier newVerifier) external {
        require(paused, "THE_CONTRACT_MUST_BE_PAUSED");
        require(msg.sender == owner, "ONLY_OWNER_CAN_UPDATE_VERIFIER");
        verifier = newVerifier;

        emit VerifierUpdated(address(newVerifier));
    }


    /// @notice In case of an emergency, allow the owner to send ETH to a specified address.
    function emergencyWithdraw(address payable recipient, uint256 amount) external {
        require(paused, "THE_CONTRACT_MUST_BE_PAUSED");
        require(msg.sender == owner, "ONLY_OWNER_CAN_EMERGENCY_WITHDRAW");
        require(recipient != address(0) && recipient != address(this) && recipient != owner, "INVALID_RECIPIENT");
        require(amount > 0 && amount <= address(this).balance, "INVALID_AMOUNT"); 

        (bool sent, ) = recipient.call{value: amount}("");
        require(sent, "ETH_TRANSFER_FAILED");

        emit EmergencyWithdraw(recipient, amount);
    }


    /// @notice Fallback function to accept ETH sent directly to the contract.
    receive() external payable {
        emit Funded(msg.value, address(this).balance);  
    }

}