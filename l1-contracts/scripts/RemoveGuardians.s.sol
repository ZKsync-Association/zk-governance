// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Script.sol";
import {Vm, console2} from "forge-std/Test.sol";

import "../src/EmergencyUpgradeBoard.sol";
import {ProtocolUpgradeHandler} from "../src/ProtocolUpgradeHandler.sol";
import {IProtocolUpgradeHandler} from "../src/interfaces/IProtocolUpgradeHandler.sol";

struct RemoveGuardiansDeployedContracts {
    address emergencyUpgradeBoard;
}

/// @title RemoveGuardians
/// @notice Base script for removing the Guardians from the L1 side of ZKsync governance:
/// 1. Deploys the new two-party EmergencyUpgradeBoard (Security Council + ZK Foundation),
///    replacing the previous three-party board that also required Guardians signatures.
/// 2. Generates the Call[] for the ProtocolUpgradeHandler to hand the guardians role
///    (legal-veto extension + guardians upgrade approval) over to the ZK Foundation
///    multisig and to switch to the new EmergencyUpgradeBoard.
///
/// The generated Call[] must be executed by the ProtocolUpgradeHandler itself, i.e. it is
/// meant to be included in a protocol upgrade proposal (ZIP).
contract RemoveGuardians is Script {
    RemoveGuardiansDeployedContracts internal deployedAddresses;
    IProtocolUpgradeHandler.Call[] internal generatedCalls;

    function getDeployedAddresses() public view returns (RemoveGuardiansDeployedContracts memory) {
        return deployedAddresses;
    }

    function getGeneratedCalls() public view returns (IProtocolUpgradeHandler.Call[] memory) {
        return generatedCalls;
    }

    /// @notice Main function.
    /// @param _currentHandler Address of the current ProtocolUpgradeHandler (proxy).
    /// @param _newGuardians Address that takes over the guardians role on the
    /// ProtocolUpgradeHandler (expected to be the ZK Foundation multisig).
    function runRemoveGuardians(address _currentHandler, address _newGuardians) internal {
        ProtocolUpgradeHandler currentHandler = ProtocolUpgradeHandler(payable(_currentHandler));

        address currentSecurityCouncil = currentHandler.securityCouncil();
        address currentGuardians = currentHandler.guardians();
        address currentEmergencyUpgradeBoard = currentHandler.emergencyUpgradeBoard();
        // The `ZK_FOUNDATION_SAFE()` getter is present on both the previous three-party
        // board and the current two-party one.
        address zkFoundationSafe = EmergencyUpgradeBoard(currentEmergencyUpgradeBoard).ZK_FOUNDATION_SAFE();

        require(_newGuardians != address(0), "New guardians address is zero");
        require(_newGuardians != currentGuardians, "New guardians must differ from the current Guardians");
        require(_newGuardians.code.length != 0, "New guardians must be a contract (multisig)");

        console2.log("=== Current System State ===");
        console2.log("ProtocolUpgradeHandler:", _currentHandler);
        console2.log("Current SecurityCouncil:", currentSecurityCouncil);
        console2.log("Current Guardians:", currentGuardians);
        console2.log("Current EmergencyUpgradeBoard:", currentEmergencyUpgradeBoard);
        console2.log("ZK Foundation Safe:", zkFoundationSafe);
        console2.log("");
        console2.log("New guardians role holder:", _newGuardians);

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Deploy the new two-party EmergencyUpgradeBoard
        vm.startBroadcast(deployerPrivateKey);
        EmergencyUpgradeBoard newEmergencyUpgradeBoard = new EmergencyUpgradeBoard(
            IProtocolUpgradeHandler(_currentHandler),
            currentSecurityCouncil,
            zkFoundationSafe
        );
        vm.stopBroadcast();

        deployedAddresses = RemoveGuardiansDeployedContracts({
            emergencyUpgradeBoard: address(newEmergencyUpgradeBoard)
        });

        console2.log("");
        console2.log("=== Newly Deployed Contracts ===");
        console2.log("New EmergencyUpgradeBoard (2/2):", address(newEmergencyUpgradeBoard));

        // Generate the Call[] that the ProtocolUpgradeHandler must execute
        IProtocolUpgradeHandler.Call[] memory calls = new IProtocolUpgradeHandler.Call[](2);

        calls[0] = IProtocolUpgradeHandler.Call({
            target: _currentHandler,
            value: 0,
            data: abi.encodeCall(ProtocolUpgradeHandler.updateGuardians, (_newGuardians))
        });

        calls[1] = IProtocolUpgradeHandler.Call({
            target: _currentHandler,
            value: 0,
            data: abi.encodeCall(ProtocolUpgradeHandler.updateEmergencyUpgradeBoard, (address(newEmergencyUpgradeBoard)))
        });

        delete generatedCalls;
        generatedCalls.push(calls[0]);
        generatedCalls.push(calls[1]);

        bytes memory encodedCalls = abi.encode(calls);

        console2.log("");
        console2.log("=== Upgrade Calls for ProtocolUpgradeHandler ===");
        console2.log("Call[0]: updateGuardians ->", _newGuardians);
        console2.log("Call[1]: updateEmergencyUpgradeBoard ->", address(newEmergencyUpgradeBoard));
        console2.log("");
        console2.log("abi.encode(Call[]):");
        console2.logBytes(encodedCalls);
    }
}
