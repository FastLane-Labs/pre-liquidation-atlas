// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/// @title RiskOracle
/// @author Fastlane Labs
/// @notice Dynamic risk parameter oracle enabling application-specific ordering rules.
contract RiskOracle is Ownable {
    error IncorrectRiskOracleOperator();

    address public riskOracleOperator;

    /// @dev Dynamic risk parameters are written to transient storage so that they
    ///      exist only within the Risk-Oracle-operator transaction.  This guarantees
    ///      that liquidations executed outside such a transaction fall back to the
    ///      application's default risk parameters and cannot be influenced by the
    ///      operator.
    bytes32 immutable TRANSIENT_LIQUIDATION_PENALTY_KEY;
    bytes32 immutable TRANSIENT_CLOSE_FACTOR_KEY;

    constructor() Ownable(msg.sender) {
        /// @dev Generates unique transient-storage keys for this RiskOracle deployment.
        TRANSIENT_LIQUIDATION_PENALTY_KEY = keccak256(abi.encodePacked(address(this), ".liquidationPenalty"));
        TRANSIENT_CLOSE_FACTOR_KEY = keccak256(abi.encodePacked(address(this), ".closeFactor"));
    }

    modifier OnlyRiskOracleOperator() {
        if (msg.sender != riskOracleOperator) {
            revert IncorrectRiskOracleOperator();
        }
        _;
    }

    /// @dev Owner should be the application; Owner can modify the Risk-Oracle operator entity.
    ///     Setting the riskOracleOperator as address(0) effectively acts as a kill-switch.
    function setRiskOracleOperator(address newRiskOracleOperator) external onlyOwner {
        riskOracleOperator = newRiskOracleOperator;
    }

    /// @notice Invoked by the risk-oracle operator once per liquidator,
    ///         multiple times within the same transaction.
    /// @dev    Enables application-specific ordering based on each
    ///         liquidator's "bid" for risk parameters. Off-chain, the
    ///         Risk Oracle Operator enforces this order.
    ///         Example sequence:
    ///         1. Liquidator A — penalty 0.1 %, close-factor 10 %
    ///         2. Liquidator B — penalty 0.3 %, close-factor 10 %
    ///         3. Liquidator C — penalty 0.3 %, close-factor 15 %
    /// @param liquidationPenalty Liquidation Penalty to apply.
    /// @param closeFactor        Close Factor to apply.
    function setRiskParameters(uint256 liquidationPenalty, uint256 closeFactor) external OnlyRiskOracleOperator {
        bytes32 penaltyKey = TRANSIENT_LIQUIDATION_PENALTY_KEY;
        bytes32 closeKey = TRANSIENT_CLOSE_FACTOR_KEY;
        assembly {
            tstore(penaltyKey, liquidationPenalty)
            tstore(closeKey, closeFactor)
        }
    }

    /// @notice Executes at the end of a Risk-Oracle-operator transaction so that
    ///         any subsequent liquidations in the same block (but outside the
    ///         operator's transaction) revert to the application's default risk
    ///         parameters.
    /// @dev    Transient storage would reset these values to zero automatically
    ///         after the transaction completes.
    function resetRiskParameters() external OnlyRiskOracleOperator {
        bytes32 penaltyKey = TRANSIENT_LIQUIDATION_PENALTY_KEY;
        bytes32 closeKey = TRANSIENT_CLOSE_FACTOR_KEY;
        assembly {
            tstore(penaltyKey, 0)
            tstore(closeKey, 0)
        }
    }

    /// @notice Returns the current risk parameters held in transient storage.
    /// @dev A value of 0 for either field indicates to the application that it
    ///      must use the local default risk parameter for that field.
    /// @return liquidationPenalty Current liquidation penalty stored in transient storage.
    /// @return closeFactor        Current close factor stored in transient storage.
    function getRiskParameters() external view returns (uint256 liquidationPenalty, uint256 closeFactor) {
        bytes32 penaltyKey = TRANSIENT_LIQUIDATION_PENALTY_KEY;
        bytes32 closeKey = TRANSIENT_CLOSE_FACTOR_KEY;
        assembly {
            liquidationPenalty := tload(penaltyKey)
            closeFactor := tload(closeKey)
        }
    }
}
