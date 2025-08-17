// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ICampaignInterfaces.sol";

interface IUniswapV2Router02 {
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);

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
        address indexed token, uint256 tokenAmount, uint256 ethAmount, uint256 liquidity, address indexed pair
    );

    constructor(address _uniswapRouter, address _uniswapFactory) {
        require(_uniswapRouter != address(0), "DEXIntegrator: Invalid router address");
        require(_uniswapFactory != address(0), "DEXIntegrator: Invalid factory address");

        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
        uniswapFactory = IUniswapV2Factory(_uniswapFactory);
    }

    function addLiquidity(address token, uint256 tokenAmount, uint256 ethAmount)
        external
        payable
        returns (uint256 amountToken, uint256 amountETH, uint256 liquidity)
    {
        require(token != address(0), "DEXIntegrator: Invalid token address");
        require(tokenAmount > 0, "DEXIntegrator: Token amount must be greater than zero");
        require(ethAmount > 0, "DEXIntegrator: ETH amount must be greater than zero");
        require(msg.value >= ethAmount, "DEXIntegrator: Insufficient ETH sent");

        IERC20(token).safeTransferFrom(msg.sender, address(this), tokenAmount);
        IERC20(token).approve(address(uniswapRouter), tokenAmount);

        uint256 deadline = block.timestamp + 300;

        (amountToken, amountETH, liquidity) = uniswapRouter.addLiquidityETH{value: ethAmount}(
            token,
            tokenAmount,
            tokenAmount * 95 / 100, // 5% slippage tolerance
            ethAmount * 95 / 100, // 5% slippage tolerance
            msg.sender,
            deadline
        );

        if (msg.value > amountETH) {
            payable(msg.sender).transfer(msg.value - amountETH);
        }

        if (tokenAmount > amountToken) {
            IERC20(token).safeTransfer(msg.sender, tokenAmount - amountToken);
        }

        address pair = uniswapFactory.getPair(token, uniswapRouter.WETH());

        emit LiquidityAdded(token, amountToken, amountETH, liquidity, pair);
    }

    function getOptimalLiquidityAmounts(address token, uint256 tokenDesired, uint256 ethDesired)
        external
        view
        returns (uint256 tokenAmount, uint256 ethAmount)
    {
        address pair = uniswapFactory.getPair(token, uniswapRouter.WETH());

        if (pair == address(0)) {
            return (tokenDesired, ethDesired);
        }

        IUniswapV2Pair pairContract = IUniswapV2Pair(pair);
        (uint112 reserve0, uint112 reserve1,) = pairContract.getReserves();

        address token0 = pairContract.token0();
        (uint256 tokenReserve, uint256 ethReserve) =
            token == token0 ? (uint256(reserve0), uint256(reserve1)) : (uint256(reserve1), uint256(reserve0));

        if (tokenReserve == 0 && ethReserve == 0) {
            return (tokenDesired, ethDesired);
        }

        uint256 ethAmountOptimal = (tokenDesired * ethReserve) / tokenReserve;
        if (ethAmountOptimal <= ethDesired) {
            return (tokenDesired, ethAmountOptimal);
        } else {
            uint256 tokenAmountOptimal = (ethDesired * tokenReserve) / ethReserve;
            return (tokenAmountOptimal, ethDesired);
        }
    }
}
