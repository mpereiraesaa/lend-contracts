// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

error InsufficientBalance(uint256 available, uint256 requested);
error LendingPoolAlreadyExistsForThisToken(address token);
error AmountMustBeGreaterThanZero();
error InvalidCaller();
error PriceFeedMissing(address token);
error InvalidPriceFromOracle(int256 price);
error BorrowAmountExceedsAvailable(uint256 available, uint256 requested);
error InvalidOperation();
error BorrowRateExceedsMax(uint256 rate);
error NoOutstandingBorrow();
