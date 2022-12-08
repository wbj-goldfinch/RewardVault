// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/RewardVault.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {RewardVault, StateLib, AccountLib} from "../src/RewardVault.sol";

contract RewardVaultTest is Test {
    // 1 reward per token per second
    uint256 public rewardsPerTokenPerSecond = 1e18;
    address me = address(this);

    RewardToken rewardToken = new RewardToken();
    DepositToken depositToken = new DepositToken();
    RewardVault public c = new RewardVault(depositToken, rewardToken, rewardsPerTokenPerSecond);

    function setUp() external {
        rewardToken.mintTo(address(c), type(uint256).max);
        depositToken.mintTo(address(this), type(uint256).max);
    }

    function testDeposit(uint256 firstDeposit, uint256 secondDeposit) external {
        vm.assume(firstDeposit > 0 && firstDeposit <= type(uint128).max);
        vm.assume(secondDeposit > 0 && secondDeposit <= type(uint128).max);

        // first deposit
        uint256 balanceBeforeFirstDeposit = depositToken.balanceOf(me);
        depositToken.approve(address(c), firstDeposit);
        uint256 newBalanceAfterFirstDeposit = c.deposit(firstDeposit);
        assertEq(depositToken.balanceOf(me), balanceBeforeFirstDeposit - firstDeposit, "didnt take enough depositToken");
        assertEq(firstDeposit, newBalanceAfterFirstDeposit);
        assertEq(c.balanceOf(me), firstDeposit);

        // second deposit
        depositToken.approve(address(c), secondDeposit);
        uint256 newBalanceAfterSecondDeposit = c.deposit(secondDeposit);
        assertEq(newBalanceAfterSecondDeposit, firstDeposit + secondDeposit);
        assertEq(c.balanceOf(me), firstDeposit + secondDeposit);
    }

    function testWithdrawFailsIfBalanceIsTooLow(uint256 depositAmount, uint256 withdrawAmount)
        external
        withDeposit(depositAmount)
    {
        vm.assume(withdrawAmount > depositAmount);

        vm.expectRevert(abi.encodeWithSelector(AccountLib.InsufficientBalance.selector));
        c.withdraw(withdrawAmount);
    }

    function testWithdrawSucceedsWithSufficientBalance(uint256 depositAmount, uint256 withdrawAmount) external {
        vm.assume(withdrawAmount <= depositAmount);
        depositToken.approve(address(c), depositAmount);
        c.deposit(depositAmount);
    }

    function testClaim(uint256 depositAmount) external withDeposit(depositAmount) {
        vm.assume(depositAmount > 1e18);
        vm.warp(block.timestamp + 100);
        assertGt(c.previewClaim(), 0);
    }

    modifier withDeposit(uint256 amount) {
        depositToken.approve(address(c), amount);
        c.deposit(amount);
        _;
    }
}

contract RewardToken is ERC20("Reward", "Reward") {
    function mintTo(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract DepositToken is ERC20("Deposit", "Deposit") {
    function mintTo(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
