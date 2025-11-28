// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract EthEchoModule {
    // Returns back whatever ETH value was sent
    function echo() external payable returns (uint256) {
        return msg.value;
    }
}
