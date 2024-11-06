// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../helpers/Errors.sol";
import "../strategies/SimpleRateStrategy.sol";
import "./LendingPool.sol";

contract LendingPoolFactory {
    address[] public pools;
    mapping(IERC20 => address) public tokenToLendingPool;

    event LendingPoolCreated(address indexed poolAddress);

    function createLendingPool(address implementation, IERC20 token, SimpleRateStrategy rateStrategy) external {
        if (tokenToLendingPool[token] == address(0)) {
            revert LendingPoolAlreadyExistsForThisToken(token);
        }
        bytes memory data = abi.encodeWithSelector(LendingPool.initialize.selector, token, rateStrategy);
        address proxy = address(new ERC1967Proxy(implementation, data));
        pools.push(proxy);
        tokenToLendingPool[token] = proxy;
        emit LendingPoolCreated(proxy);
    }

    function upgradeLendingPool(address pool, address newImplementation) external {
        LendingPool(pool).upgradeTo(newImplementation);
    }

    function upgradeLendingPoolAndCall(address pool, address newImplementation, bytes memory data) external payable {
        LendingPool(pool).upgradeToAndCall(newImplementation, data);
    }
}
