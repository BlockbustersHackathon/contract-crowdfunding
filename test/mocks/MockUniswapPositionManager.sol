// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockUniswapPositionManager {
    address public constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    
    uint256 private nextTokenId = 1;

    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        require(params.deadline >= block.timestamp, "MockPositionManager: EXPIRED");
        require(params.amount0Desired >= params.amount0Min, "MockPositionManager: INSUFFICIENT_AMOUNT_0");
        require(params.amount1Desired >= params.amount1Min, "MockPositionManager: INSUFFICIENT_AMOUNT_1");

        // Transfer tokens from sender
        IERC20(params.token0).transferFrom(msg.sender, address(this), params.amount0Desired);
        IERC20(params.token1).transferFrom(msg.sender, address(this), params.amount1Desired);

        // Mock return values
        tokenId = nextTokenId++;
        amount0 = params.amount0Desired;
        amount1 = params.amount1Desired;
        liquidity = uint128((amount0 * amount1) / 1e18); // Simple calculation
    }
}