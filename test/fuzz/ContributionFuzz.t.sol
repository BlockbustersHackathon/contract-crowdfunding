// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../utils/BaseTest.sol";

contract ContributionFuzzTest is BaseTest {
    uint256 campaignId;
    Campaign campaign;

    function setUp() public override {
        super.setUp();
        campaignId = createTestCampaign();
        campaign = getCampaign(campaignId);
    }

    function testFuzz_Contribute_RandomAmounts(uint256 amount) public {
        // Bound the amount to reasonable range - must be at least MIN_CONTRIBUTION
        amount = bound(amount, 1e6, 10000e6); // 1 USDC to 10,000 USDC

        // Ensure amount doesn't exceed funding goal to avoid campaign ending
        if (amount >= FUNDING_GOAL) {
            amount = FUNDING_GOAL - 1e6;
        }

        // Give contributor enough USDC
        vm.prank(deployer);
        usdcToken.transfer(contributor1, amount + 1000e6);

        vm.startPrank(contributor1);
        usdcToken.approve(address(campaign), amount);
        campaign.contribute(amount);
        vm.stopPrank();

        // Verify contribution recorded correctly
        Contribution memory contrib = campaign.getContribution(contributor1);
        assertEq(contrib.amount, amount);
        assertEq(contrib.contributor, contributor1);
        assertGt(contrib.tokenAllocation, 0);

        // Verify campaign state updated
        CampaignData memory data = campaign.getCampaignDetails();
        assertEq(data.totalRaised, amount);
        assertEq(uint256(data.state), uint256(CampaignState.Active));
    }

    function testFuzz_MultipleContributions_RandomOrder(uint256[] memory amounts, uint8 contributorIndex) public {
        // Limit array size and contributor index
        vm.assume(amounts.length > 0 && amounts.length <= 10);
        contributorIndex = uint8(bound(contributorIndex, 0, 2)); // Use 3 contributors

        address[3] memory contributors = [contributor1, contributor2, contributor3];

        uint256 totalContributed = 0;

        for (uint256 i = 0; i < amounts.length; i++) {
            // Bound each amount
            amounts[i] = bound(amounts[i], 1e6, 1000e6); // 1 to 1000 USDC

            address currentContributor = contributors[contributorIndex % 3];
            vm.prank(deployer);
            usdcToken.transfer(currentContributor, amounts[i] + 100e6);

            // Skip if campaign would exceed funding goal
            if (totalContributed + amounts[i] > FUNDING_GOAL) {
                continue;
            }

            vm.startPrank(currentContributor);
            usdcToken.approve(address(campaign), amounts[i]);
            campaign.contribute(amounts[i]);
            vm.stopPrank();

            totalContributed += amounts[i];

            // Update contributor index for next iteration
            contributorIndex = uint8((contributorIndex + 1) % 3);
        }

        // Verify total raised is correct
        CampaignData memory data = campaign.getCampaignDetails();
        assertEq(data.totalRaised, totalContributed);
    }

    function testFuzz_ContributionTiming_TokenAllocation(uint256 amount, uint256 timeElapsed) public {
        amount = bound(amount, 1e6, 5000e6); // 1 to 5000 USDC
        timeElapsed = bound(timeElapsed, 0, CAMPAIGN_DURATION - 1);

        vm.prank(deployer);
        usdcToken.transfer(contributor1, amount + 100e6);

        // Fast forward time
        vm.warp(block.timestamp + timeElapsed);

        vm.startPrank(contributor1);
        usdcToken.approve(address(campaign), amount);
        campaign.contribute(amount);
        vm.stopPrank();

        Contribution memory contrib = campaign.getContribution(contributor1);

        // Token allocation should be positive
        assertGt(contrib.tokenAllocation, 0);

        // Earlier contributions should generally get more tokens
        uint256 baseTokens = amount * 1000; // Base rate
        if (timeElapsed <= CAMPAIGN_DURATION / 4) {
            // Should get early bird bonus
            assertGe(contrib.tokenAllocation, baseTokens);
        }
    }

    function testFuzz_ContributeAndRefund_Consistency(uint256 contributionAmount, uint256 timeDelay) public {
        contributionAmount = bound(contributionAmount, 1e6, FUNDING_GOAL - 1000e6); // 1 USDC to funding goal - 1000 USDC
        timeDelay = bound(timeDelay, 1, CAMPAIGN_DURATION + 1 days);

        // Use strict campaign for refund testing
        uint256 strictCampaignId = createTestCampaignWithGoalRequired();
        Campaign strictCampaign = getCampaign(strictCampaignId);

        vm.prank(deployer);
        usdcToken.transfer(contributor1, contributionAmount + 100e6);
        uint256 initialBalance = usdcToken.balanceOf(contributor1);

        // Contribute
        vm.startPrank(contributor1);
        usdcToken.approve(address(strictCampaign), contributionAmount);
        strictCampaign.contribute(contributionAmount);
        vm.stopPrank();

        // Fast forward past deadline
        vm.warp(block.timestamp + timeDelay);
        strictCampaign.updateCampaignState();

        // If campaign failed, refund should work
        if (strictCampaign.getCampaignState() == CampaignState.Failed) {
            vm.prank(contributor1);
            strictCampaign.refund();

            // Should get original contribution back
            assertEq(usdcToken.balanceOf(contributor1), initialBalance);
        }
    }

    function testFuzz_TokenAllocation_Proportionality(uint256 contrib1, uint256 contrib2, uint256 contrib3) public {
        // Bound contributions
        contrib1 = bound(contrib1, 1e6, 3000e6); // 1 to 3000 USDC
        contrib2 = bound(contrib2, 1e6, 3000e6); // 1 to 3000 USDC
        contrib3 = bound(contrib3, 1e6, 3000e6); // 1 to 3000 USDC

        // Ensure we don't exceed funding goal
        uint256 total = contrib1 + contrib2 + contrib3;
        vm.assume(total <= FUNDING_GOAL);

        // Fund contributors
        vm.startPrank(deployer);
        usdcToken.transfer(contributor1, contrib1 + 100e6);
        usdcToken.transfer(contributor2, contrib2 + 100e6);
        usdcToken.transfer(contributor3, contrib3 + 100e6);
        vm.stopPrank();

        // Make contributions
        vm.startPrank(contributor1);
        usdcToken.approve(address(campaign), contrib1);
        campaign.contribute(contrib1);
        vm.stopPrank();

        vm.startPrank(contributor2);
        usdcToken.approve(address(campaign), contrib2);
        campaign.contribute(contrib2);
        vm.stopPrank();

        vm.startPrank(contributor3);
        usdcToken.approve(address(campaign), contrib3);
        campaign.contribute(contrib3);
        vm.stopPrank();

        // Get token allocations
        uint256 tokens1 = campaign.getContribution(contributor1).tokenAllocation;
        uint256 tokens2 = campaign.getContribution(contributor2).tokenAllocation;
        uint256 tokens3 = campaign.getContribution(contributor3).tokenAllocation;

        // Calculate token ratios - should be proportional to contribution ratios
        // Allow for some variance due to bonuses but contributions should be roughly proportional
        uint256 ratio1to2 = contrib1 * 1000 / contrib2;
        uint256 tokenRatio1to2 = tokens1 * 1000 / tokens2;

        // Allow 50% variance due to bonuses
        if (contrib1 > contrib2) {
            assertTrue(tokenRatio1to2 >= ratio1to2 * 500 / 1000, "Token allocation not proportional within variance");
        }

        // All allocations should be positive
        assertGt(tokens1, 0);
        assertGt(tokens2, 0);
        assertGt(tokens3, 0);
    }

    function testFuzz_CampaignParameters_Validation(
        uint256 fundingGoal,
        uint256 duration,
        uint256 creatorReserve,
        uint256 liquidityPercentage
    ) public {
        // Test parameter validation with fuzzing
        fundingGoal = bound(fundingGoal, 50e6, 15000000e6); // 50 to 15M USDC
        duration = bound(duration, 0.5 days, 365 days);
        creatorReserve = bound(creatorReserve, 0, 100);
        liquidityPercentage = bound(liquidityPercentage, 0, 100);

        vm.prank(creator);

        try factory.createCampaign(
            "ipfs://fuzz-test", fundingGoal, duration, creatorReserve, liquidityPercentage, true, "Fuzz Token", "FUZZ"
        ) returns (uint256 newCampaignId) {
            // If successful, verify the campaign was created properly
            CampaignData memory data = factory.getCampaign(newCampaignId);
            assertEq(data.fundingGoal, fundingGoal);
            assertEq(data.creatorReservePercentage, creatorReserve);
            assertEq(data.liquidityPercentage, liquidityPercentage);
            assertEq(data.creator, creator);

            // Verify parameters are within valid ranges for successful creation
            assertTrue(fundingGoal >= 100e6 && fundingGoal <= 10000000e6); // 100 USDC to 10M USDC
            assertTrue(duration >= 1 days && duration <= 180 days);
            assertTrue(creatorReserve <= 50);
            assertTrue(liquidityPercentage <= 80);
        } catch {
            // Expected for invalid parameters - verify they are actually invalid
            assertTrue(
                fundingGoal < 100e6 || fundingGoal > 10000000e6 || duration < 1 days || duration > 180 days
                    || creatorReserve > 50 || liquidityPercentage > 80
            );
        }
    }

    function testFuzz_StateTransitions_RandomTiming(uint256 timeWarp) public {
        timeWarp = bound(timeWarp, 0, CAMPAIGN_DURATION * 2);

        // Partially fund campaign
        contributeToCompaign(campaignId, contributor1, FUNDING_GOAL / 2);

        // Fast forward random amount of time
        vm.warp(block.timestamp + timeWarp);
        campaign.updateCampaignState();

        CampaignState state = campaign.getCampaignState();
        // CampaignData memory data = campaign.getCampaignDetails();

        if (timeWarp <= CAMPAIGN_DURATION) {
            // Should still be active if deadline not passed
            assertEq(uint256(state), uint256(CampaignState.Active));
        } else {
            // Should succeed because allowEarlyWithdrawal is true
            assertEq(uint256(state), uint256(CampaignState.Succeeded));
        }
    }

    function testFuzz_TokenMinting_MaxSupply(uint256 mintAmount) public {
        mintAmount = bound(mintAmount, 1, type(uint128).max);

        CampaignData memory data = campaign.getCampaignDetails();
        CampaignToken token = CampaignToken(data.tokenAddress);
        uint256 maxSupply = token.MAX_SUPPLY();

        vm.prank(address(campaign));

        if (mintAmount > maxSupply) {
            vm.expectRevert("CampaignToken: Exceeds max supply");
            token.mint(contributor1, mintAmount);
        } else {
            token.mint(contributor1, mintAmount);
            assertEq(token.balanceOf(contributor1), mintAmount);
        }
    }

    function testFuzz_PricingCurve_EdgeCases(
        uint256 contribution,
        uint256 totalRaised,
        uint256 fundingGoal,
        uint256 timeRemaining,
        uint256 totalDuration
    ) public view {
        contribution = bound(contribution, 1e6, 1000000e6); // 1 to 1M USDC
        totalRaised = bound(totalRaised, 0, 10000000e6); // 0 to 10M USDC
        fundingGoal = bound(fundingGoal, 1000e6, 10000000e6); // 1000 to 10M USDC
        totalDuration = bound(totalDuration, 1 days, 365 days);
        timeRemaining = bound(timeRemaining, 0, totalDuration);

        try pricingCurve.calculateTokenAllocation(contribution, totalRaised, fundingGoal, timeRemaining, totalDuration)
        returns (uint256 tokens) {
            // Should always return positive tokens for positive contribution
            assertGt(tokens, 0);

            // Should be at least base amount
            uint256 baseTokens = contribution * 1000;
            assertGe(tokens, baseTokens);
        } catch {
            // Only acceptable failure is zero contribution or duration
            assertTrue(contribution == 0 || totalDuration == 0);
        }
    }
}
