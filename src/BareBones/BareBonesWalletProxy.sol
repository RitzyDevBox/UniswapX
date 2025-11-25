// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * -------------------------------------------------------------------------
 *  ModularSmartAccount6900 — Refactored
 *  - Uses custom errors (no revert strings)
 *  - Groups functions logically
 *  - ERC-6900 style module routing
 *  - Timelocked governance
 *  - Selector → module registry
 *  - Endpoint introspection
 *  - EIP-1271 signature validation
 *  - Multicall
 * -------------------------------------------------------------------------
 */
contract ModularSmartAccount6900 {

    // ---------------------------------------------------------------------
    // ERRORS
    // ---------------------------------------------------------------------
    error NotAdmin();
    error ZeroAddress();
    error InvalidModule();
    error NoModule(bytes4 selector);
    error TooEarly(uint256 availableAt);
    error NoProposal(bytes4 selector);
    error AuthFailed();
    error BadSignature();
    error CallFailed(bytes data);

    // ---------------------------------------------------------------------
    // STORAGE
    // ---------------------------------------------------------------------
    address public admin;
    uint256 public policyDelay;

    mapping(bytes4 => address) public moduleForSelector;
    mapping(bytes4 => string) public signatureForSelector;
    bytes4[] public allRegisteredSelectors;

    mapping(bytes4 => address) public proposedModule;
    mapping(bytes4 => string) public proposedSignature;
    mapping(bytes4 => uint256) public activationTime;

    bytes4 internal constant MAGICVALUE = 0x1626ba7e;

    // ---------------------------------------------------------------------
    // EVENTS
    // ---------------------------------------------------------------------
    event ModuleProposed(bytes4 indexed selector, address module, string signature, uint256 eta);
    event ModuleActivated(bytes4 indexed selector, address module);
    event AdminChanged(address newAdmin);
    event PolicyDelayChanged(uint256 newDelay);

    // ---------------------------------------------------------------------
    // CONSTRUCTOR
    // ---------------------------------------------------------------------
    constructor(uint256 _policyDelay) {
        admin = msg.sender;
        policyDelay = _policyDelay;
    }

    // ---------------------------------------------------------------------
    // ADMIN / GOVERNANCE
    // ---------------------------------------------------------------------
    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    function changeAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert ZeroAddress();
        admin = newAdmin;
        emit AdminChanged(newAdmin);
    }

    function changePolicyDelay(uint256 newDelay) external onlyAdmin {
        policyDelay = newDelay;
        emit PolicyDelayChanged(newDelay);
    }

    // ---------------------------------------------------------------------
    // MODULE REGISTRY (ERC-6900 STYLE)
    // ---------------------------------------------------------------------

    /// @notice Propose a module (timelocked)
    function proposeModule(
        bytes4 selector,
        address module,
        string calldata signature
    ) external onlyAdmin {
        if (module == address(0)) revert InvalidModule();

        proposedModule[selector] = module;
        proposedSignature[selector] = signature;
        uint256 eta = block.timestamp + policyDelay;
        activationTime[selector] = eta;

        emit ModuleProposed(selector, module, signature, eta);
    }

    /// @notice Activate module after timelock
    function activateModule(bytes4 selector) external {
        uint256 eta = activationTime[selector];
        if (eta == 0) revert NoProposal(selector);
        if (block.timestamp < eta) revert TooEarly(eta);

        moduleForSelector[selector] = proposedModule[selector];
        signatureForSelector[selector] = proposedSignature[selector];
        allRegisteredSelectors.push(selector);

        emit ModuleActivated(selector, proposedModule[selector]);

        delete proposedModule[selector];
        delete proposedSignature[selector];
        delete activationTime[selector];
    }

    // ---------------------------------------------------------------------
    // ENDPOINT INTROSPECTION
    // ---------------------------------------------------------------------
    function listAllSelectors() external view returns (bytes4[] memory) {
        return allRegisteredSelectors;
    }

    function getSignature(bytes4 selector) external view returns (string memory) {
        return signatureForSelector[selector];
    }

    function getModule(bytes4 selector) external view returns (address) {
        return moduleForSelector[selector];
    }

    // ---------------------------------------------------------------------
    // AUTHORIZATION (OVERRIDABLE)
    // ---------------------------------------------------------------------
    function _authorize(
        address sender,
        bytes4 selector,
        bytes memory,
        uint256
    ) internal view returns (bool) {
        bool isAdminFunction =
            selector == this.proposeModule.selector ||
            selector == this.activateModule.selector ||
            selector == this.changeAdmin.selector ||
            selector == this.changePolicyDelay.selector;

        if (isAdminFunction) {
            return sender == admin;
        }

        return true;
    }

    modifier authorizedCaller(
        bytes4 selector,
        bytes memory data,
        uint256 value
    ) {
        if (!_authorize(msg.sender, selector, data, value)) revert AuthFailed();
        _;
    }


    // ---------------------------------------------------------------------
    // CORE EXECUTION + MULTICALL
    // ---------------------------------------------------------------------
    function multicall(bytes[] calldata calls)
        external
        payable
        returns (bytes[] memory results)
    {
        results = new bytes[](calls.length);

        for (uint256 i; i < calls.length; i++) {
            (address target, uint256 value, bytes memory callData) =
                abi.decode(calls[i], (address, uint256, bytes));

            // Extract selector safely from memory bytes
            bytes4 selector;
            if (callData.length >= 4) {
                assembly {
                    selector := mload(add(callData, 32))
                }
            }

            results[i] = _execute(target, value, selector, callData);
        }
    }


    function _execute(
        address target,
        uint256 value,
        bytes4 selector,
        bytes memory callData
    )
        internal
        authorizedCaller(selector, callData, value)
        returns (bytes memory result)
    {
        (bool ok, bytes memory ret) = target.call{value: value}(callData);
        if (!ok) revert CallFailed(ret);
        return ret;
    }

    // ---------------------------------------------------------------------
    // FALLBACK (DELEGATECALL)
    // ---------------------------------------------------------------------
    fallback() external payable {
        bytes4 selector = msg.data.length >= 4
            ? bytes4(msg.data[0:4])
            : bytes4(0);

        address mod = moduleForSelector[selector];
        if (mod == address(0)) revert NoModule(selector);

        if (!_authorize(msg.sender, selector, msg.data, msg.value))
            revert AuthFailed();

        (bool ok, bytes memory result) = mod.delegatecall(msg.data);
        if (!ok) revert CallFailed(result);

        assembly {
            return(add(result, 32), mload(result))
        }
    }

    receive() external payable {}

    // ---------------------------------------------------------------------
    // EIP-1271 SIGNATURE VALIDATION
    // ---------------------------------------------------------------------
    function isValidSignature(bytes32 hash, bytes calldata sig)
        external
        view
        returns (bytes4)
    {
        if (_isValidAdminSignature(hash, sig)) return MAGICVALUE;
        return 0x00000000;
    }

    function _isValidAdminSignature(bytes32 hash, bytes calldata sig)
        internal
        view
        returns (bool)
    {
        if (sig.length != 65) revert BadSignature();

        (bytes32 r, bytes32 s, uint8 v) = _splitSignature(sig);
        address signer = ecrecover(hash, v, r, s);
        return signer == admin;
    }

    // ---------------------------------------------------------------------
    // UTILITIES
    // ---------------------------------------------------------------------
    function _splitSignature(bytes calldata sig)
        internal
        pure
        returns (bytes32 r, bytes32 s, uint8 v)
    {
        assembly {
            r := calldataload(add(sig.offset, 0))
            s := calldataload(add(sig.offset, 32))
            v := byte(0, calldataload(add(sig.offset, 64)))
        }
    }
}
