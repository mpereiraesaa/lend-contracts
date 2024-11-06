// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ILendingPool {
    /**
     * @notice Borrow balance information
     * @member totalDue (with accrued interest), after applying the most recent balance-changing action
     * @member interestIndex Global borrowIndex as of the most recent balance-changing action
     */
    struct BorrowSnapshot {
        uint256 totalDue;
        uint256 interestIndex;
    }

    function deposit(uint256 amount) external;
    function withdraw(address account, uint256 amount) external;
    function borrow(uint256 borrowAmount) external;
    function repay(uint256 repayAmount) external;
    function getBorrowBalance(address account) external view returns (uint256);
    function getAccountBalance(address account) external view returns (uint256);
}
