// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract SimpleRateStrategy {
    uint256 public baseRate; // Base rate, scaled by 1e18 for precision
    uint256 public multiplier; // Rate multiplier, scaled by 1e18 for precision
    uint256 public constant borrowRateMax = 0.000005e18;

    event NewInterestParams(uint256 baseRate, uint256 multiplier);

    constructor(uint256 _baseRate, uint256 _multiplier) {
        baseRate = _baseRate; // Base rate (e.g., 2% as 0.02 * 1e18)
        multiplier = _multiplier; // Rate multiplier (e.g., 15% as 0.15 * 1e18)

        emit NewInterestParams(baseRate, multiplier);
    }

    /**
     * @notice Calculates the market utilization rate: `borrows / (cash + borrows)`
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @return The utilization rate as a mantissa between [0, 1e18]
     */
    function utilizationRate(uint256 cash, uint256 borrows) public pure returns (uint256) {
        if (borrows == 0) {
            return 0;
        }
        return (borrows * 1e18) / (cash + borrows);
    }

    /**
     * @notice Calculates the borrow interest rate per block
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @return The borrow interest rate per block as a mantissa (scaled by 1e18)
     */
    function getBorrowRate(uint256 cash, uint256 borrows) public view returns (uint256) {
        uint256 util = utilizationRate(cash, borrows);
        return baseRate + (util * multiplier) / 1e18;
    }

    /**
     * @notice Calculates the supply interest rate per block
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserveFactorMantissa The current reserve factor for the market
     * @return The supply interest rate per block as a mantissa (scaled by 1e18)
     */
    function getSupplyRate(uint256 cash, uint256 borrows, uint256 reserveFactorMantissa)
        public
        view
        returns (uint256)
    {
        uint256 borrowRate = getBorrowRate(cash, borrows);
        uint256 oneMinusReserveFactor = 1e18 - reserveFactorMantissa;
        return (utilizationRate(cash, borrows) * borrowRate * oneMinusReserveFactor) / 1e36;
    }

    /**
     * @notice Calculates the exchange rate
     * @param cash The total amount of cash in the market
     * @param totalBorrows The total amount of borrows in the market
     * @param totalSupply The total supply of tokens in the market
     * @return The exchange rate as a mantissa (scaled by 1e18)
     */
    function getExchangeRate(uint256 cash, uint256 totalBorrows, uint256 totalSupply)
        public
        view
        returns (uint256)
    {
        if (totalSupply == 0) {
            return baseRate;
        } else {
            // exchangeRate = (cash + totalBorrows) / totalSupply
            uint256 cashPlusBorrowsMinusReserves = cash + totalBorrows;
            return (cashPlusBorrowsMinusReserves * 1e18) / totalSupply;
        }
    }
}
