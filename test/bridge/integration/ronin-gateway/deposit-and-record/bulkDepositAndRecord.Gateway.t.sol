// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { console2 as console } from "forge-std/console2.sol";
import { Transfer } from "@ronin/contracts/libraries/Transfer.sol";
import { LibTokenInfo, TokenStandard } from "@ronin/contracts/libraries/LibTokenInfo.sol";
import { TokenOwner } from "@ronin/contracts/libraries/LibTokenOwner.sol";
import "../../BaseIntegration.t.sol";

contract BulkDepositAndRecord_Gateway_Test is BaseIntegration_Test {
  using Transfer for Transfer.Receipt;

  address _newBridgeOperator;
  uint256 _numOperatorsForVoteExecuted;
  Transfer.Receipt _sampleReceipt;
  Transfer.Receipt[] _bulkReceipts;
  uint256 _id = 0;

  function setUp() public virtual override {
    super.setUp();

    vm.deal(address(_bridgeReward), 10 ether);
    _sampleReceipt = Transfer.Receipt({
      id: 0,
      kind: Transfer.Kind.Deposit,
      ronin: TokenOwner({ addr: makeAddr("recipient"), tokenAddr: address(_roninWeth), chainId: block.chainid }),
      mainchain: TokenOwner({ addr: makeAddr("requester"), tokenAddr: address(_mainchainWeth), chainId: block.chainid }),
      info: TokenInfo({ erc: TokenStandard.ERC20, id: 0, quantity: 100 })
    });

    _numOperatorsForVoteExecuted = (_roninBridgeManager.minimumVoteWeight() - 1) / 100 + 1;
    console.log("Num operators for vote executed:", _numOperatorsForVoteExecuted);
    console.log("Total operators:", _param.roninBridgeManager.bridgeOperators.length);
  }

  function test_bulkDepositFor_wrapUp_checkRewardAndSlash() public {
    _depositFor(_numOperatorsForVoteExecuted);
    _moveToEndPeriodAndWrapUpEpoch();

    console.log("=============== First 50 Receipts ===========");
    _bulkDepositFor(_numOperatorsForVoteExecuted);

    _wrapUpEpoch();
    _wrapUpEpoch();

    _moveToEndPeriodAndWrapUpEpoch();

    console.log("=============== Check slash and reward behavior  ===========");
    console.log("==== Check total ballot before new deposit  ====");

    logBridgeTracking();

    uint256 lastSyncedPeriod = uint256(vm.load(address(_bridgeTracking), bytes32(uint256(11))));
    for (uint256 i; i < _numOperatorsForVoteExecuted; i++) {
      address operator = _param.roninBridgeManager.bridgeOperators[i];
      assertEq(_bridgeTracking.totalBallotOf(lastSyncedPeriod, operator), _id);
    }

    for (uint256 i = _numOperatorsForVoteExecuted; i < _param.roninBridgeManager.bridgeOperators.length; i++) {
      address operator = _param.roninBridgeManager.bridgeOperators[i];
      assertEq(_bridgeTracking.totalBallotOf(lastSyncedPeriod, operator), 0);
    }

    console.log("==== Check total ballot after new deposit  ====");
    _depositFor(_numOperatorsForVoteExecuted);

    logBridgeTracking();
    logBridgeSlash();

    lastSyncedPeriod = uint256(vm.load(address(_bridgeTracking), bytes32(uint256(11))));
    for (uint256 i; i < _param.roninBridgeManager.bridgeOperators.length; i++) {
      address operator = _param.roninBridgeManager.bridgeOperators[i];
      assertEq(_bridgeTracking.totalBallotOf(lastSyncedPeriod, operator), 0);
    }

    uint256[] memory toPeriodSlashArr = _bridgeSlash.getSlashUntilPeriodOf(_param.roninBridgeManager.bridgeOperators);
    for (uint256 i = _numOperatorsForVoteExecuted; i < _param.roninBridgeManager.bridgeOperators.length; i++) {
      assertEq(toPeriodSlashArr[i], 7);
    }
  }

  function test_RecordAllVoters_bulkDepositFor() public {
    uint256 numAllOperators = _param.roninBridgeManager.bridgeOperators.length;

    _depositFor(numAllOperators);
    _moveToEndPeriodAndWrapUpEpoch();

    // console.log("=============== First 50 Receipts ===========");
    _bulkDepositFor(numAllOperators);

    _wrapUpEpoch();
    _wrapUpEpoch();

    _moveToEndPeriodAndWrapUpEpoch();

    console.log("=============== Check slash and reward behavior  ===========");
    console.log("==== Check total ballot before new deposit  ====");

    logBridgeTracking();

    uint256 lastSyncedPeriod = uint256(vm.load(address(_bridgeTracking), bytes32(uint256(11))));
    for (uint256 i; i < numAllOperators; i++) {
      address operator = _param.roninBridgeManager.bridgeOperators[i];
      assertEq(_bridgeTracking.totalBallotOf(lastSyncedPeriod, operator), _id, "Total ballot should be equal to the number of receipts");
    }
  }

  function _depositFor(uint256 numVote) internal {
    console.log(">> depositFor ....");
    _sampleReceipt.id = ++_id;
    for (uint256 i; i < numVote; i++) {
      console.log(" -> Operator vote:", _param.roninBridgeManager.bridgeOperators[i]);
      vm.prank(_param.roninBridgeManager.bridgeOperators[i]);
      _roninGatewayV3.depositFor(_sampleReceipt);
    }
  }

  function _bulkDepositFor(uint256 numVote) internal {
    console.log(">> bulkDepositFor ....");
    _prepareBulkRequest();
    for (uint256 i; i < numVote; i++) {
      console.log(" -> Operator vote:", _param.roninBridgeManager.bridgeOperators[i]);
      vm.prank(_param.roninBridgeManager.bridgeOperators[i]);
      bool[] memory _executedReceipts = _roninGatewayV3.tryBulkDepositFor(_bulkReceipts);

      for (uint256 j; j < _executedReceipts.length; j++) {
        assertTrue(_roninGatewayV3.depositVoted(block.chainid, _bulkReceipts[j].id, _param.roninBridgeManager.bridgeOperators[i]), "Receipt should be voted");
      }
    }
  }

  function _prepareBulkRequest() internal {
    delete _bulkReceipts;

    for (uint256 i; i < 50; i++) {
      _sampleReceipt.id = ++_id;
      _bulkReceipts.push(_sampleReceipt);
    }
  }
}