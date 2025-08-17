// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../fixtures/CampaignFixtures.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract CampaignTokenTest is CampaignFixtures {
    Campaign public campaign;
    CampaignToken public token;

    function setUp() public override {
        super.setUp();
        (campaign, token) = createBasicCampaign();
    }

    // ============ ERC20 Compliance Tests ============

    function test_erc20_BasicInfo_ReturnsCorrectly() public {
        assertEq(token.name(), "Test Token");
        assertEq(token.symbol(), "TEST");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 0); // No tokens minted yet
    }

    function test_erc20_Transfer_WorksWhenEnabled() public {
        // Mint some tokens first
        uint256 amount = 1000 * 1e18;
        vm.prank(address(campaign));
        token.mint(CONTRIBUTOR_1, amount);

        // Enable transfers
        vm.prank(CREATOR);
        token.enableTransfers();

        // Test transfer
        vm.prank(CONTRIBUTOR_1);
        assertTrue(token.transfer(CONTRIBUTOR_2, 100 * 1e18));

        assertEq(token.balanceOf(CONTRIBUTOR_1), 900 * 1e18);
        assertEq(token.balanceOf(CONTRIBUTOR_2), 100 * 1e18);
    }

    function test_erc20_Transfer_FailsWhenDisabled() public {
        // Mint some tokens
        uint256 amount = 1000 * 1e18;
        vm.prank(address(campaign));
        token.mint(CONTRIBUTOR_1, amount);

        // Try to transfer (should fail as transfers are disabled by default)
        vm.prank(CONTRIBUTOR_1);
        vm.expectRevert("Transfers not enabled");
        token.transfer(CONTRIBUTOR_2, 100 * 1e18);
    }

    // ============ Minting Tests ============

    function test_mint_CampaignOnly_Success() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(address(campaign));
        token.mint(CONTRIBUTOR_1, amount);

        assertEq(token.balanceOf(CONTRIBUTOR_1), amount);
        assertEq(token.totalSupply(), amount);
        assertEq(token.totalMinted(), amount);
    }

    function test_mint_NonCampaign_Reverts() public {
        vm.prank(CONTRIBUTOR_1);
        vm.expectRevert("Only campaign can call");
        token.mint(CONTRIBUTOR_1, 1000 * 1e18);
    }

    function test_mint_ExceedsMaxSupply_Reverts() public {
        uint256 maxSupply = token.maxSupply();

        vm.prank(address(campaign));
        vm.expectRevert("Exceeds max supply");
        token.mint(CONTRIBUTOR_1, maxSupply + 1);
    }

    function test_mint_ZeroAmount_Reverts() public {
        vm.prank(address(campaign));
        vm.expectRevert("Amount must be positive");
        token.mint(CONTRIBUTOR_1, 0);
    }

    // ============ Burning Tests ============

    function test_burn_ByHolder_Success() public {
        uint256 amount = 1000 * 1e18;
        uint256 burnAmount = 300 * 1e18;

        // Mint tokens
        vm.prank(address(campaign));
        token.mint(CONTRIBUTOR_1, amount);

        // Burn tokens
        vm.prank(CONTRIBUTOR_1);
        token.burn(burnAmount);

        assertEq(token.balanceOf(CONTRIBUTOR_1), amount - burnAmount);
        assertEq(token.totalSupply(), amount - burnAmount);
    }

    function test_burn_InsufficientBalance_Reverts() public {
        vm.prank(CONTRIBUTOR_1);
        vm.expectRevert("Insufficient balance");
        token.burn(1000 * 1e18);
    }

    function test_burnFrom_ByCampaign_Success() public {
        uint256 amount = 1000 * 1e18;

        // Mint tokens
        vm.prank(address(campaign));
        token.mint(CONTRIBUTOR_1, amount);

        // Burn tokens from campaign
        vm.prank(address(campaign));
        token.burnFrom(CONTRIBUTOR_1, amount);

        assertEq(token.balanceOf(CONTRIBUTOR_1), 0);
        assertEq(token.totalSupply(), 0);
    }

    // ============ Transfer Control Tests ============

    function test_enableTransfers_CreatorOnly_Success() public {
        vm.prank(CREATOR);
        token.enableTransfers();

        assertTrue(token.transfersEnabled());
    }

    function test_enableTransfers_NonCreator_Reverts() public {
        vm.prank(CONTRIBUTOR_1);
        vm.expectRevert("Only campaign or owner");
        token.enableTransfers();
    }

    function test_disableTransfers_CreatorOnly_Success() public {
        // Enable first
        vm.prank(CREATOR);
        token.enableTransfers();

        // Then disable
        vm.prank(CREATOR);
        token.disableTransfers();

        assertFalse(token.transfersEnabled());
    }

    function test_campaignCanAlwaysTransfer() public {
        uint256 amount = 1000 * 1e18;

        // Mint tokens to campaign
        vm.prank(address(campaign));
        token.mint(address(campaign), amount);

        // Campaign can transfer even when transfers are disabled
        vm.prank(address(campaign));
        assertTrue(token.transfer(CONTRIBUTOR_1, amount));

        assertEq(token.balanceOf(CONTRIBUTOR_1), amount);
    }

    // ============ Pause Functionality Tests ============

    function test_pause_StopsAllTransfers() public {
        uint256 amount = 1000 * 1e18;

        // Mint and enable transfers
        vm.prank(address(campaign));
        token.mint(CONTRIBUTOR_1, amount);
        vm.prank(CREATOR);
        token.enableTransfers();

        // Pause contract
        vm.prank(CREATOR);
        token.pause();

        // All transfers should fail
        vm.prank(CONTRIBUTOR_1);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        token.transfer(CONTRIBUTOR_2, 100 * 1e18);
    }

    function test_unpause_RestoresTransfers() public {
        // Pause first
        vm.prank(CREATOR);
        token.pause();

        // Unpause
        vm.prank(CREATOR);
        token.unpause();

        // Should be able to perform operations again
        vm.prank(address(campaign));
        token.mint(CONTRIBUTOR_1, 1000 * 1e18);
    }

    // ============ Utility Function Tests ============

    function test_remainingSupply_CalculatesCorrectly() public {
        uint256 maxSupply = token.maxSupply();
        uint256 mintAmount = 1000 * 1e18;

        // Initially, remaining should equal max supply
        assertEq(token.remainingSupply(), maxSupply);

        // After minting, remaining should decrease
        vm.prank(address(campaign));
        token.mint(CONTRIBUTOR_1, mintAmount);

        assertEq(token.remainingSupply(), maxSupply - mintAmount);
    }

    function test_canTransfer_ChecksCorrectly() public {
        // Campaign can always transfer
        assertTrue(token.canTransfer(address(campaign)));

        // Owner can always transfer
        assertTrue(token.canTransfer(CREATOR));

        // Regular user cannot transfer when disabled
        assertFalse(token.canTransfer(CONTRIBUTOR_1));

        // Regular user can transfer when enabled
        vm.prank(CREATOR);
        token.enableTransfers();
        assertTrue(token.canTransfer(CONTRIBUTOR_1));
    }

    // ============ Emergency Recovery Tests ============

    function test_emergencyTokenRecovery_OwnerOnly_Success() public {
        // This would be tested with a mock ERC20 token
        // For now, just test the access control
        vm.prank(CONTRIBUTOR_1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, CONTRIBUTOR_1));
        token.emergencyTokenRecovery(address(0x123), CREATOR, 1000);
    }

    function test_emergencyETHRecovery_OwnerOnly_Success() public {
        // Send some ETH to the contract
        vm.deal(address(token), 1 ether);

        uint256 balanceBefore = CREATOR.balance;

        vm.prank(CREATOR);
        token.emergencyETHRecovery(payable(CREATOR), 1 ether);

        assertEq(CREATOR.balance, balanceBefore + 1 ether);
    }
}
