// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./IValidationModule.sol";

/**
 * -------------------------------------------------------------------------
 *  MODULE REGISTRY + UNIFIED PROPOSAL SYSTEM + FALLBACK ROUTER (EXTERNAL AUTH)
 *
 *  This contract:
 *    - Uses an external validator for ALL authorization checks
 *    - Supports ANY privileged state change via a generic timelocked proposal
 *    - Routes all unknown selectors through fallback → delegatecall(module)
 *    - Maintains registry: selector → module + signature
 *
 *  Extending privileged actions = add new actionType + implement handler.
 * -------------------------------------------------------------------------
 */
contract ModuleRegistryRouter {

    // ---------------------------------------------------------------------
    // ERRORS
    // ---------------------------------------------------------------------
    error NotAuthorized();
    error ZeroAddress();
    error InvalidModule();
    error NoModule(bytes4 selector);
    error TooEarly(uint256 availableAt);
    error NoProposal(bytes32 proposalId);
    error UnknownProposalType(uint8 actionType);
    error CallFailed(bytes data);
    error InvalidSelectorLength(uint256 length);

    // ---------------------------------------------------------------------
    // EVENTS
    // ---------------------------------------------------------------------
    event ProposalCreated(bytes32 indexed proposalId, uint8 actionType, bytes data, uint256 eta);
    event ProposalExecuted(bytes32 indexed proposalId);

    event ValidationModuleChanged(address oldModule, address newModule);
    event PolicyDelayChanged(uint256 newDelay);
    event ModuleActivated(bytes4 indexed selector, address module);

    // ---------------------------------------------------------------------
    // STORAGE (PUBLIC API)
    // ---------------------------------------------------------------------

    IValidationModule public validator;
    uint256 public policyDelay;

    // Selector → module address
    mapping(bytes4 => address) public moduleForSelector;

    // Selector → human-readable signature
    mapping(bytes4 => string) public signatureForSelector;

    // All selectors (for introspection)
    bytes4[] public allSelectors;

    // ---------------------------------------------------------------------
    // STORAGE (UNIFIED PROPOSALS)
    // ---------------------------------------------------------------------
    struct Proposal {
        uint8 actionType;     // what operation to execute
        uint256 eta;          // when execution becomes allowed
        bytes data;           // encoded payload
    }

    mapping(bytes32 => Proposal) public proposals;

    // ---------------------------------------------------------------------
    // ACTION TYPES (extend freely)
    // ---------------------------------------------------------------------
    uint8 constant ACTION_INSTALL_MODULE      = 1;
    uint8 constant ACTION_UPDATE_VALIDATOR    = 2;
    uint8 constant ACTION_UPDATE_POLICY_DELAY = 3;

    // ---------------------------------------------------------------------
    // CONSTRUCTOR
    // ---------------------------------------------------------------------
    constructor(uint256 _policyDelay, address _validator) {
        if (_validator == address(0)) revert ZeroAddress();
        validator = IValidationModule(_validator);
        policyDelay = _policyDelay;
    }

    // ---------------------------------------------------------------------
    // PROPOSAL CREATION (GENERIC)
    // ---------------------------------------------------------------------
    function propose(uint8 actionType, bytes calldata data) external payable {
        // External authorization (validator controls ALL privileged logic)
        if (!validator.validate(msg.sender, this.propose.selector, address(this), data, msg.value))
            revert NotAuthorized();

        bytes32 proposalId = keccak256(abi.encode(actionType, data, block.number));

        uint256 eta = block.timestamp + policyDelay;
        proposals[proposalId] = Proposal({
            actionType: actionType,
            eta: eta,
            data: data
        });

        emit ProposalCreated(proposalId, actionType, data, eta);
    }

    // ---------------------------------------------------------------------
    // PROPOSAL EXECUTION (GENERIC)
    // ---------------------------------------------------------------------
    function execute(bytes32 proposalId) external payable {
        Proposal memory p = proposals[proposalId];
        if (p.eta == 0) revert NoProposal(proposalId);
        if (block.timestamp < p.eta) revert TooEarly(p.eta);

        // Must be authorized by validator
        if (!validator.validate(msg.sender, this.execute.selector, address(this), p.data, msg.value))
            revert NotAuthorized();

        // Dispatch to appropriate handler
        _executeProposal(p);

        delete proposals[proposalId];
        emit ProposalExecuted(proposalId);
    }

    // ---------------------------------------------------------------------
    // INTERNAL: PROPOSAL DISPATCH
    // ---------------------------------------------------------------------
    function _executeProposal(Proposal memory p) internal {
        if (p.actionType == ACTION_INSTALL_MODULE) {
            _installModule(p.data);
        }
        else if (p.actionType == ACTION_UPDATE_VALIDATOR) {
            _updateValidator(p.data);
        }
        else if (p.actionType == ACTION_UPDATE_POLICY_DELAY) {
            _updatePolicyDelay(p.data);
        }
        else {
            revert UnknownProposalType(p.actionType);
        }
    }

    // ---------------------------------------------------------------------
    // ACTION HANDLERS
    // ---------------------------------------------------------------------

    // ACTION 1: Install / update a module implementation
    // data = abi.encode(bytes4 selector, address module, string signature)
    function _installModule(bytes memory data) internal {
        (bytes4 selector, address module, string memory signature) =
            abi.decode(data, (bytes4, address, string));

        if (module == address(0)) revert InvalidModule();

        moduleForSelector[selector] = module;
        signatureForSelector[selector] = signature;

        allSelectors.push(selector);

        emit ModuleActivated(selector, module);
    }

    // ACTION 2: Update the validation module
    // data = abi.encode(address newValidator)
    function _updateValidator(bytes memory data) internal {
        address newVal = abi.decode(data, (address));
        if (newVal == address(0)) revert ZeroAddress();

        address oldVal = address(validator);
        validator = IValidationModule(newVal);

        emit ValidationModuleChanged(oldVal, newVal);
    }

    // ACTION 3: Update policyDelay
    // data = abi.encode(uint256 newDelay)
    function _updatePolicyDelay(bytes memory data) internal {
        uint256 newDelay = abi.decode(data, (uint256));
        policyDelay = newDelay;

        emit PolicyDelayChanged(newDelay);
    }

    // ---------------------------------------------------------------------
    // INTROSPECTION HELPERS
    // ---------------------------------------------------------------------
    function listAllSelectors() external view returns (bytes4[] memory) {
        return allSelectors;
    }

    function getSignature(bytes4 selector) external view returns (string memory) {
        return signatureForSelector[selector];
    }

    function getModule(bytes4 selector) external view returns (address) {
        return moduleForSelector[selector];
    }

        // ---------------------------------------------------------------------
        // FALLBACK ROUTING (DELEGATECALL)
        // ---------------------------------------------------------------------
    fallback() external payable {
        // ------------------------------------------------------------
        // CASE 1: Pure ETH transfer
        // ------------------------------------------------------------
        // This allows:  address(router).call{value: x}("");
        // Most smart accounts MUST accept ETH without calldata.
        uint256 msgDataLength = msg.data.length;
        if (msgDataLength == 0) {
            return;
        }

        // ------------------------------------------------------------
        // CASE 2: Malformed calldata (<4 bytes)
        // ------------------------------------------------------------
        // No valid selector exists, so routing would be unsafe.
        if (msgDataLength < 4) {
            revert InvalidSelectorLength(msgDataLength);
        }

        // ------------------------------------------------------------
        // CASE 3: Valid function call
        // ------------------------------------------------------------
        bytes4 selector = bytes4(msg.data[0:4]);

        address mod = moduleForSelector[selector];
        if (mod == address(0)) revert NoModule(selector);

        // External validation module checks authorization for ALL calls.
        if (!validator.validate(msg.sender, selector, mod, msg.data, msg.value)) {
            revert NotAuthorized();
        }

        // ------------------------------------------------------------
        // Delegatecall into module
        // ------------------------------------------------------------
        (bool ok, bytes memory result) = mod.delegatecall(msg.data);
        if (!ok) revert CallFailed(result);

        assembly {
            return(add(result, 32), mload(result))
        }
    }


    receive() external payable {}
}
