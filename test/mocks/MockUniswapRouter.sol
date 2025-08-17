// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockUniswapRouter {
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    mapping(address => mapping(address => address)) public pairs;

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        require(deadline >= block.timestamp, "MockRouter: EXPIRED");
        require(amountTokenDesired >= amountTokenMin, "MockRouter: INSUFFICIENT_TOKEN_AMOUNT");
        require(msg.value >= amountETHMin, "MockRouter: INSUFFICIENT_ETH_AMOUNT");

        // Transfer tokens from sender
        IERC20(token).transferFrom(msg.sender, address(this), amountTokenDesired);

        // Mock liquidity calculation
        amountToken = amountTokenDesired;
        amountETH = msg.value;
        liquidity = (amountToken * amountETH) / 1e18; // Simple calculation

        // Mock LP token transfer to recipient
        // In real implementation, this would mint LP tokens
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        pure
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;

        // Mock price calculation
        for (uint256 i; i < path.length - 1; i++) {
            amounts[i + 1] = amounts[i] * 1000; // Mock 1000:1 ratio
        }
    }

    function setPair(address tokenA, address tokenB, address pair) external {
        pairs[tokenA][tokenB] = pair;
        pairs[tokenB][tokenA] = pair;
    }
}
