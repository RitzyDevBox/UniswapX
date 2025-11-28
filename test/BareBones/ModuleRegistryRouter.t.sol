// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/BareBones/ModuleRegistryRouter.sol";
import "src/BareBones/IValidationModule.sol";
import "src/BareBones/DummyModule.sol";
import "src/BareBones/DummyModuleStorage.sol";
import "src/BareBones/EthEchoModule.sol";


// ---------------------------------------------------------------------------
// MOCK VALIDATOR (always allow/deny based on flag)
// ---------------------------------------------------------------------------
contract MockValidationModule is IValidationModule {
    bool public allow;

    constructor(bool _allow) {
        allow = _allow;
    }

    function setAllow(bool v) external {
        allow = v;
    }

    function validate(
        address,
        bytes4,
        address,
        bytes calldata,
        uint256
    ) external view returns (bool) {
        return allow;
    }
}

// ---------------------------------------------------------------------------
// TEST SUITE
// ---------------------------------------------------------------------------
contract ModuleRegistryRouterTest is Test {
    ModuleRegistryRouter router;
    MockValidationModule validator;
    DummyModule module;
    EthEchoModule ethModule;

    uint256 constant POLICY_DELAY = 1 hours;

    // uint8 action types from router
    uint8 constant ACTION_INSTALL_MODULE      = 1;
    uint8 constant ACTION_UPDATE_VALIDATOR    = 2;
    uint8 constant ACTION_UPDATE_POLICY_DELAY = 3;

    // -----------------------------------------------------------------------
    function setUp() public {
        validator = new MockValidationModule(true);
        router = new ModuleRegistryRouter(POLICY_DELAY, address(validator));
        module = new DummyModule();
        ethModule = new EthEchoModule();
    }

    // -----------------------------------------------------------------------
    // PROPOSAL CREATION
    // -----------------------------------------------------------------------
    function test_ProposeModule() public {
        bytes4 selector = DummyModule.setValue.selector;
        bytes memory data = abi.encode(selector, address(module), "setValue(uint256)");

        router.propose(ACTION_INSTALL_MODULE, data);

        bytes32 proposalId = keccak256(
            abi.encode(ACTION_INSTALL_MODULE, data, block.number)
        );

        (uint8 actionType, uint256 eta, bytes memory storedData) =
            router.proposals(proposalId);

        assertEq(actionType, ACTION_INSTALL_MODULE);
        assertEq(eta, block.timestamp + POLICY_DELAY);
        assertEq(storedData, data);
    }

    // -----------------------------------------------------------------------
    // EXECUTION AFTER DELAY
    // -----------------------------------------------------------------------
    function test_ExecuteModuleInstallationAfterDelay() public {
        bytes4 selector = DummyModule.setValue.selector;
        bytes memory payload = abi.encode(selector, address(module), "setValue(uint256)");

        router.propose(ACTION_INSTALL_MODULE, payload);

        bytes32 proposalId = keccak256(
            abi.encode(ACTION_INSTALL_MODULE, payload, block.number)
        );

        vm.warp(block.timestamp + POLICY_DELAY + 1);

        router.execute(proposalId);

        assertEq(router.moduleForSelector(selector), address(module));
    }

    // -----------------------------------------------------------------------
    // VALIDATION MODULE RESTRICTION
    // -----------------------------------------------------------------------
    function test_ProposalRejectedWhenValidatorDisallows() public {
        validator.setAllow(false);

        bytes memory payload = abi.encode(
            DummyModule.setValue.selector,
            address(module),
            "setValue(uint256)"
        );

        vm.expectRevert(ModuleRegistryRouter.NotAuthorized.selector);
        router.propose(ACTION_INSTALL_MODULE, payload);
    }

    // -----------------------------------------------------------------------
    // FALLBACK ROUTING WITH DELEGATECALL + NAMESPACE STORAGE
    // -----------------------------------------------------------------------
    function test_FallbackDelegatecall() public {
        bytes4 selector = DummyModule.setValue.selector;
        bytes memory payload =
            abi.encode(selector, address(module), "setValue(uint256)");

        router.propose(ACTION_INSTALL_MODULE, payload);

        bytes32 proposalId = keccak256(
            abi.encode(ACTION_INSTALL_MODULE, payload, block.number)
        );

        vm.warp(block.timestamp + POLICY_DELAY + 1);
        router.execute(proposalId);

        // Call into module via fallback
        bytes memory callData = abi.encodeWithSelector(selector, 777);
        (bool ok,) = address(router).call(callData);
        require(ok);

        // Load from router storage at the DummyModuleStorage namespace
        uint256 stored = uint256(
            vm.load(
                address(router),
                DummyModuleStorage.NAMESPACE // loads struct slot 0
            )
        );

        assertEq(stored, 777);
    }

    // -----------------------------------------------------------------------
    // INVALID SELECTOR LENGTH
    // -----------------------------------------------------------------------
    function test_FallbackRejectsShortCalldata() public {
        bytes memory badData = hex"01";

        vm.expectRevert(ModuleRegistryRouter.InvalidSelectorLength.selector);
        address(router).call(badData);
    }

    // -----------------------------------------------------------------------
    // ETH RECEIVE
    // -----------------------------------------------------------------------
    function test_FallbackAllowsEthTransfer() public {
        vm.deal(address(this), 1 ether);

        (bool ok,) = address(router).call{value: 1 ether}("");
        require(ok);

        assertEq(address(router).balance, 1 ether);
    }

    function test_FallbackDelegatecallEthEcho() public {
        // Deploy the new module

        // Install via proposal
        bytes4 selector = EthEchoModule.echo.selector;
        bytes memory payload =
            abi.encode(selector, address(ethModule), "echo()");

        router.propose(ACTION_INSTALL_MODULE, payload);

        bytes32 proposalId = keccak256(
            abi.encode(ACTION_INSTALL_MODULE, payload, block.number)
        );

        vm.warp(block.timestamp + POLICY_DELAY + 1);
        router.execute(proposalId);

        // Call echo() via fallback and send ETH
        bytes memory callData = abi.encodeWithSelector(selector);

        (bool ok, bytes memory result) =
            address(router).call{value: 999}(callData);

        require(ok);

        // The module returns msg.value so we decode it
        uint256 returnedValue = abi.decode(result, (uint256));

        assertEq(returnedValue, 999);
    }

}
