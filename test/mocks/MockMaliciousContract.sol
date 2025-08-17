// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../src/Campaign.sol";

contract MockMaliciousContract {
    bool public attackActive;
    Campaign public targetCampaign;
    uint256 public attackCount;

    function setTarget(address _campaign) external {
        targetCampaign = Campaign(payable(_campaign));
    }

    function activateAttack() external {
        attackActive = true;
    }

    function deactivateAttack() external {
        attackActive = false;
        attackCount = 0;
    }

    function maliciousContribute() external payable {
        targetCampaign.contribute{value: msg.value}();
    }

    function maliciousRefund() external {
        targetCampaign.refund();
    }

    receive() external payable {
        if (attackActive && attackCount < 3) {
            attackCount++;
            // Attempt reentrancy - should be blocked by ReentrancyGuard
            if (address(targetCampaign) != address(0)) {
                try targetCampaign.refund() {
                    // This should fail due to reentrancy guard
                } catch {
                    // Expected to fail due to reentrancy guard
                }
            }
        }
    }

    fallback() external payable {
        if (attackActive && attackCount < 3) {
            attackCount++;
            // Attempt reentrancy on fallback - should be blocked by ReentrancyGuard
            if (address(targetCampaign) != address(0)) {
                try targetCampaign.refund() {
                    // This should fail due to reentrancy guard
                } catch {
                    // Expected to fail due to reentrancy guard
                }
            }
        }
    }
}
