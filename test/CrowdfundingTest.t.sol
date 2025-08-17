// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./fixtures/BaseSetup.sol";

contract CrowdfundingTest is BaseSetup {
    function testFactoryDeployment() public {
        assertEq(address(factory.treasury()), address(treasury));
        assertEq(address(factory.pricingCurve()), address(pricingCurve));
        assertEq(address(factory.dexIntegrator()), address(dexIntegrator));
        assertEq(factory.feeRecipient(), FEE_RECIPIENT);
    }

    // Basic test to ensure contracts compile and deploy correctly
    function testContractsExist() public {
        assertTrue(address(factory) != address(0));
        assertTrue(address(treasury) != address(0));
        assertTrue(address(pricingCurve) != address(0));
        assertTrue(address(dexIntegrator) != address(0));
    }
}
