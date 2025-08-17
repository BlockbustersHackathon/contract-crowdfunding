// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./CampaignToken.sol";

contract TokenFactory {
    event TokenCreated(
        address indexed tokenAddress,
        address indexed campaignAddress,
        string name,
        string symbol
    );
    
    function createToken(
        string memory name,
        string memory symbol,
        address campaignAddress,
        address owner
    ) external returns (address) {
        require(bytes(name).length > 0, "TokenFactory: Name cannot be empty");
        require(bytes(symbol).length > 0, "TokenFactory: Symbol cannot be empty");
        require(campaignAddress != address(0), "TokenFactory: Invalid campaign address");
        require(owner != address(0), "TokenFactory: Invalid owner address");
        
        CampaignToken token = new CampaignToken(
            name,
            symbol,
            campaignAddress,
            owner
        );
        
        emit TokenCreated(address(token), campaignAddress, name, symbol);
        
        return address(token);
    }
}