// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {Owned} from "solmate/auth/Owned.sol";
import {UnstoppableVault, ERC20, IERC3156FlashBorrower} from "./UnstoppableVault.sol";

contract UnstoppableMonitor is Owned, IERC3156FlashBorrower {
    UnstoppableVault private immutable vault;

    error UnexpectedFlashLoan();

    event FlashLoanStatus(bool success);

    constructor(address _vault) Owned(msg.sender) {
        vault = UnstoppableVault(_vault);
    }

    function onFlashLoan(address initiator, address token, uint256 amount, uint256 fee, bytes calldata)
        external returns (bytes32)
    {
        if (initiator != address(this) || msg.sender != address(vault) || token != address(vault.asset()) || fee != 0) {
            revert UnexpectedFlashLoan();
        }
        ERC20(token).approve(address(vault), amount);
        return keccak256("IERC3156FlashBorrower.onFlashLoan");
    }

    function checkFlashLoan(uint256 amount) external onlyOwner {
        require(amount > 0);
        try vault.flashLoan(this, address(vault.asset()), amount, bytes("")) {
            emit FlashLoanStatus(true);
        } catch {
            emit FlashLoanStatus(false);
            // Flash loan BROKEN → transfer ownership of vault (pause for investigation)
            vault.transferOwnership(owner);
        }
    }
}
