// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/ICampaignInterfaces.sol";

// Uniswap V2 interfaces
interface IUniswapV2Router02 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
    
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);
    
    function getAmountsOut(uint amountIn, address[] calldata path)
        external view returns (uint[] memory amounts);
}

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function totalSupply() external view returns (uint);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function transfer(address to, uint value) external returns (bool);
    function balanceOf(address account) external view returns (uint);
}

/**
 * @title DEXIntegrator
 * @dev Handles integration with Uniswap V2 for token launches
 */
contract DEXIntegrator is IDEXIntegrator, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // Uniswap V2 Router
    IUniswapV2Router02 public immutable uniswapRouter;
    IUniswapV2Factory public immutable uniswapFactory;
    
    // Factory contract
    address public immutable factory;
    
    // Liquidity lock duration (can be overridden per campaign)
    uint256 public defaultLockDuration = 365 days; // 1 year
    
    // Locked liquidity tracking: pair => unlock timestamp
    mapping(address => uint256) public liquidityUnlockTime;
    mapping(address => address) public liquidityOwner; // pair => campaign creator
    mapping(address => uint256) public lockedLiquidity; // pair => LP token amount
    
    // Events
    event PairCreated(address indexed token, address indexed pair);
    event LiquidityAdded(address indexed token, address indexed pair, uint256 tokenAmount, uint256 ethAmount, uint256 liquidity);
    event LiquidityRemoved(address indexed token, address indexed pair, uint256 liquidity, uint256 tokenAmount, uint256 ethAmount);
    event LiquidityLocked(address indexed pair, uint256 unlockTime, uint256 amount);
    event LiquidityUnlocked(address indexed pair, address indexed owner, uint256 amount);

    modifier onlyFactory() {
        require(msg.sender == factory, "Only factory");
        _;
    }

    modifier onlyCampaign() {
        // This will be validated by checking if the sender is a valid campaign
        require(_isValidCampaign(msg.sender), "Only campaign contract");
        _;
    }

    constructor(
        address uniswapRouter_,
        address factory_
    ) Ownable(msg.sender) {
        require(uniswapRouter_ != address(0), "Invalid router address");
        require(factory_ != address(0), "Invalid factory address");
        
        uniswapRouter = IUniswapV2Router02(uniswapRouter_);
        uniswapFactory = IUniswapV2Factory(IUniswapV2Router02(uniswapRouter_).factory());
        factory = factory_;
    }

    /**
     * @dev Create a Uniswap pair for a token
     * @param token Address of the campaign token
     * @return pair Address of the created pair
     */
    function createUniswapPair(address token) external override onlyCampaign returns (address pair) {
        require(token != address(0), "Invalid token address");
        
        address weth = uniswapRouter.WETH();
        
        // Check if pair already exists
        pair = uniswapFactory.getPair(token, weth);
        if (pair == address(0)) {
            // Create new pair
            pair = uniswapFactory.createPair(token, weth);
            emit PairCreated(token, pair);
        }
        
        return pair;
    }

    /**
     * @dev Add initial liquidity to a token pair
     * @param token Address of the campaign token
     * @param tokenAmount Amount of tokens to add
     * @param ethAmount Amount of ETH to add
     * @param to Address to receive LP tokens (usually this contract for locking)
     * @return amountToken Actual amount of tokens added
     * @return amountETH Actual amount of ETH added
     * @return liquidity Amount of LP tokens minted
     */
    function addInitialLiquidity(
        address token,
        uint256 tokenAmount,
        uint256 ethAmount,
        address to
    ) external payable override onlyCampaign nonReentrant returns (
        uint256 amountToken,
        uint256 amountETH,
        uint256 liquidity
    ) {
        require(token != address(0), "Invalid token address");
        require(tokenAmount > 0, "Token amount must be positive");
        require(ethAmount > 0 && msg.value >= ethAmount, "Insufficient ETH");
        require(to != address(0), "Invalid recipient");

        // Transfer tokens from campaign to this contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), tokenAmount);
        
        // Approve router to spend tokens
        IERC20(token).approve(address(uniswapRouter), tokenAmount);
        
        // Add liquidity
        (amountToken, amountETH, liquidity) = uniswapRouter.addLiquidityETH{value: ethAmount}(
            token,
            tokenAmount,
            0, // Accept any amount of tokens
            0, // Accept any amount of ETH
            to,
            block.timestamp + 300 // 5 minutes deadline
        );
        
        // Refund excess ETH
        if (msg.value > amountETH) {
            payable(msg.sender).transfer(msg.value - amountETH);
        }
        
        // Get pair address
        address pair = uniswapFactory.getPair(token, uniswapRouter.WETH());
        
        emit LiquidityAdded(token, pair, amountToken, amountETH, liquidity);
        
        return (amountToken, amountETH, liquidity);
    }

    /**
     * @dev Remove liquidity from a token pair
     * @param token Address of the campaign token
     * @param liquidity Amount of LP tokens to remove
     * @param to Address to receive tokens and ETH
     * @return amountToken Amount of tokens received
     * @return amountETH Amount of ETH received
     */
    function removeLiquidity(
        address token,
        uint256 liquidity,
        address to
    ) external override onlyCampaign nonReentrant returns (
        uint256 amountToken,
        uint256 amountETH
    ) {
        require(token != address(0), "Invalid token address");
        require(liquidity > 0, "Liquidity must be positive");
        require(to != address(0), "Invalid recipient");

        address pair = uniswapFactory.getPair(token, uniswapRouter.WETH());
        require(pair != address(0), "Pair does not exist");
        
        // Check if liquidity is locked
        require(block.timestamp >= liquidityUnlockTime[pair], "Liquidity is locked");
        
        // Transfer LP tokens from campaign to this contract
        IUniswapV2Pair(pair).transfer(address(this), liquidity);
        
        // Approve router to spend LP tokens
        IERC20(pair).approve(address(uniswapRouter), liquidity);
        
        // Remove liquidity
        (amountToken, amountETH) = uniswapRouter.removeLiquidityETH(
            token,
            liquidity,
            0, // Accept any amount of tokens
            0, // Accept any amount of ETH
            to,
            block.timestamp + 300 // 5 minutes deadline
        );
        
        emit LiquidityRemoved(token, pair, liquidity, amountToken, amountETH);
        
        return (amountToken, amountETH);
    }

    /**
     * @dev Lock liquidity tokens for a specified duration
     * @param token Address of the campaign token
     * @param lockDuration Duration to lock liquidity (in seconds)
     * @param owner Address that will be able to unlock (campaign creator)
     */
    function lockLiquidity(
        address token,
        uint256 lockDuration,
        address owner
    ) external onlyCampaign {
        require(token != address(0), "Invalid token address");
        require(lockDuration > 0, "Lock duration must be positive");
        require(owner != address(0), "Invalid owner address");

        address pair = uniswapFactory.getPair(token, uniswapRouter.WETH());
        require(pair != address(0), "Pair does not exist");
        
        uint256 lpBalance = IUniswapV2Pair(pair).balanceOf(address(this));
        require(lpBalance > 0, "No LP tokens to lock");
        
        uint256 unlockTime = block.timestamp + lockDuration;
        liquidityUnlockTime[pair] = unlockTime;
        liquidityOwner[pair] = owner;
        lockedLiquidity[pair] = lpBalance;
        
        emit LiquidityLocked(pair, unlockTime, lpBalance);
    }

    /**
     * @dev Unlock and withdraw liquidity tokens (only after lock period)
     * @param token Address of the campaign token
     */
    function unlockLiquidity(address token) external {
        require(token != address(0), "Invalid token address");

        address pair = uniswapFactory.getPair(token, uniswapRouter.WETH());
        require(pair != address(0), "Pair does not exist");
        require(msg.sender == liquidityOwner[pair], "Not liquidity owner");
        require(block.timestamp >= liquidityUnlockTime[pair], "Liquidity still locked");
        
        uint256 amount = lockedLiquidity[pair];
        require(amount > 0, "No liquidity to unlock");
        
        // Reset lock data
        liquidityUnlockTime[pair] = 0;
        liquidityOwner[pair] = address(0);
        lockedLiquidity[pair] = 0;
        
        // Transfer LP tokens to owner
        IUniswapV2Pair(pair).transfer(msg.sender, amount);
        
        emit LiquidityUnlocked(pair, msg.sender, amount);
    }

    /**
     * @dev Estimate ETH required for specific token price
     * @param token Address of the campaign token
     * @param tokenAmount Amount of tokens for liquidity
     * @param desiredPrice Desired price per token in wei
     * @return Required ETH amount
     */
    function estimateRequiredETH(
        address token,
        uint256 tokenAmount,
        uint256 desiredPrice
    ) external pure override returns (uint256) {
        require(tokenAmount > 0, "Token amount must be positive");
        require(desiredPrice > 0, "Price must be positive");
        
        // ETH required = tokenAmount * desiredPrice
        return tokenAmount * desiredPrice / 1e18;
    }

    /**
     * @dev Get pool information for a token pair
     * @param pair Address of the pair
     * @return reserve0 Reserve of token0
     * @return reserve1 Reserve of token1  
     * @return totalSupply Total LP token supply
     */
    function getPoolInfo(address pair) external view override returns (
        uint256 reserve0,
        uint256 reserve1,
        uint256 totalSupply
    ) {
        require(pair != address(0), "Invalid pair address");
        
        IUniswapV2Pair pairContract = IUniswapV2Pair(pair);
        (uint112 _reserve0, uint112 _reserve1,) = pairContract.getReserves();
        
        return (uint256(_reserve0), uint256(_reserve1), pairContract.totalSupply());
    }

    /**
     * @dev Get current token price from DEX
     * @param token Address of the campaign token
     * @return Price per token in wei
     */
    function getCurrentTokenPrice(address token) external view returns (uint256) {
        address pair = uniswapFactory.getPair(token, uniswapRouter.WETH());
        if (pair == address(0)) {
            return 0; // No pair exists
        }
        
        (uint256 reserve0, uint256 reserve1,) = this.getPoolInfo(pair);
        if (reserve0 == 0 || reserve1 == 0) {
            return 0; // No liquidity
        }
        
        // Determine which reserve is which token
        address token0 = IUniswapV2Pair(pair).token0();
        
        if (token0 == token) {
            // token is token0, WETH is token1
            // Price = reserve1 / reserve0 (WETH per token)
            return (reserve1 * 1e18) / reserve0;
        } else {
            // token is token1, WETH is token0
            // Price = reserve0 / reserve1 (WETH per token)
            return (reserve0 * 1e18) / reserve1;
        }
    }

    /**
     * @dev Get liquidity lock information
     * @param token Address of the campaign token
     * @return unlockTime When liquidity can be unlocked
     * @return owner Who can unlock the liquidity
     * @return amount Amount of LP tokens locked
     */
    function getLiquidityLockInfo(address token) external view returns (
        uint256 unlockTime,
        address owner,
        uint256 amount
    ) {
        address pair = uniswapFactory.getPair(token, uniswapRouter.WETH());
        if (pair == address(0)) {
            return (0, address(0), 0);
        }
        
        return (
            liquidityUnlockTime[pair],
            liquidityOwner[pair],
            lockedLiquidity[pair]
        );
    }

    /**
     * @dev Update default lock duration (only owner)
     * @param newDuration New default lock duration in seconds
     */
    function updateDefaultLockDuration(uint256 newDuration) external onlyOwner {
        require(newDuration > 0, "Duration must be positive");
        defaultLockDuration = newDuration;
    }

    /**
     * @dev Emergency function to recover stuck tokens
     * @param token Token address to recover
     * @param to Address to send tokens to
     * @param amount Amount to recover
     */
    function emergencyTokenRecovery(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        require(token != address(0), "Invalid token address");
        require(to != address(0), "Invalid recipient");
        
        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @dev Emergency function to recover stuck ETH
     * @param to Address to send ETH to
     * @param amount Amount to recover
     */
    function emergencyETHRecovery(address payable to, uint256 amount) external onlyOwner {
        require(to != address(0), "Invalid recipient");
        require(address(this).balance >= amount, "Insufficient balance");
        
        to.transfer(amount);
    }

    /**
     * @dev Check if an address is a valid campaign contract
     * @param campaign Address to check
     * @return Whether the address is a valid campaign
     */
    function _isValidCampaign(address campaign) internal view returns (bool) {
        // Check with the factory to see if the address is a valid campaign
        // For testing: check if campaign is registered in first few campaign IDs
        for (uint256 i = 0; i < 10; i++) {
            try ICrowdfundingFactory(factory).getCampaignDetails(i) returns (address addr, address) {
                if (addr == campaign) {
                    return true;
                }
            } catch {
                // Campaign ID doesn't exist, continue to next
                continue;
            }
        }
        return false;
    }

    /**
     * @dev Receive ETH function
     */
    receive() external payable {
        // Allow contract to receive ETH for liquidity operations
    }
}
