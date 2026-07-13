// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Script.sol";
import {console2} from "forge-std/Test.sol";

import {RemoveGuardians} from "./RemoveGuardians.s.sol";
import {EmergencyUpgradeBoard} from "../src/EmergencyUpgradeBoard.sol";
import {ProtocolUpgradeHandler} from "../src/ProtocolUpgradeHandler.sol";

/// @title MainnetRemoveGuardians
/// @notice Removes the Guardians from the L1 side of ZKsync governance on mainnet:
/// deploys the new two-party EmergencyUpgradeBoard (Security Council + ZK Foundation)
/// and generates the protocol upgrade Call[] that hands the guardians role on the
/// ProtocolUpgradeHandler over to the ZK Foundation multisig.
///
/// By default the guardians role is transferred to the ZK Foundation Safe registered
/// in the current EmergencyUpgradeBoard; set NEW_GUARDIANS to override.
///
/// Usage:
///   PRIVATE_KEY=<deployer_pk> [NEW_GUARDIANS=<foundation_multisig>] \
///     forge script scripts/MainnetRemoveGuardians.s.sol:MainnetRemoveGuardians \
///     --rpc-url <L1_MAINNET_RPC> --broadcast --verify --etherscan-api-key <KEY> -vvvv
contract MainnetRemoveGuardians is RemoveGuardians {
    // Current ProtocolUpgradeHandler proxy on mainnet
    // (verified via Bridgehub.owner() at 0x303a465B659cBB0ab36eE643eA362c509EEb5213)
    address constant CURRENT_PROTOCOL_UPGRADE_HANDLER = 0xE30Dca3047B37dc7d88849dE4A4Dc07937ad5Ab3;

    function run() external {
        ProtocolUpgradeHandler currentHandler = ProtocolUpgradeHandler(payable(CURRENT_PROTOCOL_UPGRADE_HANDLER));
        address zkFoundationSafe =
            EmergencyUpgradeBoard(currentHandler.emergencyUpgradeBoard()).ZK_FOUNDATION_SAFE();

        address newGuardians = vm.envOr("NEW_GUARDIANS", zkFoundationSafe);

        console2.log("=== Mainnet Guardians Removal ===");

        runRemoveGuardians(CURRENT_PROTOCOL_UPGRADE_HANDLER, newGuardians);
    }
}
