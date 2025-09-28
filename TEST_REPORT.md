# TrueMatchProtocol — Test Report

Date: 2025-09-28 13:47:38 +05:30

Repository: `AamirAlam/true-match-contracts`
Contract under test: `src/TrueMatchProtocol.sol`
Test file: `test/TrueMatchProtocol.t.sol`
Framework: Foundry (`forge test`)

## Summary
All tests passed successfully. The test suite validates staking/unstaking flows, product purchases and spending, reporting and slashing mechanics, reputation updates and SBT tiering, referral rewards, and pause controls.

- Total suites: 2
- Total tests: 10
- Passed: 10
- Failed: 0
- Skipped: 0

## Execution
Command:

```
forge test -vvv
```

Results:

```
Ran 6 tests for test/TrueMatchProtocol.t.sol:TrueMatchProtocolTest
[PASS] test_buy_and_spend_products() (gas: 165337)
[PASS] test_pause_blocks_state_changing_functions() (gas: 73169)
[PASS] test_referral_flow() (gas: 95703)
[PASS] test_reports_trigger_slash_and_reputation_drop() (gas: 237533)
[PASS] test_stake_and_unstake_flow() (gas: 108823)
[PASS] test_updateReputation_onlyOwner() (gas: 82658)
Suite result: ok. 6 passed; 0 failed; 0 skipped; finished in ~4.7ms

Ran 4 tests for test/Counter.t.sol:CounterTest
[PASS] testFuzz_SetNumber(uint256) (runs: 256, μ: 28181, ~: 28415)
[PASS] test_Decrement() (gas: 19284)
[PASS] test_Increment() (gas: 28479)
[PASS] test_LargeIncrement() (gas: 32452)
Suite result: ok. 4 passed; 0 failed; 0 skipped; finished in ~7.0ms

Ran 2 test suites: 10 tests passed, 0 failed, 0 skipped (10 total tests)
```

## Test Coverage (Behavioral)
- Staking/Unstaking
  - `stake(uint256)`, `requestUnstake()`, `unstake(uint256)` including lock cooldown and `userView()` state assertions.
- Product Purchases & Spending
  - `buySwipeCredits(uint256)`, `buySuperlikes(uint256)`, `buyBoosts(uint256)` accumulate balances and transfer cost to `treasury`.
  - `spendSwipe()`, `spendSuperlike()`, `spendBoost()` decrement balances and revert on insufficiency.
- Reporting & Slashing
  - `reportUser(address)` increments reports; on threshold, slashes stake (bounded by balance), resets reports, credits `treasury`, and applies reputation decrease.
- Reputation & SBT
  - `updateReputation(address,int256)` owner-only; positive and negative deltas; tier thresholds via `ReputationSBT.mintOrUpdate()`.
- Referral System
  - `linkReferral(address)` one-time link; `claimReferralReward()` transfers rewards from `treasury` to both referee and referrer; prevents double-claim.
- Pause Control
  - `setPaused(bool)` blocks state-changing functions while paused.

## Gas (Selected)
- `test_reports_trigger_slash_and_reputation_drop`: 237,533
- `test_buy_and_spend_products`: 165,337
- `test_stake_and_unstake_flow`: 108,823
- `test_updateReputation_onlyOwner`: 82,658
- `test_referral_flow`: 95,703
- `test_pause_blocks_state_changing_functions`: 73,169

## Notes & Next Steps
- Consider adding negative tests for revert paths: zero-amount stake/buys, invalid report target/self-report, duplicate referrals, claim without referral, and spending without balance for all products.
- Add tests for admin parameter updates: `setParams(...)`, `setTreasury(address)`, and `hasPremium(address)` across `minStake` boundaries.
- Optional fuzzing around report thresholds and dynamic pricing.
