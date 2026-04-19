// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {SafeTransferLib, ERC4626, ERC20} from "solmate/tokens/ERC4626.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

interface IERC3156FlashBorrower {
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external returns (bytes32);
}

interface IERC3156FlashLender {
    function flashFee(address token, uint256 amount) external view returns (uint256);
    function maxFlashLoan(address token) external view returns (uint256);
    function flashLoan(IERC3156FlashBorrower receiver, address token, uint256 amount, bytes calldata data)
        external returns (bool);
}

/**
 * Vulnerable ERC4626 vault replikasi Damn Vulnerable DeFi v4.1 - Unstoppable.
 * Flash loan gratis sampai grace period habis.
 *
 * BUG: Invariant check di flashLoan() membandingkan `convertToShares(totalSupply)`
 * dengan balance asset sebelum transfer. Invariant bisa di-break dengan mentransfer
 * asset langsung ke vault (bypass deposit) → share:asset ratio skewed → permanent DoS.
 */
contract UnstoppableVault is IERC3156FlashLender, ReentrancyGuard, Owned, ERC4626 {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    uint256 public constant FEE_FACTOR = 0.05 ether;
    uint64 public immutable end = uint64(block.timestamp) + 14 days;

    address public feeRecipient;

    error InvalidAmount(uint256 amount);
    error InvalidBalance();
    error CallbackFailed();
    error UnsupportedCurrency();

    event FeeUpdated(uint256 newFee);

    bytes32 private constant CALLBACK_SUCCESS = keccak256("IERC3156FlashBorrower.onFlashLoan");

    constructor(ERC20 _token, address _owner, address _feeRecipient)
        ERC4626(_token, "Oh Damn Valuable Token", "oDVT")
        Owned(_owner)
    {
        feeRecipient = _feeRecipient;
    }

    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function maxFlashLoan(address _token) public view returns (uint256) {
        if (address(asset) != _token) return 0;
        return totalAssets();
    }

    function flashFee(address _token, uint256 _amount) public view returns (uint256 fee) {
        if (address(asset) != _token) revert UnsupportedCurrency();
        if (block.timestamp < end && _amount < maxFlashLoan(_token)) {
            return 0;
        } else {
            return _amount.mulWadUp(FEE_FACTOR);
        }
    }

    function flashLoan(IERC3156FlashBorrower receiver, address _token, uint256 amount, bytes calldata data)
        external nonReentrant returns (bool)
    {
        if (amount == 0) revert InvalidAmount(0);
        if (address(asset) != _token) revert UnsupportedCurrency();
        uint256 balanceBefore = totalAssets();

        // ←←←  INVARIANT CHECK (titik bug)
        if (convertToShares(totalSupply) != balanceBefore) revert InvalidBalance();

        ERC20(_token).safeTransfer(address(receiver), amount);
        uint256 fee = flashFee(_token, amount);

        if (receiver.onFlashLoan(msg.sender, _token, amount, fee, data) != CALLBACK_SUCCESS) {
            revert CallbackFailed();
        }

        ERC20(_token).safeTransferFrom(address(receiver), address(this), amount + fee);
        return true;
    }

    function execute(address target, bytes memory actionData) external onlyOwner returns (bytes memory) {
        (bool success, bytes memory returnData) = target.call(actionData);
        if (!success) {
            assembly { revert(add(returnData, 32), mload(returnData)) }
        }
        return returnData;
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        if (_feeRecipient != address(this)) {
            feeRecipient = _feeRecipient;
        }
    }
}
