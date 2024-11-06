// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PToken - A simple cToken-like implementation for representing lending pool shares
 * @dev Inherits ERC20 for standard token behavior and Ownable for restricted minting and burning
 */
contract PToken is ERC20, Ownable {
    /**
     * @dev Constructor to set the name and symbol of the token
     */
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) Ownable(msg.sender) {}

    /**
     * @notice Mints `amount` of PTokens to the specified address
     * @dev Only callable by the owner (i.e., LendingPool contract)
     * @param account The address to receive the minted tokens
     * @param amount The amount of tokens to mint
     */
    function mint(address account, uint256 amount) external onlyOwner {
        _mint(account, amount);
    }

    /**
     * @notice Burns `amount` of PTokens from the specified address
     * @dev Only callable by the owner (i.e., LendingPool contract)
     * @param account The address from which the tokens will be burned
     * @param amount The amount of tokens to burn
     */
    function burn(address account, uint256 amount) external onlyOwner {
        _burn(account, amount);
    }
}
