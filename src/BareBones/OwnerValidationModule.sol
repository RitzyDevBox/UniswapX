// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./IValidationModule.sol";

contract OwnerValidationModule is IValidationModule {
    address public owner;

    error NotAuthorized();

    constructor(address _owner) {
        owner = _owner;
    }

    function validate(
        address caller,
        bytes4,
        address,
        bytes calldata,
        uint256
    ) external view override returns (bool) {
        return caller == owner;
    }
}
