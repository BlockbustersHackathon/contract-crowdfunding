// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockUniswapRouter {
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    mapping(address => mapping(address => address)) public pairs;

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address, /* to */
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        require(deadline >= block.timestamp, "MockRouter: EXPIRED");
        require(amountADesired >= amountAMin, "MockRouter: INSUFFICIENT_A_AMOUNT");
        require(amountBDesired >= amountBMin, "MockRouter: INSUFFICIENT_B_AMOUNT");

        // Transfer tokens from sender
        IERC20(tokenA).transferFrom(msg.sender, address(this), amountADesired);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountBDesired);

        // Mock liquidity calculation
        amountA = amountADesired;
        amountB = amountBDesired;
        liquidity = (amountA * amountB) / 1e18; // Simple calculation

        // Mock LP token transfer to recipient
        // In real implementation, this would mint LP tokens to the `to` address
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
