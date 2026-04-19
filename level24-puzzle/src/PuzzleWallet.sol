// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Implementation di EIP-1967 slot supaya tidak tabrakan dengan slot 0/1.
// Tapi admin & pendingAdmin tetap di slot 0 dan 1 sengaja — inilah source bug-nya.
contract UpgradeableProxy {
    bytes32 internal constant IMPL_SLOT = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

    constructor(address impl, bytes memory _data) {
        _setImpl(impl);
        if (_data.length > 0) {
            (bool ok,) = impl.delegatecall(_data);
            require(ok, "init failed");
        }
    }

    function implementation() public view returns (address i) {
        bytes32 slot = IMPL_SLOT;
        assembly { i := sload(slot) }
    }

    function _setImpl(address i) internal {
        bytes32 slot = IMPL_SLOT;
        assembly { sstore(slot, i) }
    }

    function _fallback() internal {
        address impl = implementation();
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    fallback() external payable { _fallback(); }
    receive() external payable { _fallback(); }
}

contract PuzzleProxy is UpgradeableProxy {
    address public pendingAdmin; // slot 0 — tabrakan dengan owner di impl
    address public admin;        // slot 1 — tabrakan dengan maxBalance di impl

    constructor(address _admin, address impl, bytes memory data) UpgradeableProxy(impl, data) {
        // UpgradeableProxy constructor (yang jalan init) selesai DULU saat slot 1 masih 0.
        // Setelah init selesai, slot 1 berisi maxBalance (dari init).
        // Line berikut MENIMPA slot 1 dengan admin — persis pola Ethernaut.
        admin = _admin;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "not admin");
        _;
    }

    function proposeNewAdmin(address _newAdmin) external {
        pendingAdmin = _newAdmin;
    }

    function approveNewAdmin(address _expectedAdmin) external onlyAdmin {
        require(pendingAdmin == _expectedAdmin, "unexpected admin");
        admin = pendingAdmin;
    }
}

contract PuzzleWallet {
    address public owner;                       // slot 0
    uint256 public maxBalance;                  // slot 1
    mapping(address => bool) public whitelisted;
    mapping(address => uint256) public balances;

    function init(uint256 _maxBalance) public {
        require(maxBalance == 0, "already init");
        require(owner == msg.sender || owner == address(0), "not owner");
        maxBalance = _maxBalance;
        owner = msg.sender;
    }

    modifier onlyWhitelisted() {
        require(whitelisted[msg.sender], "not whitelisted");
        _;
    }

    function setMaxBalance(uint256 _maxBalance) external onlyWhitelisted {
        require(address(this).balance == 0, "balance must be 0");
        maxBalance = _maxBalance;
    }

    function addToWhitelist(address addr) external {
        require(msg.sender == owner, "not owner");
        whitelisted[addr] = true;
    }

    function deposit() external payable onlyWhitelisted {
        require(address(this).balance <= maxBalance, "over max");
        balances[msg.sender] += msg.value;
    }

    function execute(address to, uint256 value, bytes calldata data) external payable onlyWhitelisted {
        require(balances[msg.sender] >= value, "not enough balance");
        balances[msg.sender] -= value;
        (bool ok,) = to.call{value: value}(data);
        require(ok, "exec failed");
    }

    function multicall(bytes[] calldata data) external payable onlyWhitelisted {
        bool depositCalled = false;
        for (uint256 i = 0; i < data.length; i++) {
            bytes memory _data = data[i];
            bytes4 selector;
            assembly { selector := mload(add(_data, 32)) }
            if (selector == this.deposit.selector) {
                require(!depositCalled, "deposit sekali saja");
                depositCalled = true;
            }
            (bool ok,) = address(this).delegatecall(data[i]);
            require(ok, "multicall item failed");
        }
    }
}
