// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../factories/factory-maptoken-mainchain-testnet.s.sol";
import "./base-maptoken.s.sol";

contract Migration__20240308_MapTokenAnimaMainchain is Base__MapToken, Factory__MapTokensMainchain_Testnet {
  function _initCaller() internal override(Base__MapToken, Factory__MapTokensMainchain_Testnet) returns (address) {
    return Base__MapToken._initCaller();
  }

  function _initTokenList() internal override(Base__MapToken, Factory__MapTokensMainchain_Testnet) returns (uint256 totalToken, MapTokenInfo[] memory infos) {
    return Base__MapToken._initTokenList();
  }

  function run() public override {
    console2.log("nonce", vm.getNonce(SM_GOVERNOR)); // Log nonce for workaround of nonce increase when switch network
    super.run();
  }
}
