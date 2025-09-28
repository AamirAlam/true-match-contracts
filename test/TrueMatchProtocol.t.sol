// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {TrueMatchProtocol} from "../src/TrueMatchProtocol.sol";
import {ReputationSBT} from "../src/ReputationSBT.sol";

contract MockERC20 {
    string public name = "MockToken";
    string public symbol = "MOCK";
    uint8 public decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        require(balanceOf[msg.sender] >= value, "INSUFFICIENT");
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= value, "ALLOWANCE");
        require(balanceOf[from] >= value, "BALANCE");
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - value;
        }
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
        return true;
    }
}

contract TrueMatchProtocolTest is Test {
    MockERC20 internal token;
    ReputationSBT internal sbt;
    TrueMatchProtocol internal protocol;

    address internal treasury;
    address internal alice;
    address internal bob;

    uint256 internal constant ONE = 1e18;

    function setUp() public {
        token = new MockERC20();
        sbt = new ReputationSBT();

        treasury = makeAddr("treasury");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // Fund users and treasury
        token.mint(alice, 1_000_000 * ONE);
        token.mint(bob, 1_000_000 * ONE);
        token.mint(treasury, 1_000_000 * ONE);

        protocol = new TrueMatchProtocol(address(token), treasury, address(sbt));
        // Give protocol control over SBT
        vm.prank(address(this));
        sbt.transferOwnership(address(protocol));

        // Approvals for spending
        vm.prank(alice);
        token.approve(address(protocol), type(uint256).max);
        vm.prank(bob);
        token.approve(address(protocol), type(uint256).max);

        // Treasury must approve protocol for referral payouts
        vm.prank(treasury);
        token.approve(address(protocol), type(uint256).max);
    }

    function test_stake_and_unstake_flow() public {
        // Alice stakes
        uint256 amt = 2_000 * ONE;
        vm.prank(alice);
        protocol.stake(amt);

        // Check internal state via view
        (
            uint256 staked,,uint256 credits,uint256 superlikes,uint256 boosts,,,
        ) = protocol.userView(alice);
        assertEq(staked, amt, "staked mismatch");
        assertEq(credits, 0);
        assertEq(superlikes, 0);
        assertEq(boosts, 0);

        // Request unstake and ensure cannot withdraw before cooldown
        vm.prank(alice);
        protocol.requestUnstake();
        // Attempt before cooldown should revert
        vm.prank(alice);
        vm.expectRevert(bytes("LOCKED"));
        protocol.unstake(amt);

        // After cooldown
        vm.warp(block.timestamp + protocol.unstakeCooldown());
        vm.prank(alice);
        protocol.unstake(amt);

        (staked,, , , , , ,) = protocol.userView(alice);
        assertEq(staked, 0, "should be fully unstaked");
    }

    function test_buy_and_spend_products() public {
        // Prices
        uint256 creditPrice = protocol.creditPrice();
        uint256 superlikePrice = protocol.superlikePrice();
        uint256 boostPrice = protocol.boostPrice();

        uint256 treasuryStart = token.balanceOf(treasury);

        // Buy 5 credits, 3 superlikes, 2 boosts
        vm.startPrank(alice);
        protocol.buySwipeCredits(5);
        protocol.buySuperlikes(3);
        protocol.buyBoosts(2);

        // Spend 1 each
        protocol.spendSwipe();
        protocol.spendSuperlike();
        protocol.spendBoost();
        vm.stopPrank();

        (, , uint256 credits, uint256 superlikes, uint256 boosts, , , ) = protocol.userView(alice);
        assertEq(credits, 4);
        assertEq(superlikes, 2);
        assertEq(boosts, 1);

        // Verify payment reached treasury
        uint256 expected = 5 * creditPrice + 3 * superlikePrice + 2 * boostPrice;
        assertEq(token.balanceOf(treasury), treasuryStart + expected, "treasury not paid");

        // Reverts when zero balance
        vm.prank(bob);
        vm.expectRevert(bytes("NO_CREDITS"));
        protocol.spendSwipe();
    }

    function test_reports_trigger_slash_and_reputation_drop() public {
        // Alice stakes so she can be slashed
        uint256 stakeAmt = 120 * ONE;
        vm.prank(alice);
        protocol.stake(stakeAmt);

        // Ensure threshold value
        uint256 threshold = protocol.reportValidityThreshold();
        uint256 slashPer = protocol.slashPerValidReport();
        uint256 treasuryStart = token.balanceOf(treasury);

        // Bob reports Alice threshold times
        for (uint256 i = 0; i < threshold; i++) {
            vm.prank(bob);
            protocol.reportUser(alice);
        }

        // After valid reports, Alice should be slashed and reports reset
        (uint256 staked,, , , , uint256 rep, uint256 reports, ) = protocol.userView(alice);
        uint256 expectedSlash = slashPer > stakeAmt ? stakeAmt : slashPer;
        assertEq(staked, stakeAmt - expectedSlash, "stake not slashed correctly");
        assertEq(reports, 0, "reports not reset");
        assertEq(token.balanceOf(treasury), treasuryStart + expectedSlash, "treasury not credited by slash");

        // Reputation decreased by 10 and SBT tier updated accordingly
        // Initial rep is 0, so rep should remain 0 (floored) after -10 in _updateReputation
        assertEq(rep, 0);

        // Now increase reputation positively and ensure tiering
        vm.prank(address(this));
        protocol.updateReputation(alice, 30); // tier should be 1
        (, , , , , rep, , ) = protocol.userView(alice);
        assertEq(rep, 30);

        vm.prank(address(this));
        protocol.updateReputation(alice, 75); // total 105 -> tier 2
        (, , , , , rep, , ) = protocol.userView(alice);
        assertEq(rep, 105);

        vm.prank(address(this));
        protocol.updateReputation(alice, 100); // total 205 -> tier 3
        (, , , , , rep, , ) = protocol.userView(alice);
        assertEq(rep, 205);
    }

    function test_updateReputation_onlyOwner() public {
        // Non-owner cannot call
        vm.prank(alice);
        vm.expectRevert(bytes("NOT_OWNER"));
        protocol.updateReputation(alice, 10);

        // Owner can call (this contract deployed protocol)
        vm.prank(address(this));
        protocol.updateReputation(alice, 10);
        (, , , , , uint256 rep, , ) = protocol.userView(alice);
        assertEq(rep, 10);

        // Negative delta floors at 0
        vm.prank(address(this));
        protocol.updateReputation(alice, -100);
        (, , , , , rep, , ) = protocol.userView(alice);
        assertEq(rep, 0);
    }

    function test_referral_flow() public {
        // Bob links Alice as referrer
        vm.prank(bob);
        protocol.linkReferral(alice);

        // Claim reward moves tokens from treasury to bob and alice
        uint256 refReward = protocol.referralReward();
        uint256 bobStart = token.balanceOf(bob);
        uint256 aliceStart = token.balanceOf(alice);
        uint256 treasuryStart = token.balanceOf(treasury);

        vm.prank(bob);
        protocol.claimReferralReward();

        assertEq(token.balanceOf(bob), bobStart + refReward);
        assertEq(token.balanceOf(alice), aliceStart + refReward);
        assertEq(token.balanceOf(treasury), treasuryStart - 2 * refReward);

        // Cannot claim again
        vm.prank(bob);
        vm.expectRevert(bytes("CLAIMED"));
        protocol.claimReferralReward();
    }

    function test_pause_blocks_state_changing_functions() public {
        // Owner pauses
        vm.prank(address(this));
        protocol.setPaused(true);

        vm.prank(alice);
        vm.expectRevert(bytes("PAUSED"));
        protocol.stake(1);

        vm.prank(alice);
        vm.expectRevert(bytes("PAUSED"));
        protocol.buySwipeCredits(1);

        vm.prank(alice);
        vm.expectRevert(bytes("PAUSED"));
        protocol.reportUser(bob);

        // Unpause restores functionality
        vm.prank(address(this));
        protocol.setPaused(false);
        vm.prank(alice);
        protocol.buySwipeCredits(1);
    }
}
