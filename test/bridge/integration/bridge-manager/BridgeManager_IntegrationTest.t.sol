// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { console2 } from "forge-std/console2.sol";
import { StdStyle } from "forge-std/StdStyle.sol";

import { IBridgeManager } from "@ronin/contracts/interfaces/bridge/IBridgeManager.sol";
import { MockRoninGatewayV3Extended } from "@ronin/contracts/mocks/ronin/MockRoninGatewayV3Extended.sol";
import { RoninBridgeManager } from "@ronin/contracts/ronin/gateway/RoninBridgeManager.sol";
import { MainchainBridgeManager } from "@ronin/contracts/mainchain/MainchainBridgeManager.sol";
import { MainchainGatewayV3 } from "@ronin/contracts/mainchain/MainchainGatewayV3.sol";
import { ContractType } from "@ronin/contracts/utils/ContractType.sol";
import { BridgeSlash } from "src/ronin/gateway/BridgeSlash.sol";
import { BridgeTracking } from "src/ronin/gateway/BridgeTracking.sol";
import { BridgeReward } from "src/ronin/gateway/BridgeReward.sol";

import { Base_Test } from "@ronin/test/Base.t.sol";
import { SignerUtils } from "@ronin/test/utils/Signers.sol";
import { InitTest } from "@ronin/test/init-test/InitTest.sol";
import { DefaultTestConfig } from "@ronin/test/init-test/DefaultTestConfig.sol";
import "@ronin/test/init-test/Structs.sol";
import "./BridgeManagerInterface.sol";

contract Bridge_Integration_Test is Base_Test, InitTest, SignerUtils {
  uint256 internal _operatorNum;
  uint256 internal _bridgeAdminNumerator;
  uint256 internal _bridgeAdminDenominator;
  Account[] internal _operators;
  Account[] internal _governors;

  MockRoninGatewayV3Extended internal _roninGatewayV3Contract;
  MainchainGatewayV3 internal _mainchainGatewayV3;
  RoninBridgeManager internal _roninBridgeManager;
  BridgeTracking internal _bridgeTracking;
  BridgeSlash internal _bridgeSlash;
  BridgeReward internal _bridgeReward;
  MainchainBridgeManager internal _mainchainBridgeManager;

  BridgeManagerInterface _bridgeManagerInterface;

  function setUp() public virtual {
    _operatorNum = 6;
    _setOperators(getSigners(_operatorNum));
    _setGovernors(getSigners(_operatorNum));
    _prepareDeploymentArgs();

    InitTestOutput memory output = init();

    _roninGatewayV3Contract = MockRoninGatewayV3Extended(output.roninGatewayV3Address);
    _roninBridgeManager = RoninBridgeManager(output.roninBridgeManagerAddress);
    _bridgeSlash = BridgeSlash(output.bridgeSlashAddress);
    _bridgeReward = BridgeReward(output.bridgeRewardAddress);
    _bridgeTracking = BridgeTracking(output.bridgeTrackingAddress);

    _mainchainGatewayV3 = MainchainGatewayV3(output.mainchainGatewayV3Address);
    _mainchainBridgeManager = MainchainBridgeManager(output.mainchainBridgeManagerAddress);

    vm.roll(1);
  }

  function _prepareDeploymentArgs() internal {
    _bridgeAdminNumerator = 2;
    _bridgeAdminDenominator = 4;

    BridgeManagerMemberStruct[] memory members = new BridgeManagerMemberStruct[](_operatorNum);
    for (uint256 i; i < members.length; i++) {
      members[i].operator = _operators[i].addr;
      members[i].governor = _governors[i].addr;
      members[i].weight = 100;
    }

    BridgeManagerArguments memory arg = BridgeManagerArguments({
      numerator: _bridgeAdminNumerator,
      denominator: _bridgeAdminDenominator,
      expiryDuration: DefaultTestConfig.get().bridgeManagerArguments.expiryDuration,
      members: members,
      targets: DefaultTestConfig.get().bridgeManagerArguments.targets
    });

    setBridgeManagerArgs(arg);
  }

  function _setOperators(Account[] memory operators) internal {
    delete _operators;
    for (uint256 i; i < operators.length; i++) {
      _operators.push(operators[i]);
    }
  }

  function _setGovernors(Account[] memory governors) internal {
    delete _governors;
    for (uint256 i; i < governors.length; i++) {
      _governors.push(governors[i]);
    }
  }
}
