// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Replika sederhana DVD "Puppet" — lending pool pakai Uniswap V1 spot price sebagai oracle.
// Pattern yang bikin Mango Markets ($117M), Harvest Finance ($34M), bZx ($8M).

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

contract TokenDVT is IERC20 {
    string public name = "DVT";
    string public symbol = "DVT";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(uint256 _supply) {
        totalSupply = _supply;
        balanceOf[msg.sender] = _supply;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

// Uniswap V1 style: pool berisi ETH dan Token dengan constant product x*y=k
contract UniswapV1Exchange {
    IERC20 public token;
    uint256 public tokenReserve;
    uint256 public ethReserve;

    constructor(address _token) {
        token = IERC20(_token);
    }

    function seedLiquidity(uint256 tokenAmount) external payable {
        require(tokenReserve == 0 && ethReserve == 0, "already seeded");
        token.transferFrom(msg.sender, address(this), tokenAmount);
        tokenReserve = tokenAmount;
        ethReserve = msg.value;
    }

    // Swap ETH → Token pakai constant product
    function ethToTokenSwap() external payable returns (uint256 tokenOut) {
        uint256 ethIn = msg.value;
        tokenOut = (tokenReserve * ethIn) / (ethReserve + ethIn);
        ethReserve += ethIn;
        tokenReserve -= tokenOut;
        token.transfer(msg.sender, tokenOut);
    }

    // Swap Token → ETH pakai constant product
    function tokenToEthSwap(uint256 tokenIn) external returns (uint256 ethOut) {
        token.transferFrom(msg.sender, address(this), tokenIn);
        ethOut = (ethReserve * tokenIn) / (tokenReserve + tokenIn);
        tokenReserve += tokenIn;
        ethReserve -= ethOut;
        (bool ok,) = msg.sender.call{value: ethOut}("");
        require(ok, "eth transfer failed");
    }

    // Oracle view — harga 1 token dalam ETH berdasarkan spot ratio
    // BUG: ini spot price, mudah dimanipulasi dengan 1 trade besar
    function getTokenPriceInEth(uint256 tokenAmount) public view returns (uint256) {
        return (tokenAmount * ethReserve) / tokenReserve;
    }
}

// Lending pool: pinjem token, butuh 2x nilainya dalam ETH sebagai jaminan
contract PuppetPool {
    IERC20 public token;
    UniswapV1Exchange public oracle;

    constructor(address _token, address _oracle) {
        token = IERC20(_token);
        oracle = UniswapV1Exchange(_oracle);
    }

    // Butuh collateral = 2x nilai token dalam ETH
    function calculateDepositRequired(uint256 amount) public view returns (uint256) {
        return 2 * oracle.getTokenPriceInEth(amount);
    }

    function borrow(uint256 amount) external payable {
        uint256 depositRequired = calculateDepositRequired(amount);
        require(msg.value >= depositRequired, "need more collateral");
        token.transfer(msg.sender, amount);
    }
}
