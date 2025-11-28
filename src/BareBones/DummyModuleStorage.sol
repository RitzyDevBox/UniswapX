// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library DummyModuleStorage {
    // Unique, collision-free storage slot
    bytes32 internal constant NAMESPACE =
        keccak256("module.storage.dummy");

    struct Layout {
        uint256 storedValue;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = NAMESPACE;
        assembly {
            l.slot := slot
        }
    }
}
