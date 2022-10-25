// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "../interfaces/ISlashIndicator.sol";
import "../extensions/collections/HasValidatorContract.sol";
import "../extensions/collections/HasMaintenanceContract.sol";
import "../extensions/collections/HasRoninTrustedOrganizationContract.sol";
import "../extensions/collections/HasRoninGovernanceAdminContract.sol";
import "../libraries/Math.sol";
import "../precompile-usages/PrecompileUsageValidateDoubleSign.sol";

contract SlashIndicator is
  ISlashIndicator,
  PrecompileUsageValidateDoubleSign,
  HasValidatorContract,
  HasMaintenanceContract,
  HasRoninTrustedOrganizationContract,
  HasRoninGovernanceAdminContract,
  Initializable
{
  using Math for uint256;

  /// @dev Mapping from validator address => period index => unavailability indicator
  mapping(address => mapping(uint256 => uint256)) internal _unavailabilityIndicator;
  /// @dev Maping from validator address => period index => slash type
  mapping(address => mapping(uint256 => SlashType)) internal _unavailabilitySlashed;

  /// @dev The last block that a validator is slashed
  uint256 public lastSlashedBlock;

  /// @dev The number of blocks that the current block can be ahead of the double signed blocks
  uint256 public doubleSigningConstrainBlocks;

  /// @dev The threshold to slash when validator is unavailability reaches misdemeanor
  uint256 public misdemeanorThreshold;
  /// @dev The threshold to slash when validator is unavailability reaches felony
  uint256 public felonyThreshold;
  /// @dev The threshold to slash when a trusted organization does not vote for bridge operators
  uint256 public bridgeVotingThreshold;

  /// @dev The amount of RON to slash felony.
  uint256 public slashFelonyAmount;
  /// @dev The amount of RON to slash double sign.
  uint256 public slashDoubleSignAmount;
  /// @dev The amount of RON to slash bridge voting.
  uint256 public bridgeVotingSlashAmount;
  /// @dev The block duration to jail a validator that reaches felony thresold.
  uint256 public felonyJailDuration;
  /// @dev The block number that the punished validator will be jailed until, due to double signing.
  uint256 public doubleSigningJailUntilBlock;

  modifier onlyCoinbase() {
    require(msg.sender == block.coinbase, "SlashIndicator: method caller must be coinbase");
    _;
  }

  modifier oncePerBlock() {
    require(
      block.number > lastSlashedBlock,
      "SlashIndicator: cannot slash a validator twice or slash more than one validator in one block"
    );
    _;
    lastSlashedBlock = block.number;
  }

  constructor() {
    _disableInitializers();
  }

  /**
   * @dev Initializes the contract storage.
   */
  function initialize(
    address __validatorContract,
    address __maintenanceContract,
    address __roninTrustedOrganizationContract,
    address __roninGovernanceAdminContract,
    uint256 _misdemeanorThreshold,
    uint256 _felonyThreshold,
    uint256 _bridgeVotingThreshold,
    uint256 _slashFelonyAmount,
    uint256 _slashDoubleSignAmount,
    uint256 _bridgeVotingSlashAmount,
    uint256 _felonyJailBlocks,
    uint256 _doubleSigningConstrainBlocks
  ) external initializer {
    _setValidatorContract(__validatorContract);
    _setMaintenanceContract(__maintenanceContract);
    _setRoninTrustedOrganizationContract(__roninTrustedOrganizationContract);
    _setRoninGovernanceAdminContract(__roninGovernanceAdminContract);
    _setSlashThresholds(_felonyThreshold, _misdemeanorThreshold);
    _setBridgeVotingThreshold(_bridgeVotingThreshold);
    _setSlashFelonyAmount(_slashFelonyAmount);
    _setSlashDoubleSignAmount(_slashDoubleSignAmount);
    _setBridgeVotingSlashAmount(_bridgeVotingSlashAmount);
    _setFelonyJailDuration(_felonyJailBlocks);
    _setDoubleSigningConstrainBlocks(_doubleSigningConstrainBlocks);
    _setDoubleSigningJailUntilBlock(type(uint256).max);
  }

  ///////////////////////////////////////////////////////////////////////////////////////
  //                                SLASHING FUNCTIONS                                 //
  ///////////////////////////////////////////////////////////////////////////////////////

  /**
   * @inheritdoc ISlashIndicator
   */
  function slash(address _validatorAddr) external override onlyCoinbase oncePerBlock {
    if (!_shouldSlash(_validatorAddr)) {
      return;
    }

    uint256 _period = _validatorContract.periodOf(block.number);
    uint256 _count = ++_unavailabilityIndicator[_validatorAddr][_period];
    (uint256 _misdemeanorThreshold, uint256 _felonyThreshold) = unavailabilityThresholdsOf(
      _validatorAddr,
      block.number
    );

    SlashType _slashType = getUnavailabilitySlashType(_validatorAddr, _period);

    if (_count >= _felonyThreshold && _slashType < SlashType.FELONY) {
      _unavailabilitySlashed[_validatorAddr][_period] = SlashType.FELONY;
      emit UnavailabilitySlashed(_validatorAddr, SlashType.FELONY, _period);
      _validatorContract.slash(_validatorAddr, block.number + felonyJailDuration, slashFelonyAmount);
      return;
    }

    if (_count >= _misdemeanorThreshold && _slashType < SlashType.MISDEMEANOR) {
      _unavailabilitySlashed[_validatorAddr][_period] = SlashType.MISDEMEANOR;
      emit UnavailabilitySlashed(_validatorAddr, SlashType.MISDEMEANOR, _period);
      _validatorContract.slash(_validatorAddr, 0, 0);
      return;
    }
  }

  /**
   * @inheritdoc ISlashIndicator
   */
  function slashDoubleSign(
    address _validatorAddr,
    bytes calldata _header1,
    bytes calldata _header2
  ) external override onlyCoinbase oncePerBlock {
    if (!_shouldSlash(_validatorAddr)) {
      return;
    }

    if (_pcValidateEvidence(_header1, _header2)) {
      uint256 _period = _validatorContract.periodOf(block.number);
      _unavailabilitySlashed[_validatorAddr][_period] = SlashType.DOUBLE_SIGNING;
      emit UnavailabilitySlashed(_validatorAddr, SlashType.DOUBLE_SIGNING, _period);
      _validatorContract.slash(_validatorAddr, doubleSigningJailUntilBlock, slashDoubleSignAmount);
    }
  }

  /**
   * @inheritdoc ISlashIndicator
   */
  function slashBridgeVoting(address _consensusAddr) external {
    IRoninTrustedOrganization.TrustedOrganization memory _org = _roninTrustedOrganizationContract
      .getTrustedOrganization(_consensusAddr);
    uint256 _lastVotedBlock = Math.max(_roninGovernanceAdminContract.lastVotedBlock(_org.bridgeVoter), _org.addedBlock);
    uint256 _period = _validatorContract.periodOf(block.number);
    if (
      block.number - _lastVotedBlock > bridgeVotingThreshold &&
      _unavailabilitySlashed[_consensusAddr][_period] != SlashType.BRIDGE_VOTING
    ) {
      _unavailabilitySlashed[_consensusAddr][_period] = SlashType.BRIDGE_VOTING;
      emit UnavailabilitySlashed(_consensusAddr, SlashType.BRIDGE_VOTING, _period);
      _validatorContract.slash(_consensusAddr, 0, bridgeVotingSlashAmount);
    }
  }

  ///////////////////////////////////////////////////////////////////////////////////////
  //                               GOVERNANCE FUNCTIONS                                //
  ///////////////////////////////////////////////////////////////////////////////////////

  /**
   * @inheritdoc ISlashIndicator
   */
  function setSlashThresholds(uint256 _felonyThreshold, uint256 _misdemeanorThreshold) external override onlyAdmin {
    _setSlashThresholds(_felonyThreshold, _misdemeanorThreshold);
  }

  /**
   * @inheritdoc ISlashIndicator
   */
  function setSlashFelonyAmount(uint256 _slashFelonyAmount) external override onlyAdmin {
    _setSlashFelonyAmount(_slashFelonyAmount);
  }

  /**
   * @inheritdoc ISlashIndicator
   */
  function setSlashDoubleSignAmount(uint256 _slashDoubleSignAmount) external override onlyAdmin {
    _setSlashDoubleSignAmount(_slashDoubleSignAmount);
  }

  /**
   * @inheritdoc ISlashIndicator
   */
  function setFelonyJailDuration(uint256 _felonyJailDuration) external override onlyAdmin {
    _setFelonyJailDuration(_felonyJailDuration);
  }

  /**
   * @inheritdoc ISlashIndicator
   */
  function setBridgeVotingThreshold(uint256 _threshold) external override onlyAdmin {
    _setBridgeVotingThreshold(_threshold);
  }

  /**
   * @inheritdoc ISlashIndicator
   */
  function setBridgeVotingSlashAmount(uint256 _amount) external override onlyAdmin {
    _setBridgeVotingSlashAmount(_amount);
  }

  ///////////////////////////////////////////////////////////////////////////////////////
  //                                  QUERY FUNCTIONS                                  //
  ///////////////////////////////////////////////////////////////////////////////////////

  /**
   * @inheritdoc ISlashIndicator
   */
  function getUnavailabilitySlashType(address _validatorAddr, uint256 _period) public view returns (SlashType) {
    return _unavailabilitySlashed[_validatorAddr][_period];
  }

  /**
   * @inheritdoc ISlashIndicator
   */
  function unavailabilityThresholdsOf(address _addr, uint256 _block)
    public
    view
    returns (uint256 _misdemeanorThreshold, uint256 _felonyThreshold)
  {
    uint256 _blockLength = _validatorContract.numberOfBlocksInEpoch() * _validatorContract.numberOfEpochsInPeriod();
    uint256 _start = (_block / _blockLength) * _blockLength;
    uint256 _end = _start + _blockLength - 1;
    IMaintenance.Schedule memory _s = _maintenanceContract.getSchedule(_addr);

    bool _fromInRange = _s.from.inRange(_start, _end);
    bool _toInRange = _s.to.inRange(_start, _end);
    uint256 _availableDuration = _blockLength;
    if (_fromInRange && _toInRange) {
      _availableDuration -= _s.to - _s.from + 1;
    } else if (_fromInRange) {
      _availableDuration -= _end - _s.from + 1;
    } else if (_toInRange) {
      _availableDuration -= _s.to - _start + 1;
    }

    _misdemeanorThreshold = misdemeanorThreshold.scale(_availableDuration, _blockLength);
    _felonyThreshold = felonyThreshold.scale(_availableDuration, _blockLength);
  }

  /**
   * @inheritdoc ISlashIndicator
   */
  function currentUnavailabilityIndicator(address _validator) external view override returns (uint256) {
    return getUnavailabilityIndicator(_validator, _validatorContract.periodOf(block.number));
  }

  /**
   * @inheritdoc ISlashIndicator
   */
  function getUnavailabilityThresholds() external view override returns (uint256, uint256) {
    return (misdemeanorThreshold, felonyThreshold);
  }

  /**
   * @inheritdoc ISlashIndicator
   */
  function getUnavailabilityIndicator(address _validator, uint256 _period) public view override returns (uint256) {
    return _unavailabilityIndicator[_validator][_period];
  }

  ///////////////////////////////////////////////////////////////////////////////////////
  //                                 HELPER FUNCTIONS                                  //
  ///////////////////////////////////////////////////////////////////////////////////////

  /**
   * @dev Sets the slash thresholds
   */
  function _setSlashThresholds(uint256 _felonyThreshold, uint256 _misdemeanorThreshold) internal {
    felonyThreshold = _felonyThreshold;
    misdemeanorThreshold = _misdemeanorThreshold;
    emit SlashThresholdsUpdated(_felonyThreshold, _misdemeanorThreshold);
  }

  /**
   * @dev Sets the slash felony amount
   */
  function _setSlashFelonyAmount(uint256 _slashFelonyAmount) internal {
    slashFelonyAmount = _slashFelonyAmount;
    emit SlashFelonyAmountUpdated(_slashFelonyAmount);
  }

  /**
   * @dev Sets the slash double sign amount
   */
  function _setSlashDoubleSignAmount(uint256 _slashDoubleSignAmount) internal {
    slashDoubleSignAmount = _slashDoubleSignAmount;
    emit SlashDoubleSignAmountUpdated(_slashDoubleSignAmount);
  }

  /**
   * @dev Sets the felony jail duration
   */
  function _setFelonyJailDuration(uint256 _felonyJailDuration) internal {
    felonyJailDuration = _felonyJailDuration;
    emit FelonyJailDurationUpdated(_felonyJailDuration);
  }

  /**
   * @dev Sets the double signing constrain blocks
   */
  function _setDoubleSigningConstrainBlocks(uint256 _doubleSigningConstrainBlocks) internal {
    doubleSigningConstrainBlocks = _doubleSigningConstrainBlocks;
    emit DoubleSigningConstrainBlocksUpdated(_doubleSigningConstrainBlocks);
  }

  /**
   * @dev Sets the double signing jail until block number
   */
  function _setDoubleSigningJailUntilBlock(uint256 _doubleSigningJailUntilBlock) internal {
    doubleSigningJailUntilBlock = _doubleSigningJailUntilBlock;
    emit DoubleSigningJailUntilBlockUpdated(_doubleSigningJailUntilBlock);
  }

  /**
   * @dev Sets the threshold to slash when trusted organization does not vote for bridge operators.
   */
  function _setBridgeVotingThreshold(uint256 _threshold) internal {
    bridgeVotingThreshold = _threshold;
    emit BridgeVotingThresholdUpdated(_threshold);
  }

  /**
   * @dev Sets the amount of RON to slash bridge voting.
   */
  function _setBridgeVotingSlashAmount(uint256 _amount) internal {
    bridgeVotingSlashAmount = _amount;
    emit BridgeVotingSlashAmountUpdated(_amount);
  }

  /**
   * @dev Sanity check the address to be slashed
   */
  function _shouldSlash(address _addr) internal view returns (bool) {
    return
      (msg.sender != _addr) &&
      _validatorContract.isBlockProducer(_addr) &&
      !_maintenanceContract.maintaining(_addr, block.number);
  }
}