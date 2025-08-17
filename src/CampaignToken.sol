// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/ICampaignInterfaces.sol";

contract CampaignToken is ERC20, ERC20Permit, Ownable, ICampaignToken {
    address public immutable campaignAddress;
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10**18; // 1 billion tokens max
    
    modifier onlyCampaign() {
        require(msg.sender == campaignAddress, "CampaignToken: Only campaign can call");
        _;
    }
    
    constructor(
        string memory name,
        string memory symbol,
        address _campaignAddress,
        address _owner
    ) ERC20(name, symbol) ERC20Permit(name) Ownable(_owner) {
        require(_campaignAddress != address(0), "CampaignToken: Invalid campaign address");
        require(_owner != address(0), "CampaignToken: Invalid owner address");
        campaignAddress = _campaignAddress;
    }
    
    function mint(address to, uint256 amount) external onlyCampaign {
        require(to != address(0), "CampaignToken: Cannot mint to zero address");
        require(amount > 0, "CampaignToken: Amount must be greater than zero");
        require(totalSupply() + amount <= MAX_SUPPLY, "CampaignToken: Exceeds max supply");
        
        _mint(to, amount);
    }
    
    function burn(uint256 amount) external {
        require(amount > 0, "CampaignToken: Amount must be greater than zero");
        require(balanceOf(msg.sender) >= amount, "CampaignToken: Insufficient balance");
        
        _burn(msg.sender, amount);
    }
    
    function getCampaignAddress() external view returns (address) {
        return campaignAddress;
    }
    
    function decimals() public pure override returns (uint8) {
        return 18;
    }
}