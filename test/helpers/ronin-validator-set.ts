import { ethers, network } from 'hardhat';

import { expect } from 'chai';
import { BigNumber, BigNumberish, ContractTransaction } from 'ethers';

import { expectEvent } from './utils';
import { RoninValidatorSet__factory } from '../../src/types';

const contractInterface = RoninValidatorSet__factory.createInterface();

export class EpochController {
  readonly minOffset: number;
  readonly numberOfBlocksInEpoch: number;
  readonly numberOfEpochsInPeriod: number;
  readonly numberOfBlocksInPeriod: number;

  constructor(minOffset: number, numberOfBlocksInEpoch: number, numberOfEpochsInPeriod: number) {
    this.minOffset = minOffset;
    this.numberOfBlocksInEpoch = numberOfBlocksInEpoch;
    this.numberOfEpochsInPeriod = numberOfEpochsInPeriod;
    this.numberOfBlocksInPeriod = numberOfBlocksInEpoch * numberOfEpochsInPeriod;
  }

  calculateStartOfEpoch(block: number): BigNumber {
    return BigNumber.from(
      Math.floor((block + this.minOffset) / this.numberOfBlocksInEpoch + 1) * this.numberOfBlocksInEpoch
    );
  }

  diffToEndEpoch(block: BigNumberish): BigNumber {
    return BigNumber.from(this.numberOfBlocksInEpoch).sub(BigNumber.from(block).mod(this.numberOfBlocksInEpoch)).sub(1);
  }

  diffToEndPeriod(block: BigNumberish): BigNumber {
    return BigNumber.from(this.numberOfBlocksInPeriod)
      .sub(BigNumber.from(block).mod(this.numberOfBlocksInPeriod))
      .sub(1);
  }

  calculateEndOfEpoch(block: BigNumberish): BigNumber {
    return BigNumber.from(block).add(this.diffToEndEpoch(block));
  }

  calculateEndOfPeriod(block: BigNumberish): BigNumber {
    return BigNumber.from(block).add(this.diffToEndPeriod(block));
  }

  calculatePeriodOf(block: BigNumberish): BigNumber {
    if (block == 0) {
      return BigNumber.from(0);
    }
    return BigNumber.from(block).div(BigNumber.from(this.numberOfBlocksInPeriod)).add(1);
  }

  async currentPeriod(): Promise<BigNumber> {
    return this.calculatePeriodOf(await ethers.provider.getBlockNumber());
  }

  async mineToBeforeEndOfEpoch() {
    let number = this.diffToEndEpoch(await ethers.provider.getBlockNumber()).sub(1);
    if (number.lt(0)) {
      number = number.add(this.numberOfBlocksInEpoch);
    }
    return network.provider.send('hardhat_mine', [ethers.utils.hexStripZeros(number.toHexString())]);
  }

  async mineToBeforeEndOfPeriod() {
    let number = this.diffToEndPeriod(await ethers.provider.getBlockNumber()).sub(1);
    if (number.lt(0)) {
      number = number.add(this.numberOfBlocksInPeriod);
    }
    return network.provider.send('hardhat_mine', [ethers.utils.hexStripZeros(number.toHexString())]);
  }

  async mineToBeginOfNewEpoch() {
    await this.mineToBeforeEndOfEpoch();
    return network.provider.send('hardhat_mine', ['0x2']);
  }

  async mineToBeginOfNewPeriod() {
    await this.mineToBeforeEndOfPeriod();
    return network.provider.send('hardhat_mine', ['0x2']);
  }
}

export const expects = {
  emitRewardDeprecatedEvent: async function (
    tx: ContractTransaction,
    expectingCoinbaseAddr: string,
    expectingDeprecatedReward: BigNumberish
  ) {
    await expectEvent(
      contractInterface,
      'RewardDeprecated',
      tx,
      (event) => {
        expect(event.args[0], 'invalid coinbase address').eq(expectingCoinbaseAddr);
        expect(event.args[1], 'invalid reward').eq(expectingDeprecatedReward);
      },
      1
    );
  },

  emitBlockRewardSubmittedEvent: async function (
    tx: ContractTransaction,
    expectingCoinbaseAddr: string,
    expectingSubmittedReward: BigNumberish,
    expectingStakingVesting: BigNumberish
  ) {
    await expectEvent(
      contractInterface,
      'BlockRewardSubmitted',
      tx,
      (event) => {
        expect(event.args[0], 'invalid coinbase address').eq(expectingCoinbaseAddr);
        expect(event.args[1], 'invalid submitted reward').eq(expectingSubmittedReward);
        expect(event.args[2], 'invalid staking vesting').eq(expectingStakingVesting);
      },
      1
    );
  },

  emitMiningRewardDistributedEvent: async function (
    tx: ContractTransaction,
    expectingCoinbaseAddr: string,
    expectingRecipientAddr: string,
    expectingAmount: BigNumberish
  ) {
    await expectEvent(
      contractInterface,
      'MiningRewardDistributed',
      tx,
      (event) => {
        expect(event.args[0], 'invalid coinbase address').eq(expectingCoinbaseAddr);
        expect(event.args[1], 'invalid recipient address').eq(expectingRecipientAddr);
        expect(event.args[2], 'invalid amount').eq(expectingAmount);
      },
      1
    );
  },

  emitBridgeOperatorRewardDistributedEvent: async function (
    tx: ContractTransaction,
    expectingCoinbaseAddr: string,
    expectingRecipientAddr: string,
    expectingAmount: BigNumberish
  ) {
    await expectEvent(
      contractInterface,
      'BridgeOperatorRewardDistributed',
      tx,
      (event) => {
        expect(event.args[0], 'invalid coinbase address').eq(expectingCoinbaseAddr);
        expect(event.args[1], 'invalid recipient address').eq(expectingRecipientAddr);
        expect(event.args[2], 'invalid amount').eq(expectingAmount);
      },
      1
    );
  },

  emitStakingRewardDistributedEvent: async function (tx: ContractTransaction, expectingAmount: BigNumberish) {
    await expectEvent(
      contractInterface,
      'StakingRewardDistributed',
      tx,
      (event) => {
        expect(event.args[0], 'invalid distributing reward').eq(expectingAmount);
      },
      1
    );
  },

  emitValidatorSetUpdatedEvent: async function (tx: ContractTransaction, expectingValidators: string[]) {
    await expectEvent(
      contractInterface,
      'ValidatorSetUpdated',
      tx,
      (event) => {
        expect(event.args[0], 'invalid validator set').eql(expectingValidators);
      },
      1
    );
  },

  emitBlockProducerSetUpdatedEvent: async function (tx: ContractTransaction, expectingBlockProducers: string[]) {
    await expectEvent(
      contractInterface,
      'BlockProducerSetUpdated',
      tx,
      (event) => {
        expect(event.args[0], 'invalid validator set').eql(expectingBlockProducers);
      },
      1
    );
  },

  emitActivatedBlockProducersEvent: async function (tx: ContractTransaction, expectingProducers: string[]) {
    await expectEvent(
      contractInterface,
      'ActivatedBlockProducers',
      tx,
      (event) => {
        expect(event.args[0], 'invalid activated producer set').eql(expectingProducers);
      },
      1
    );
  },

  emitDeactivatedBlockProducersEvent: async function (tx: ContractTransaction, expectingProducers: string[]) {
    await expectEvent(
      contractInterface,
      'DeactivatedBlockProducers',
      tx,
      (event) => {
        expect(event.args[0], 'invalid deactivated producer set').eql(expectingProducers);
      },
      1
    );
  },

  emitWrappedUpEpochEvent: async function (tx: ContractTransaction) {
    await expectEvent(contractInterface, 'WrappedUpEpoch', tx, () => {}, 1);
  },
};