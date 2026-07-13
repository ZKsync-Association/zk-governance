// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test, Vm} from "forge-std/Test.sol";

import {IProtocolUpgradeHandler} from "../src/interfaces/IProtocolUpgradeHandler.sol";
import {ProtocolUpgradeHandler} from "../src/ProtocolUpgradeHandler.sol";
import {EmergencyUpgradeBoard} from "../src/EmergencyUpgradeBoard.sol";

import {MainnetRemoveGuardians} from "../scripts/MainnetRemoveGuardians.s.sol";
import {RemoveGuardiansDeployedContracts} from "../scripts/RemoveGuardians.s.sol";

/// @dev Verifies the guardians removal flow against a mainnet fork: runs the
/// MainnetRemoveGuardians script, executes the Call[] it generates (via the current
/// EmergencyUpgradeBoard as a stand-in for the protocol upgrade proposal that will carry
/// them in production), and checks the resulting system state.
contract RemoveGuardiansForkTest is Test {
  // Must match MainnetRemoveGuardians.CURRENT_PROTOCOL_UPGRADE_HANDLER
  address constant CURRENT_PROTOCOL_UPGRADE_HANDLER = 0xE30Dca3047B37dc7d88849dE4A4Dc07937ad5Ab3;

  MainnetRemoveGuardians script;
  ProtocolUpgradeHandler handler;

  address oldEmergencyUpgradeBoard;
  address oldGuardians;
  address zkFoundationSafe;
  address securityCouncil;
  address newEmergencyUpgradeBoard;

  modifier onlyMainnet() {
    if (block.chainid == 1) {
      _;
    } else {
      return;
    }
  }

  function setUp() external onlyMainnet {
    handler = ProtocolUpgradeHandler(payable(CURRENT_PROTOCOL_UPGRADE_HANDLER));

    oldEmergencyUpgradeBoard = handler.emergencyUpgradeBoard();
    oldGuardians = handler.guardians();
    securityCouncil = handler.securityCouncil();
    // The `ZK_FOUNDATION_SAFE()` getter exists on both the three-party and two-party boards.
    zkFoundationSafe = EmergencyUpgradeBoard(oldEmergencyUpgradeBoard).ZK_FOUNDATION_SAFE();

    Vm.Wallet memory deployerWallet = vm.createWallet("deployerWallet");
    vm.setEnv("PRIVATE_KEY", vm.toString(deployerWallet.privateKey));
    // Pin the new guardians role holder so the test is deterministic even if the
    // environment sets NEW_GUARDIANS.
    vm.setEnv("NEW_GUARDIANS", vm.toString(zkFoundationSafe));

    script = new MainnetRemoveGuardians();
    script.run();

    newEmergencyUpgradeBoard = script.getDeployedAddresses().emergencyUpgradeBoard;
  }

  function _executeViaEmergencyUpgrade(address _executor, IProtocolUpgradeHandler.Call[] memory _calls, bytes32 _salt)
    internal
    returns (bytes32 id)
  {
    IProtocolUpgradeHandler.UpgradeProposal memory proposal =
      IProtocolUpgradeHandler.UpgradeProposal({calls: _calls, salt: _salt, executor: _executor});
    id = keccak256(abi.encode(proposal));

    vm.prank(_executor);
    handler.executeEmergencyUpgrade(proposal);
  }

  function _executeRemoveGuardiansCalls() internal {
    _executeViaEmergencyUpgrade(oldEmergencyUpgradeBoard, script.getGeneratedCalls(), bytes32(uint256(1)));
  }

  function test_MainnetForkNewBoardConfiguration() external onlyMainnet {
    EmergencyUpgradeBoard newBoard = EmergencyUpgradeBoard(newEmergencyUpgradeBoard);
    assertEq(address(newBoard.PROTOCOL_UPGRADE_HANDLER()), CURRENT_PROTOCOL_UPGRADE_HANDLER);
    assertEq(newBoard.SECURITY_COUNCIL(), securityCouncil);
    assertEq(newBoard.ZK_FOUNDATION_SAFE(), zkFoundationSafe);
  }

  function test_MainnetForkGuardiansRoleHandedToFoundation() external onlyMainnet {
    _executeRemoveGuardiansCalls();

    assertEq(handler.guardians(), zkFoundationSafe);
    assertEq(handler.emergencyUpgradeBoard(), newEmergencyUpgradeBoard);
    // The Security Council and the deposed Guardians multisig are untouched.
    assertEq(handler.securityCouncil(), securityCouncil);
  }

  function test_MainnetForkOldBoardLosesEmergencyPowers() external onlyMainnet {
    _executeRemoveGuardiansCalls();

    IProtocolUpgradeHandler.Call[] memory noCalls = new IProtocolUpgradeHandler.Call[](0);
    IProtocolUpgradeHandler.UpgradeProposal memory proposal = IProtocolUpgradeHandler.UpgradeProposal({
      calls: noCalls,
      salt: bytes32(uint256(2)),
      executor: oldEmergencyUpgradeBoard
    });

    vm.prank(oldEmergencyUpgradeBoard);
    vm.expectRevert("Only Emergency Upgrade Board is allowed to call this function");
    handler.executeEmergencyUpgrade(proposal);
  }

  function test_MainnetForkNewBoardCanExecuteEmergencyUpgrade() external onlyMainnet {
    _executeRemoveGuardiansCalls();

    IProtocolUpgradeHandler.Call[] memory noCalls = new IProtocolUpgradeHandler.Call[](0);
    bytes32 id = _executeViaEmergencyUpgrade(newEmergencyUpgradeBoard, noCalls, bytes32(uint256(3)));

    assertEq(uint8(handler.upgradeState(id)), uint8(IProtocolUpgradeHandler.UpgradeState.Done));
  }
}
