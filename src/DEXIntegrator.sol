// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ICampaignInterfaces.sol";

interface IUniswapV2Router02 {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    function WETH() external pure returns (address);
}

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

contract DEXIntegrator is IDEXIntegrator {
    using SafeERC20 for IERC20;

    IUniswapV2Router02 public immutable uniswapRouter;
    IUniswapV2Factory public immutable uniswapFactory;

    event LiquidityAdded(
        address indexed tokenA,
        address indexed tokenB,
        uint256 tokenAmount,
        uint256 usdcAmount,
        uint256 liquidity,
        address indexed pair
    );

    constructor(address _uniswapRouter, address _uniswapFactory) {
        require(_uniswapRouter != address(0), "DEXIntegrator: Invalid router address");
        require(_uniswapFactory != address(0), "DEXIntegrator: Invalid factory address");

        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
        uniswapFactory = IUniswapV2Factory(_uniswapFactory);
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
        IERC20(tokenA).approve(address(uniswapRouter), tokenAmount);
        IERC20(tokenB).approve(address(uniswapRouter), usdcAmount);

        uint256 deadline = block.timestamp + 300;

        (amountToken, amountUSDC, liquidity) = uniswapRouter.addLiquidity(
            tokenA,
            tokenB,
            tokenAmount,
            usdcAmount,
            tokenAmount * 95 / 100, // 5% slippage tolerance
            usdcAmount * 95 / 100, // 5% slippage tolerance
            msg.sender,
            deadline
        );

        if (tokenAmount > amountToken) {
            IERC20(tokenA).safeTransfer(msg.sender, tokenAmount - amountToken);
        }

        if (usdcAmount > amountUSDC) {
            IERC20(tokenB).safeTransfer(msg.sender, usdcAmount - amountUSDC);
        }

        address pair = uniswapFactory.getPair(tokenA, tokenB);

        emit LiquidityAdded(tokenA, tokenB, amountToken, amountUSDC, liquidity, pair);
    }

    function getOptimalLiquidityAmounts(address tokenA, address tokenB, uint256 tokenDesired, uint256 usdcDesired)
        external
        view
        returns (uint256 tokenAmount, uint256 usdcAmount)
    {
        address pair = uniswapFactory.getPair(tokenA, tokenB);

        if (pair == address(0)) {
            return (tokenDesired, usdcDesired);
        }

        IUniswapV2Pair pairContract = IUniswapV2Pair(pair);
        (uint112 reserve0, uint112 reserve1,) = pairContract.getReserves();

        address token0 = pairContract.token0();
        (uint256 tokenReserve, uint256 usdcReserve) =
            tokenA == token0 ? (uint256(reserve0), uint256(reserve1)) : (uint256(reserve1), uint256(reserve0));

        if (tokenReserve == 0 && usdcReserve == 0) {
            return (tokenDesired, usdcDesired);
        }

        uint256 usdcAmountOptimal = (tokenDesired * usdcReserve) / tokenReserve;
        if (usdcAmountOptimal <= usdcDesired) {
            return (tokenDesired, usdcAmountOptimal);
        } else {
            uint256 tokenAmountOptimal = (usdcDesired * tokenReserve) / usdcReserve;
            return (tokenAmountOptimal, usdcDesired);
        }
    }
}
