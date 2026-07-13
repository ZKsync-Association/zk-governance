// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Script.sol";
import {console2} from "forge-std/Test.sol";

import {RemoveGuardians} from "./RemoveGuardians.s.sol";
import {EmergencyUpgradeBoard} from "../src/EmergencyUpgradeBoard.sol";
import {ProtocolUpgradeHandler} from "../src/ProtocolUpgradeHandler.sol";

/// @title StageRemoveGuardians
/// @notice Removes the Guardians from the L1 side of ZKsync governance on the stage
/// environment. See MainnetRemoveGuardians for details.
///
/// Usage:
///   PRIVATE_KEY=<deployer_pk> [NEW_GUARDIANS=<foundation_multisig>] \
///     forge script scripts/StageRemoveGuardians.s.sol:StageRemoveGuardians \
///     --rpc-url <L1_STAGE_RPC> --broadcast --verify --etherscan-api-key <KEY> -vvvv
contract StageRemoveGuardians is RemoveGuardians {
    // Current ProtocolUpgradeHandler on stage (testnet)
    // (verified via stage Bridgehub.owner() at 0x236D1c3Ff32Bd0Ca26b72Af287E895627c0478cE)
    address constant CURRENT_PROTOCOL_UPGRADE_HANDLER = 0x8f08627524aeD610192132A425D6b9C32a1727EF;

    function run() external {
        ProtocolUpgradeHandler currentHandler = ProtocolUpgradeHandler(payable(CURRENT_PROTOCOL_UPGRADE_HANDLER));
        address zkFoundationSafe =
            EmergencyUpgradeBoard(currentHandler.emergencyUpgradeBoard()).ZK_FOUNDATION_SAFE();

        address newGuardians = vm.envOr("NEW_GUARDIANS", zkFoundationSafe);

        console2.log("=== Stage Guardians Removal ===");

        runRemoveGuardians(CURRENT_PROTOCOL_UPGRADE_HANDLER, newGuardians);
    }
}
