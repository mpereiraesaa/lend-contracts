// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../helpers/Errors.sol";
import "../interfaces/ILendingPool.sol";
import "../strategies/SimpleRateStrategy.sol";
import "./LendingPoolManager.sol";
import "./PToken.sol";

contract LendingPool is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ILendingPool
{
    using SafeERC20 for IERC20;

    IERC20 public underlyingToken;
    PToken public pToken;
    SimpleRateStrategy internal _rateStrategy;
    LendingPoolManager internal _manager;
    uint256 public collateralFactor;
    uint256 public totalBorrows;
    uint256 public accrualBlockNumber;
    uint256 public borrowIndex;

    mapping(address => BorrowSnapshot) public borrows;

    // Events
    event Deposit(address indexed user, uint256 amount, uint256 pTokenAmount);
    event Withdraw(address indexed user, uint256 amount, uint256 pTokenAmount);
    event Borrow(address indexed user, uint256 amount);
    event Repay(address indexed user, uint256 amount);
    event SeizeCollateral(
        address indexed liquidator,
        address indexed borrower,
        uint256 seizeAmount
    );

    modifier onlyManager() {
        if (msg.sender != address(_manager)) {
            revert InvalidCaller();
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        IERC20 token,
        SimpleRateStrategy rateStrategy,
        LendingPoolManager manager,
        uint256 _collateralFactor,
        string calldata pTokenName,
        string calldata pTokenSymbol
    ) public initializer {
        __Ownable_init();
        underlyingToken = token;
        pToken = new PToken(pTokenName, pTokenSymbol);
        _rateStrategy = rateStrategy;
        _manager = manager;
        collateralFactor = _collateralFactor;
        borrowIndex = 1e18;
        accrualBlockNumber = block.number;
    }

    function deposit(uint256 amount) external {
        if (amount <= 0) {
            revert AmountMustBeGreaterThanZero();
        }
        underlyingToken.safeTransferFrom(msg.sender, address(this), amount);
        pToken.mint(msg.sender, amount);
        _manager.addLendingPool(msg.sender, underlyingToken);
    }

    function withdraw(address account, uint256 amount) external {
        uint256 underlyingBalance = getAccountBalance(account);

        if (underlyingBalance < amount) {
            revert InsufficientBalance({
                available: underlyingBalance,
                requested: amount
            });
        }

        uint256 pTokensToBurn = (amount * 1e18) / getExchangeRate();
        pToken.burn(account, pTokensToBurn);
        underlyingToken.safeTransfer(account, amount);
    }

    /**
     * @notice Allows a user to borrow an amount if it doesn't exceed their available liquidity
     * @param borrowAmount The amount to borrow in the underlying token
     */
    function borrow(uint256 borrowAmount) external {
        _accrueInterest();

        (uint256 liquidity, uint256 shortfall) = _manager
            .getHypotheticalAccountLiquidity(msg.sender, this, 0, borrowAmount);

        if (shortfall > 0) {
            revert BorrowAmountExceedsAvailable({
                available: liquidity,
                requested: borrowAmount
            });
        }

        BorrowSnapshot storage borrowSnapshot = borrows[msg.sender];
        uint256 priorBorrowBalance = getBorrowBalance(msg.sender);
        uint256 newBorrowBalance = priorBorrowBalance + borrowAmount;

        borrowSnapshot.totalDue = newBorrowBalance;
        borrowSnapshot.interestIndex = borrowIndex;

        totalBorrows += borrowAmount;
        underlyingToken.safeTransfer(msg.sender, borrowAmount);
    }

    function repay(uint256 repayAmount) external {
        BorrowSnapshot storage borrowSnapshot = borrows[msg.sender];

        if (repayAmount <= 0) {
            revert AmountMustBeGreaterThanZero();
        }
        if (borrowSnapshot.totalDue == 0) {
            revert NoOutstandingBorrow();
        }

        _accrueInterest();

        uint256 borrowBalance = getBorrowBalance(msg.sender);
        uint256 amountToRepay = repayAmount > borrowBalance
            ? borrowBalance
            : repayAmount;

        // Transfer the tokens from the borrower to the pool
        underlyingToken.safeTransferFrom(
            msg.sender,
            address(this),
            amountToRepay
        );

        // Update the borrower's snapshot
        borrowSnapshot.totalDue = borrowBalance - amountToRepay;
        borrowSnapshot.interestIndex = borrowIndex;

        // Update total borrows
        totalBorrows -= amountToRepay;
    }

    /**
     * @notice Seizes collateral from a borrower during liquidation
     * @dev Only callable by the LendingPoolManager
     * @param borrower The address of the borrower
     * @param liquidator The address of the liquidator
     * @param seizeAmount The amount of collateral to seize (in underlying tokens)
     */
    function seizeCollateral(
        address borrower,
        address liquidator,
        uint256 seizeAmount
    ) external onlyManager {
        _accrueInterest();

        uint256 exchangeRate = getExchangeRate();
        uint256 seizeTokens = (seizeAmount * 1e18) / exchangeRate;

        // Transfer pTokens from borrower to liquidator
        pToken.seize(borrower, liquidator, seizeTokens);

        emit SeizeCollateral(liquidator, borrower, seizeAmount);
    }

    function getBorrowBalance(address account) public view returns (uint256) {
        BorrowSnapshot storage borrowSnapshot = borrows[account];

        if (borrowSnapshot.totalDue == 0) return 0;

        uint256 totalDueTimesIndex = borrowSnapshot.totalDue * borrowIndex;
        uint256 borrowbalance = totalDueTimesIndex /
            borrowSnapshot.interestIndex;
        return borrowbalance;
    }

    /**
     * @notice Returns the balance of underlying for the specified address
     * @param account The address to query the balance of
     * @return The balance in underlying assets, scaled by 1e18
     */
    function getAccountBalance(address account) public view returns (uint256) {
        uint256 pTokenBalance = pToken.balanceOf(account);
        return (pTokenBalance * getExchangeRate()) / 1e18;
    }

    function getCash() public view returns (uint256) {
        return underlyingToken.balanceOf(address(this));
    }

    function getExchangeRate() public view returns (uint256) {
        return
            _rateStrategy.getExchangeRate(
                getCash(),
                totalBorrows,
                pToken.totalSupply()
            );
    }

    function _accrueInterest() internal {
        uint currentBlockNumber = block.number;
        uint256 blockDelta = currentBlockNumber - accrualBlockNumber;

        if (blockDelta == 0) return;

        uint256 cash = getCash();
        uint256 borrowRate = _rateStrategy.getBorrowRate(cash, totalBorrows);

        if (borrowRate >= _rateStrategy.borrowRateMax)
            revert BorrowRateExceedsMax(borrowRate);

        uint256 interestFactor = borrowRate * blockDelta;
        uint256 interestAccumulated = (interestFactor * totalBorrows) / 1e18;

        borrowIndex = borrowIndex + (interestFactor * borrowIndex) / 1e18;
        totalBorrows += interestAccumulated;
        accrualBlockNumber = currentBlockNumber;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
