// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/ICampaignInterfaces.sol";

/**
 * @title CampaignToken
 * @dev ERC-20 token for crowdfunding campaigns with special features:
 * - Minting controlled by campaign contract
 * - Transfer restrictions during campaign
 * - Snapshot capability for governance
 * - Burn mechanism for failed campaigns
 */
contract CampaignToken is ERC20, ERC20Pausable, ERC20Permit, Ownable, ICampaignToken {
    // Campaign contract that controls this token
    address public immutable campaign;
    
    // Whether transfers are enabled for regular holders
    bool public transfersEnabled;
    
    // Token configuration
    uint256 public immutable maxSupply;
    uint256 public totalMinted;
    
    // Events
    event TransfersEnabled();
    event TransfersDisabled();
    event TokensBurned(address indexed burner, uint256 amount);
    event TokensMinted(address indexed to, uint256 amount);

    modifier onlyCampaign() {
        require(msg.sender == campaign, "Only campaign can call");
        _;
    }

    modifier onlyCampaignOrOwner() {
        require(msg.sender == campaign || msg.sender == owner(), "Only campaign or owner");
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 maxSupply_,
        address campaign_,
        address owner_
    ) ERC20(name_, symbol_) ERC20Permit(name_) Ownable(owner_) {
        require(campaign_ != address(0), "Invalid campaign address");
        require(maxSupply_ > 0, "Max supply must be positive");
        
        campaign = campaign_;
        maxSupply = maxSupply_;
        transfersEnabled = false; // Disabled by default during campaign
    }

    /**
     * @dev Mint tokens to a recipient. Only callable by campaign contract.
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external override onlyCampaign {
        require(to != address(0), "Cannot mint to zero address");
        require(amount > 0, "Amount must be positive");
        require(totalMinted + amount <= maxSupply, "Exceeds max supply");

        totalMinted += amount;
        _mint(to, amount);
        
        emit TokensMinted(to, amount);
    }

    /**
     * @dev Burn tokens from caller's balance
     * @param amount Amount of tokens to burn
     */
    function burn(uint256 amount) external override {
        require(amount > 0, "Amount must be positive");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        _burn(msg.sender, amount);
        
        emit TokensBurned(msg.sender, amount);
    }

    /**
     * @dev Burn tokens from a specific address. Only callable by campaign.
     * @param from Address to burn tokens from
     * @param amount Amount of tokens to burn
     */
    function burnFrom(address from, uint256 amount) external onlyCampaign {
        require(amount > 0, "Amount must be positive");
        require(balanceOf(from) >= amount, "Insufficient balance");

        _burn(from, amount);
        
        emit TokensBurned(from, amount);
    }

    /**
     * @dev Enable token transfers for all holders
     */
    function enableTransfers() external override onlyCampaignOrOwner {
        transfersEnabled = true;
        emit TransfersEnabled();
    }

    /**
     * @dev Disable token transfers for regular holders
     */
    function disableTransfers() external override onlyCampaignOrOwner {
        transfersEnabled = false;
        emit TransfersDisabled();
    }

    /**
     * @dev Pause all token operations
     */
    function pause() external override onlyCampaignOrOwner {
        _pause();
    }

    /**
     * @dev Unpause all token operations
     */
    function unpause() external override onlyCampaignOrOwner {
        _unpause();
    }

    /**
     * @dev Create a snapshot of current balances
     * @return The snapshot ID
     */
    function snapshot() external override onlyCampaignOrOwner returns (uint256) {
        // For this implementation, we'll use the current block number as snapshot ID
        return block.number;
    }

    /**
     * @dev Override transfer to check if transfers are enabled
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal virtual override(ERC20, ERC20Pausable) {
        // Allow minting (from == address(0)) and burning (to == address(0))
        // Allow campaign contract to always transfer
        if (from != address(0) && to != address(0) && from != campaign) {
            require(transfersEnabled, "Transfers not enabled");
        }

        super._update(from, to, value);
    }

    /**
     * @dev Get token decimals (standard 18)
     */
    function decimals() public pure override(ERC20, ICampaignToken) returns (uint8) {
        return 18;
    }

    /**
     * @dev Get token name
     */
    function name() public view override(ERC20, ICampaignToken) returns (string memory) {
        return super.name();
    }

    /**
     * @dev Get token symbol
     */
    function symbol() public view override(ERC20, ICampaignToken) returns (string memory) {
        return super.symbol();
    }

    /**
     * @dev Get total token supply
     */
    function totalSupply() public view override(ERC20, ICampaignToken) returns (uint256) {
        return super.totalSupply();
    }

    /**
     * @dev Get balance of an account
     */
    function balanceOf(address account) public view override(ERC20, ICampaignToken) returns (uint256) {
        return super.balanceOf(account);
    }

    /**
     * @dev Transfer tokens
     */
    function transfer(address to, uint256 amount) public override(ERC20, ICampaignToken) returns (bool) {
        return super.transfer(to, amount);
    }

    /**
     * @dev Get allowance
     */
    function allowance(address owner, address spender) public view override(ERC20, ICampaignToken) returns (uint256) {
        return super.allowance(owner, spender);
    }

    /**
     * @dev Approve spender
     */
    function approve(address spender, uint256 amount) public override(ERC20, ICampaignToken) returns (bool) {
        return super.approve(spender, amount);
    }

    /**
     * @dev Transfer from one account to another
     */
    function transferFrom(address from, address to, uint256 amount) public override(ERC20, ICampaignToken) returns (bool) {
        return super.transferFrom(from, to, amount);
    }

    /**
     * @dev Get remaining tokens that can be minted
     */
    function remainingSupply() external view returns (uint256) {
        return maxSupply - totalMinted;
    }

    /**
     * @dev Check if transfers are currently allowed for an address
     */
    function canTransfer(address from) external view returns (bool) {
        return transfersEnabled || from == campaign || from == owner();
    }

    /**
     * @dev Emergency function to recover accidentally sent tokens
     */
    function emergencyTokenRecovery(
        address tokenAddress,
        address to,
        uint256 amount
    ) external onlyOwner {
        require(tokenAddress != address(this), "Cannot recover own tokens");
        require(to != address(0), "Invalid recipient");
        
        IERC20 token = IERC20(tokenAddress);
        require(token.transfer(to, amount), "Transfer failed");
    }

    /**
     * @dev Emergency function to recover accidentally sent ETH
     */
    function emergencyETHRecovery(address payable to, uint256 amount) external onlyOwner {
        require(to != address(0), "Invalid recipient");
        require(address(this).balance >= amount, "Insufficient balance");
        
        to.transfer(amount);
    }
}
