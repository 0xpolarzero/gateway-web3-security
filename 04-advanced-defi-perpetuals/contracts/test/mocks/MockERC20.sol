// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "solady/tokens/ERC20.sol";

contract MockERC20 is ERC20 {
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    constructor(string memory _tokenNname, string memory _tokenSymbol, uint8 _tokenDecimals) {
        _name = _tokenNname;
        _symbol = _tokenSymbol;
        _decimals = _tokenDecimals;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }

    /* -------------------------------------------------------------------------- */
    /*                              METADATA (Solady)                             */
    /* -------------------------------------------------------------------------- */

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}
