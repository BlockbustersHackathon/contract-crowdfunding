// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/CrowdfundingFactory.sol";
import "../../src/Treasury.sol";
import "../../src/PricingCurve.sol";
import "../../src/DEXIntegrator.sol";
import "../../src/Campaign.sol";
import "../../src/CampaignToken.sol";

// Mock Uniswap contracts for testing
contract MockUniswapFactory {
    mapping(address => mapping(address => address)) public pairs;
    
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        pair = address(uint160(uint256(keccak256(abi.encodePacked(tokenA, tokenB, block.timestamp)))));
        pairs[tokenA][tokenB] = pair;
        pairs[tokenB][tokenA] = pair;
    }
    
    function getPair(address tokenA, address tokenB) external view returns (address) {
        return pairs[tokenA][tokenB];
    }
}

contract MockUniswapRouter {
    MockUniswapFactory public factory;
    address public WETH;
    
    constructor() {
        factory = new MockUniswapFactory();
        WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // Mainnet WETH address for consistency
    }
    
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        // Mock implementation
        amountA = amountADesired;
        amountB = amountBDesired;
        liquidity = (amountA + amountB) / 2; // Simple mock calculation
    }
    
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        // Mock implementation
        amountToken = amountTokenDesired;
        amountETH = msg.value;
        liquidity = (amountToken + amountETH) / 2; // Simple mock calculation
    }
}

// Mock factory for treasury validation
contract MockFactory {
    mapping(uint256 => address) public campaigns;
    mapping(address => bool) public admins;
    
    function registerCampaign(uint256 campaignId, address campaignAddress) external {
        campaigns[campaignId] = campaignAddress;
    }
    
    function getCampaignDetails(uint256 campaignId) external view returns (address campaignAddress, address tokenAddress) {
        campaignAddress = campaigns[campaignId];
        tokenAddress = address(0); // Not needed for treasury validation
    }
    
    function isAdmin(address account) external view returns (bool) {
        return admins[account];
    }
    
    function setAdmin(address account, bool isAdminValue) external {
        admins[account] = isAdminValue;
    }
}

contract BaseSetup is Test {
    // System contracts
    CrowdfundingFactory public factory;
    Treasury public treasury;
    PricingCurve public pricingCurve;
    DEXIntegrator public dexIntegrator;
    
    // Test accounts
    address public constant ADMIN = address(0x1);
    address public constant CREATOR = address(0x2);
    address public constant CONTRIBUTOR_1 = address(0x3);
    address public constant CONTRIBUTOR_2 = address(0x4);
    address public constant FEE_RECIPIENT = address(0x5);
    address public constant ATTACKER = address(0x666);
    
    // Mock Uniswap router for testing
    MockUniswapRouter public mockRouter;
    MockFactory public mockFactory;
    
    function setUp() public virtual {
        // Label addresses for better debugging
        vm.label(ADMIN, "Admin");
        vm.label(CREATOR, "Creator");
        vm.label(CONTRIBUTOR_1, "Contributor1");
        vm.label(CONTRIBUTOR_2, "Contributor2");
        vm.label(FEE_RECIPIENT, "FeeRecipient");
        vm.label(ATTACKER, "Attacker");
        
        // Deploy system
        vm.startPrank(ADMIN);
        deploySystem();
        vm.stopPrank();
        
        // Give test accounts some ETH
        vm.deal(CREATOR, 100 ether);
        vm.deal(CONTRIBUTOR_1, 100 ether);
        vm.deal(CONTRIBUTOR_2, 100 ether);
        vm.deal(ATTACKER, 100 ether);
    }
    
    function deploySystem() internal {
        // Deploy mock contracts first
        mockRouter = new MockUniswapRouter();
        mockFactory = new MockFactory();
        
        // Set up mock factory admin
        mockFactory.setAdmin(ADMIN, true);
        
        // Deploy pricing curve (no dependencies)
        pricingCurve = new PricingCurve();
        
        // Deploy treasury and dexIntegrator with mock factory
        treasury = new Treasury(address(mockFactory), FEE_RECIPIENT);
        dexIntegrator = new DEXIntegrator(address(mockRouter), address(mockFactory));
        
        // Deploy the real factory
        factory = new CrowdfundingFactory(
            address(treasury),
            address(pricingCurve),
            payable(address(dexIntegrator)),
            FEE_RECIPIENT
        );
        
        // Transfer ownership to admin
        treasury.transferOwnership(ADMIN);
        dexIntegrator.transferOwnership(ADMIN);
    }
}
