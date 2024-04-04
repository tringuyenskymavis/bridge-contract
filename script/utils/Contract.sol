// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { LibString, TContract } from "@fdk/types/Types.sol";

enum Contract {
  WETH,
  WRON,
  AXS,
  SLP,
  USDC,
  MockERC721,
  BridgeTracking,
  BridgeSlash,
  BridgeReward,
  RoninPauseEnforcer,
  RoninGatewayV3,
  RoninBridgeManager,
  RoninBridgeManagerConstructor,
  MainchainPauseEnforcer,
  MainchainGatewayV3,
  MainchainBridgeManager,
  MainchainWethUnwrapper
}

using { key, name } for Contract global;

function key(Contract contractEnum) pure returns (TContract) {
  return TContract.wrap(LibString.packOne(name(contractEnum)));
}

function name(Contract contractEnum) pure returns (string memory) {
  if (contractEnum == Contract.WETH) return "WETH";
  if (contractEnum == Contract.WRON) return "WRON";
  if (contractEnum == Contract.AXS) return "AXS";
  if (contractEnum == Contract.SLP) return "SLP";
  if (contractEnum == Contract.USDC) return "USDC";
  if (contractEnum == Contract.MockERC721) return "MockERC721";

  if (contractEnum == Contract.BridgeTracking) return "BridgeTracking";
  if (contractEnum == Contract.BridgeSlash) return "BridgeSlash";
  if (contractEnum == Contract.BridgeReward) return "BridgeReward";
  if (contractEnum == Contract.RoninPauseEnforcer) return "PauseEnforcer";
  if (contractEnum == Contract.RoninGatewayV3) return "RoninGatewayV3";
  if (contractEnum == Contract.RoninBridgeManager) return "RoninBridgeManager";
  if (contractEnum == Contract.RoninBridgeManagerConstructor) return "RoninBridgeManagerConstructor";

  if (contractEnum == Contract.MainchainPauseEnforcer) return "PauseEnforcer";
  if (contractEnum == Contract.MainchainGatewayV3) return "MainchainGatewayV3";
  if (contractEnum == Contract.MainchainBridgeManager) return "MainchainBridgeManager";
  if (contractEnum == Contract.MainchainWethUnwrapper) return "WethUnwrapper";

  revert("Contract: Unknown contract");
}
