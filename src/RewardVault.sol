// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

using StateLib for State;
using StaleStateLib for StaleState;
using AccountLib for Account;
using StaleAccountLib for StaleAccount;
using SafeERC20 for IERC20;

/// @title Reward Vault
/// @author Will Johnston
/// @notice A vault that allows users to deposit tokens and earn a reward token at a specified rate
contract RewardVault {
    StaleState state;

    constructor(IERC20 depositToken, IERC20 rewardToken, uint256 rewardsPerTokenPerSecond) {
        state.init({
            depositToken: depositToken,
            rewardToken: rewardToken,
            rewardsPerTokenPerSecond: rewardsPerTokenPerSecond
        });
    }

    /**
     * @notice Deposit tokens to the vault
     */
    function deposit(uint256 amount) external returns (uint256) {
        return state.getUpdated().depositFrom(msg.sender, amount);
    }

    /**
     * @notice Returns the balance of a given user
     */
    function balanceOf(address operator) external view returns (uint256) {
        return state.balanceOf(operator);
    }

    /**
     * @notice Withdraw deposit tokens
     */
    function withdraw(uint256 amount) external returns (uint256) {
        return state.getUpdated().withdrawFrom(msg.sender, amount);
    }

    /**
     * @notice Claim all outstanding reward tokens
     */
    function claim() external returns (uint256) {
        return state.getUpdated().claimFrom(msg.sender);
    }

    /**
     * @notice Returns the amount of reward tokens that will be transferred on
     *          a call to `.claim`
     */
    function previewClaim() external view returns (uint256) {
        return state.previewClaim(msg.sender);
    }

    function setRewardsPerTokenPerSecond(uint256 newRewardsPerTokenPerSecond) external onlyAdmin {
        return state.getUpdated().setRewardsPerTokenPerSecondFrom(msg.sender, newRewardsPerTokenPerSecond);
    }

    modifier onlyAdmin() {
        // TOOD:
        _;
    }
}

struct State {
    IERC20 __depositToken;
    IERC20 __rewardToken;
    uint256 __updatedAt;
    uint256 __rewardsPerTokenPerSecond;
    uint256 __rewardPerTokenAcc;
    uint256 __totalDeposits;
    mapping(address => StaleAccount) __accounts;
}

library StateLib {
    function depositFrom(State storage s, address from, uint256 amount) internal returns (uint256) {
        Account storage a = s.getUpdatedAccount(from);
        uint256 newBalance = a.deposit(amount);
        s.__totalDeposits += amount;

        s.transferDepositFrom(from, amount);

        emit Deposit(from, amount);

        return newBalance;
    }

    function withdrawFrom(State storage s, address from, uint256 amount) internal returns (uint256) {
        Account storage a = s.getUpdatedAccount(from);
        uint256 newBalance = a.withdraw(amount);
        s.__totalDeposits -= amount;

        emit Withdrawal(from, newBalance);
        return newBalance;
    }

    function balanceOf(State storage s, address operator) internal view returns (uint256) {
        return s.__accounts[operator].balance();
    }

    function claimFrom(State storage s, address from) internal returns (uint256) {
        Account storage a = s.getUpdatedAccount(from);
        uint256 amountClaimed = a.claim();
        emit Claim(from, amountClaimed);
        s.transferRewardsTo(from, amountClaimed);

        return amountClaimed;
    }

    function previewClaimFrom(State storage s, address from) internal view returns (uint256) {
        return s.__accounts[from].previewClaim(s);
    }

    function transferDepositTo(State storage s, address to, uint256 amount) internal {
        return s.__depositToken.safeTransfer(to, amount);
    }

    function transferDepositFrom(State storage s, address from, uint256 amount) internal {
        return s.__depositToken.safeTransferFrom(from, address(this), amount);
    }

    function transferRewardsTo(State storage s, address to, uint256 amount) internal {
        return s.__rewardToken.safeTransfer(to, amount);
    }

    function setRewardsPerTokenPerSecondFrom(State storage s, address from, uint256 newRewardsPerTokenPerSecond)
        internal
    {
        uint256 oldRewardsPerTokenPerSecond = s.__rewardsPerTokenPerSecond;
        s.__rewardsPerTokenPerSecond = newRewardsPerTokenPerSecond;
        emit RewardsPerTokenPerSecondUpdated(from, s.__rewardsPerTokenPerSecond, oldRewardsPerTokenPerSecond);
    }

    function checkpoint(State storage s) internal returns (State storage) {
        uint256 secondsSinceLastCheckpoint = block.timestamp - s.__updatedAt;

        if (s.__totalDeposits > 0) {
            s.__rewardPerTokenAcc +=
                (s.__rewardsPerTokenPerSecond * secondsSinceLastCheckpoint * 1e18) / s.__totalDeposits;
        }
        s.__updatedAt = block.timestamp;

        return s;
    }

    function getUpdatedAccount(State storage s, address owner) internal returns (Account storage) {
        return s.__accounts[owner].getUpdated(s);
    }

    event Deposit(address indexed operator, uint256 amount);
    event Withdrawal(address indexed operator, uint256 amount);
    event Claim(address indexed operator, uint256 amount);
    event RewardsPerTokenPerSecondUpdated(
        address indexed operator, uint256 newRewardsPerTokenPerSecond, uint256 oldRewardsPerTokenPerSecond
    );
}

struct StaleState {
    State __inner;
}

library StaleStateLib {
    function init(StaleState storage s, IERC20 depositToken, IERC20 rewardToken, uint256 rewardsPerTokenPerSecond)
        internal
    {
        s.__inner.__depositToken = depositToken;
        s.__inner.__rewardToken = rewardToken;
        s.__inner.__rewardsPerTokenPerSecond = rewardsPerTokenPerSecond;
    }

    function previewClaim(StaleState storage s, address operator) internal view returns (uint256) {
        return s.__inner.previewClaimFrom(operator);
    }

    function balanceOf(StaleState storage s, address operator) internal view returns (uint256) {
        return s.__inner.balanceOf(operator);
    }

    function getUpdated(StaleState storage s) internal returns (State storage) {
        return s.__inner.checkpoint();
    }
}

struct Account {
    // doesnt need to be checkpointed
    uint256 __balance;
    // need to be checkpointed
    uint256 __rewardsClaimable;
    uint256 __rewardsPerTokenAcc;
}

library AccountLib {
    function claim(Account storage a) internal returns (uint256) {
        uint256 claimable = a.__rewardsClaimable;
        a.__rewardsClaimable = 0;

        return claimable;
    }

    function balance(Account storage a) internal view returns (uint256) {
        return a.__balance;
    }

    function previewClaim(Account storage a, State storage s) internal view returns (uint256) {
        uint256 rewardsPerTokenSinceLastUpdate = s.__rewardPerTokenAcc - a.__rewardsPerTokenAcc;
        uint256 rewardsSinceLastUpdated = (rewardsPerTokenSinceLastUpdate * a.__balance) / 1e18;
        return a.__rewardsClaimable + rewardsSinceLastUpdated;
    }

    function withdraw(Account storage a, uint256 amount) internal returns (uint256) {
        if (a.__balance < amount) {
            revert InsufficientBalance();
        }

        a.__balance -= amount;

        return a.__balance;
    }

    function deposit(Account storage a, uint256 amount) internal returns (uint256) {
        a.__balance += amount;
        return a.__balance;
    }

    error InsufficientBalance();
}

struct StaleAccount {
    Account __inner;
}

library StaleAccountLib {
    function previewClaim(StaleAccount storage a, State storage s) internal view returns (uint256) {
        return a.__inner.previewClaim(s);
    }

    function balance(StaleAccount storage a) internal view returns (uint256) {
        return a.__inner.balance();
    }

    function getUpdated(StaleAccount storage a, State storage s) internal returns (Account storage) {
        Account storage inner = a.__inner;

        inner.__rewardsClaimable = inner.previewClaim(s);
        inner.__rewardsPerTokenAcc = s.__rewardPerTokenAcc;

        return inner;
    }
}
