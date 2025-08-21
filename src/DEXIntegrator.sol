// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ICampaignInterfaces.sol";

interface INonfungiblePositionManager {
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
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    function WETH9() external pure returns (address);
}

interface IUniswapV3Factory {
    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool);
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

interface IUniswapV3Pool {
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );
    function token0() external view returns (address);
    function token1() external view returns (address);
    function fee() external view returns (uint24);
}

contract DEXIntegrator is IDEXIntegrator {
    using SafeERC20 for IERC20;

    INonfungiblePositionManager public immutable positionManager;
    IUniswapV3Factory public immutable uniswapFactory;
    uint24 public constant DEFAULT_FEE = 3000; // 0.3%

    event LiquidityAdded(
        address indexed tokenA,
        address indexed tokenB,
        uint256 tokenAmount,
        uint256 usdcAmount,
        uint256 liquidity,
        address indexed pair
    );

    constructor(address _positionManager, address _uniswapFactory) {
        require(_positionManager != address(0), "DEXIntegrator: Invalid position manager address");
        require(_uniswapFactory != address(0), "DEXIntegrator: Invalid factory address");

        positionManager = INonfungiblePositionManager(_positionManager);
        uniswapFactory = IUniswapV3Factory(_uniswapFactory);
    }

    function addLiquidity(address tokenA, uint256 tokenAmount, address tokenB, uint256 usdcAmount)
        external
        returns (uint256 amountToken, uint256 amountUSDC, uint256 liquidity)
    {
        require(tokenA != address(0), "DEXIntegrator: Invalid tokenA address");
        require(tokenB != address(0), "DEXIntegrator: Invalid tokenB address");
        require(tokenAmount > 0, "DEXIntegrator: Token amount must be greater than zero");
        require(usdcAmount > 0, "DEXIntegrator: USDC amount must be greater than zero");

        IERC20(tokenA).safeTransferFrom(msg.sender, address(this), tokenAmount);
        IERC20(tokenB).safeTransferFrom(msg.sender, address(this), usdcAmount);
        IERC20(tokenA).approve(address(positionManager), tokenAmount);
        IERC20(tokenB).approve(address(positionManager), usdcAmount);

        // Ensure token0 < token1 for Uniswap V3
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        (uint256 amount0Desired, uint256 amount1Desired) = tokenA < tokenB ? (tokenAmount, usdcAmount) : (usdcAmount, tokenAmount);

        // Create pool if it doesn't exist
        address pool = uniswapFactory.getPool(token0, token1, DEFAULT_FEE);
        if (pool == address(0)) {
            pool = uniswapFactory.createPool(token0, token1, DEFAULT_FEE);
        }

        // Use full range liquidity for simplicity (-887220 to 887220)
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: DEFAULT_FEE,
            tickLower: -887220, // Min tick
            tickUpper: 887220,  // Max tick
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            amount0Min: amount0Desired * 95 / 100, // 5% slippage tolerance
            amount1Min: amount1Desired * 95 / 100, // 5% slippage tolerance
            recipient: msg.sender,
            deadline: block.timestamp + 300
        });

        (, uint128 liquidityAmount, uint256 amount0, uint256 amount1) = positionManager.mint(params);
        
        // Map amounts back to original token order
        (amountToken, amountUSDC) = tokenA < tokenB ? (amount0, amount1) : (amount1, amount0);
        liquidity = uint256(liquidityAmount);

        // Refund unused tokens
        if (tokenAmount > amountToken) {
            IERC20(tokenA).safeTransfer(msg.sender, tokenAmount - amountToken);
        }
        if (usdcAmount > amountUSDC) {
            IERC20(tokenB).safeTransfer(msg.sender, usdcAmount - amountUSDC);
        }

        emit LiquidityAdded(tokenA, tokenB, amountToken, amountUSDC, liquidity, pool);
    }

    function getOptimalLiquidityAmounts(address tokenA, address tokenB, uint256 tokenDesired, uint256 usdcDesired)
        external
        view
        returns (uint256 tokenAmount, uint256 usdcAmount)
    {
        address pool = uniswapFactory.getPool(tokenA, tokenB, DEFAULT_FEE);

        // If pool doesn't exist, return desired amounts
        if (pool == address(0)) {
            return (tokenDesired, usdcDesired);
        }

        // For V3 with full range liquidity, we can use the desired amounts
        // In practice, you might want to calculate based on current price
        return (tokenDesired, usdcDesired);
    }
}
