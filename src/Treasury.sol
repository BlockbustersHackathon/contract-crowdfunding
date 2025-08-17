// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/ICampaignInterfaces.sol";

/**
 * @title Treasury
 * @dev Secure storage and management of campaign funds with escrow functionality
 */
contract Treasury is ITreasury, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // Factory contract that manages campaigns
    address public immutable factory;

    // Campaign balances for ETH
    mapping(uint256 => uint256) public campaignBalances;

    // Campaign balances for ERC20 tokens: campaignId => token => balance
    mapping(uint256 => mapping(address => uint256)) public campaignTokenBalances;

    // Emergency pause state
    bool public paused;

    // Platform fee recipient
    address public feeRecipient;

    // Events
    event Deposited(uint256 indexed campaignId, uint256 amount);
    event TokenDeposited(uint256 indexed campaignId, address indexed token, uint256 amount);
    event Withdrawn(uint256 indexed campaignId, address indexed to, uint256 amount);
    event TokenWithdrawn(uint256 indexed campaignId, address indexed token, address indexed to, uint256 amount);
    event Refunded(uint256 indexed campaignId, address indexed to, uint256 amount);
    event TokenRefunded(uint256 indexed campaignId, address indexed token, address indexed to, uint256 amount);
    event EmergencyWithdrawn(uint256 indexed campaignId, address indexed to, uint256 amount);
    event TreasuryPaused();
    event TreasuryUnpaused();
    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);

    modifier onlyFactory() {
        require(msg.sender == factory, "Only factory");
        _;
    }

    modifier onlyCampaign(uint256 campaignId) {
        (address campaignAddress,) = ICrowdfundingFactory(factory).getCampaignDetails(campaignId);
        require(msg.sender == campaignAddress, "Only campaign contract");
        _;
    }

    modifier notPaused() {
        require(!paused, "Treasury is paused");
        _;
    }

    constructor(address factory_, address feeRecipient_) Ownable(msg.sender) {
        require(factory_ != address(0), "Invalid factory address");
        require(feeRecipient_ != address(0), "Invalid fee recipient");

        factory = factory_;
        feeRecipient = feeRecipient_;
    }

    /**
     * @dev Deposit ETH for a campaign
     * @param campaignId ID of the campaign
     */
    function deposit(uint256 campaignId) external payable override onlyCampaign(campaignId) notPaused {
        require(msg.value > 0, "Deposit amount must be positive");

        campaignBalances[campaignId] += msg.value;

        emit Deposited(campaignId, msg.value);
    }

    /**
     * @dev Deposit ERC20 tokens for a campaign
     * @param campaignId ID of the campaign
     * @param token Address of the ERC20 token
     * @param amount Amount of tokens to deposit
     */
    function depositToken(uint256 campaignId, address token, uint256 amount)
        external
        override
        onlyCampaign(campaignId)
        notPaused
    {
        require(token != address(0), "Invalid token address");
        require(amount > 0, "Deposit amount must be positive");

        // Transfer tokens from campaign to treasury
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        campaignTokenBalances[campaignId][token] += amount;

        emit TokenDeposited(campaignId, token, amount);
    }

    /**
     * @dev Withdraw ETH from a campaign (only for successful campaigns)
     * @param campaignId ID of the campaign
     * @param to Address to withdraw to
     * @param amount Amount to withdraw
     */
    function withdraw(uint256 campaignId, address to, uint256 amount)
        external
        override
        onlyCampaign(campaignId)
        nonReentrant
        notPaused
    {
        require(to != address(0), "Invalid recipient address");
        require(amount > 0, "Withdrawal amount must be positive");
        require(campaignBalances[campaignId] >= amount, "Insufficient balance");

        campaignBalances[campaignId] -= amount;

        (bool success,) = payable(to).call{value: amount}("");
        require(success, "Transfer failed");

        emit Withdrawn(campaignId, to, amount);
    }

    /**
     * @dev Withdraw ERC20 tokens from a campaign
     * @param campaignId ID of the campaign
     * @param token Address of the ERC20 token
     * @param to Address to withdraw to
     * @param amount Amount to withdraw
     */
    function withdrawToken(uint256 campaignId, address token, address to, uint256 amount)
        external
        override
        onlyCampaign(campaignId)
        nonReentrant
        notPaused
    {
        require(token != address(0), "Invalid token address");
        require(to != address(0), "Invalid recipient address");
        require(amount > 0, "Withdrawal amount must be positive");
        require(campaignTokenBalances[campaignId][token] >= amount, "Insufficient token balance");

        campaignTokenBalances[campaignId][token] -= amount;

        IERC20(token).safeTransfer(to, amount);

        emit TokenWithdrawn(campaignId, token, to, amount);
    }

    /**
     * @dev Refund ETH to a contributor (for failed campaigns)
     * @param campaignId ID of the campaign
     * @param to Address to refund to
     * @param amount Amount to refund
     */
    function refund(uint256 campaignId, address to, uint256 amount)
        external
        override
        onlyCampaign(campaignId)
        nonReentrant
        notPaused
    {
        require(to != address(0), "Invalid recipient address");
        require(amount > 0, "Refund amount must be positive");
        require(campaignBalances[campaignId] >= amount, "Insufficient balance");

        campaignBalances[campaignId] -= amount;

        (bool success,) = payable(to).call{value: amount}("");
        require(success, "Refund failed");

        emit Refunded(campaignId, to, amount);
    }

    /**
     * @dev Refund ERC20 tokens to a contributor
     * @param campaignId ID of the campaign
     * @param token Address of the ERC20 token
     * @param to Address to refund to
     * @param amount Amount to refund
     */
    function refundToken(uint256 campaignId, address token, address to, uint256 amount)
        external
        override
        onlyCampaign(campaignId)
        nonReentrant
        notPaused
    {
        require(token != address(0), "Invalid token address");
        require(to != address(0), "Invalid recipient address");
        require(amount > 0, "Refund amount must be positive");
        require(campaignTokenBalances[campaignId][token] >= amount, "Insufficient token balance");

        campaignTokenBalances[campaignId][token] -= amount;

        IERC20(token).safeTransfer(to, amount);

        emit TokenRefunded(campaignId, token, to, amount);
    }

    /**
     * @dev Emergency withdrawal function (only owner)
     * @param campaignId ID of the campaign
     * @param to Address to withdraw to
     */
    function emergencyWithdraw(uint256 campaignId, address to) external override onlyOwner nonReentrant {
        require(to != address(0), "Invalid recipient address");

        uint256 balance = campaignBalances[campaignId];
        if (balance > 0) {
            campaignBalances[campaignId] = 0;

            (bool success,) = payable(to).call{value: balance}("");
            require(success, "Emergency withdrawal failed");

            emit EmergencyWithdrawn(campaignId, to, balance);
        }
    }

    /**
     * @dev Emergency withdrawal for ERC20 tokens
     * @param campaignId ID of the campaign
     * @param token Address of the ERC20 token
     * @param to Address to withdraw to
     */
    function emergencyTokenWithdraw(uint256 campaignId, address token, address to) external onlyOwner nonReentrant {
        require(token != address(0), "Invalid token address");
        require(to != address(0), "Invalid recipient address");

        uint256 balance = campaignTokenBalances[campaignId][token];
        if (balance > 0) {
            campaignTokenBalances[campaignId][token] = 0;

            IERC20(token).safeTransfer(to, balance);

            emit TokenWithdrawn(campaignId, token, to, balance);
        }
    }

    /**
     * @dev Get ETH balance for a campaign
     * @param campaignId ID of the campaign
     * @return Balance in wei
     */
    function getBalance(uint256 campaignId) external view override returns (uint256) {
        return campaignBalances[campaignId];
    }

    /**
     * @dev Get ERC20 token balance for a campaign
     * @param campaignId ID of the campaign
     * @param token Address of the ERC20 token
     * @return Token balance
     */
    function getTokenBalance(uint256 campaignId, address token) external view override returns (uint256) {
        return campaignTokenBalances[campaignId][token];
    }

    /**
     * @dev Pause treasury operations (emergency only)
     */
    function pause() external onlyOwner {
        paused = true;
        emit TreasuryPaused();
    }

    /**
     * @dev Unpause treasury operations
     */
    function unpause() external onlyOwner {
        paused = false;
        emit TreasuryUnpaused();
    }

    /**
     * @dev Update fee recipient address
     * @param newFeeRecipient New fee recipient address
     */
    function updateFeeRecipient(address newFeeRecipient) external onlyOwner {
        require(newFeeRecipient != address(0), "Invalid fee recipient");

        address oldRecipient = feeRecipient;
        feeRecipient = newFeeRecipient;

        emit FeeRecipientUpdated(oldRecipient, newFeeRecipient);
    }

    /**
     * @dev Collect platform fees for a campaign
     * @param campaignId ID of the campaign
     * @param feeAmount Amount of fees to collect
     */
    function collectPlatformFee(uint256 campaignId, uint256 feeAmount) external onlyCampaign(campaignId) nonReentrant {
        require(feeAmount > 0, "Fee amount must be positive");
        require(campaignBalances[campaignId] >= feeAmount, "Insufficient balance");

        campaignBalances[campaignId] -= feeAmount;

        (bool success,) = payable(feeRecipient).call{value: feeAmount}("");
        require(success, "Fee transfer failed");
    }

    /**
     * @dev Collect platform fees in ERC20 tokens
     * @param campaignId ID of the campaign
     * @param token Address of the ERC20 token
     * @param feeAmount Amount of fees to collect
     */
    function collectPlatformTokenFee(uint256 campaignId, address token, uint256 feeAmount)
        external
        onlyCampaign(campaignId)
        nonReentrant
    {
        require(token != address(0), "Invalid token address");
        require(feeAmount > 0, "Fee amount must be positive");
        require(campaignTokenBalances[campaignId][token] >= feeAmount, "Insufficient token balance");

        campaignTokenBalances[campaignId][token] -= feeAmount;

        IERC20(token).safeTransfer(feeRecipient, feeAmount);
    }

    /**
     * @dev Get total treasury ETH balance
     * @return Total ETH balance across all campaigns
     */
    function getTotalBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev Get total treasury token balance
     * @param token Address of the ERC20 token
     * @return Total token balance across all campaigns
     */
    function getTotalTokenBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }
}
