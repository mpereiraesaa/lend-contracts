// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./LendingPool.sol";
import "./LendingPoolFactory.sol";

contract LendingPoolManager is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    uint256 public constant ORACLE_PRECISION_MULTIPLIER = 10000000000;

    LendingPoolFactory public factory;
    mapping(address => LendingPool[]) public accountToLendingPool;
    mapping(address => address) public tokenToPriceFeed;
    mapping(address => mapping(address => uint256)) public accountLendingPoolIndex; // 1-based index to distinguish from default 0

    // Liquidation parameters
    uint256 public closeFactor;
    uint256 public liquidationIncentive;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        LendingPoolFactory _factory,
        uint256 _closeFactor,
        uint256 _liquidationIncentive
    ) public initializer {
        __Ownable_init();
        factory = _factory;
        closeFactor = _closeFactor;
        liquidationIncentive = _liquidationIncentive;
    }

    modifier onlyRegisteredLendingPool(address underlyingToken) {
        LendingPool pool = factory.tokenToLendingPool[underlyingToken];

        if (address(pool) != msg.sender) {
            revert InvalidCaller();
        }
        _;
    }

    /**
     * @notice Sets the close factor
     * @param newCloseFactor The new close factor value, scaled by 1e18
     */
    function setCloseFactor(uint256 newCloseFactor) external onlyOwner {
        require(newCloseFactor <= 1e18, "Close factor cannot exceed 100%");
        closeFactor = newCloseFactor;
    }

    /**
     * @notice Sets the liquidation incentive
     * @param newLiquidationIncentive The new liquidation incentive, scaled by 1e18
     */
    function setLiquidationIncentive(uint256 newLiquidationIncentive) external onlyOwner {
        require(newLiquidationIncentive >= 1e18, "Liquidation incentive cannot be less than 100%");
        liquidationIncentive = newLiquidationIncentive;
    }

    /**
     * @notice Adds a LendingPool to the user's list of pools if it hasn't been added yet
     * @param user The address of the user
     * @param underlyingToken The address of the LendingPool underlying token
     */
    function addLendingPool(address user, address underlyingToken)
        external
        onlyRegisteredLendingPool(underlyingToken)
    {
        LendingPool pool = factory.tokenToLendingPool[underlyingToken];

        if (accountLendingPoolIndex[user][address(pool)] == 0) {
            accountToLendingPool[user].push(pool);
            accountLendingPoolIndex[user][address(pool)] = accountToLendingPool[user].length; // Store index as 1-based to distinguish from default 0
        }
    }

    /**
     * @notice Sets the Chainlink price feed for a given token
     * @param token The address of the token
     * @param priceFeed The address of the Chainlink price feed
     */
    function setPriceFeed(address token, address priceFeed) external onlyOwner {
        tokenToPriceFeed[token] = priceFeed;
    }

    /**
     * @notice Calculates the total liquidity a user has across all lending pools in USD
     * @param user The address of the user
     * @return totalLiquidity The total liquidity that the user has across all pools in USD
     */
    function calculateTotalLiquidity(address user) external view returns (uint256 totalLiquidity) {
        LendingPool[] memory userPools = accountToLendingPool[user];
        for (uint256 i = 0; i < userPools.length; i++) {
            LendingPool pool = userPools[i];
            uint256 underlyingBalance = pool.balanceOfUnderlying(user);
            uint256 price = getPriceFromOracle(pool.underlyingToken);
            totalLiquidity += (underlyingBalance * price) / 1e18;
        }
    }

    /**
     * @notice Calculates the effective collateral value a user has across all lending pools in USD, applying collateral factors
     * @param user The address of the user
     * @return totalCollateralValueUSD The effective collateral value that the user has across all pools in USD
     */
    function calculateEffectiveCollateralValue(address user) external view returns (uint256 totalCollateralValueUSD) {
        LendingPool[] memory userPools = accountToLendingPool[user];
        for (uint256 i = 0; i < userPools.length; i++) {
            LendingPool pool = userPools[i];
            uint256 underlyingBalance = pool.balanceOfUnderlying(user);
            uint256 price = getPriceFromOracle(pool.underlyingToken);
            uint256 collateralFactor = pool.collateralFactor;
            totalCollateralValueUSD += (underlyingBalance * price * collateralFactor) / 1e36;
        }
    }

    /**
     * @notice Retrieves the price of a token from the Chainlink oracle
     * @param token The address of the token
     * @return price The latest price of the token, scaled by 1e18
     */
    function getPriceFromOracle(address token) internal view returns (uint256 price) {
        address priceFeedAddress = tokenToPriceFeed[token];

        if (priceFeedAddress == address(0)) {
            revert PriceFeedMissing(token);
        }

        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddress);
        (, int256 priceInt,,,) = priceFeed.latestRoundData();

        if (priceInt <= 0) {
            revert InvalidPriceFromOracle(priceInt);
        }

        price = uint256(priceInt) * ORACLE_PRECISION_MULTIPLIER;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
