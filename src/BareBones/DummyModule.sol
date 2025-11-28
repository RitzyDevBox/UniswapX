// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./DummyModuleStorage.sol";

contract DummyModule {
    function setValue(uint256 x) external {
        DummyModuleStorage.Layout storage s = DummyModuleStorage.layout();
        s.storedValue = x;
    }

    function getValue() external view returns (uint256) {
        return DummyModuleStorage.layout().storedValue;
    }
}
