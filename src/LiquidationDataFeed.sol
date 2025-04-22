// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

//import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/// @dev A fixed key to use in transient storage for the dynamic penalty.
/// In practice you might compute this as a hash of a constant string.
bytes32 constant TRANSIENT_LIQUIDATION_PENALTY_KEY = 0xd033e44c9f2a65a460c9f878712895054941eb772c7716e6dee8b66c21be9561;
/// @dev A fixed key to use in transient storage for dynamic close factor
bytes32 constant TRANSIENT_CLOSE_FACTOR_KEY = 0x2345678901234567890123456789012345678901234567890123456789012345;

/// @title PenaltyFeed using transient storage for dynamic penalty updates
// TODO make ownable
contract LiquidationDataFeed {

    // Whitelisted updater of risk parameters
    address public riskOracle = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF;

    error IncorrectRiskOracle();

    //constructor() Ownable(msg.sender) {}
    constructor() {}

    modifier OnlyRiskOracle() {
        if (msg.sender != riskOracle) {
            revert IncorrectRiskOracle();
        }
        _;
    }

    /// @notice Sets a new risk parameter values in transient storage.
    /// @param newLiquidationPenalty The new penalty value.
    /// @param newCloseFactor The new close factor value.
    function setRiskParameters(uint256 newLiquidationPenalty, uint256 newCloseFactor) external OnlyRiskOracle {

        // tstore(key, value): store `newPenalty` under TRANSIENT_PENALTY_KEY.
        assembly {
            tstore(TRANSIENT_LIQUIDATION_PENALTY_KEY, newLiquidationPenalty)
        }

        // tstore(key, value): store `newCloseFactor` under TRANSIENT_CLOSE_FACTOR_KEY.
        assembly {
            tstore(TRANSIENT_CLOSE_FACTOR_KEY, newCloseFactor)
        }
    }

    /// @notice Resets the dynamic penalty value in transient storage to zero.
    function resetRiskParameters() external OnlyRiskOracle {
        assembly {
            // Clear the transient storage slot by writing zero. 
            tstore(TRANSIENT_LIQUIDATION_PENALTY_KEY, 0)
        }

        // Clear the transient storage slot by writing zero.
        assembly {
            tstore(TRANSIENT_CLOSE_FACTOR_KEY, 0)
        }      
    }

    /// @notice Returns the current penalty.
    /// If a dynamic penalty is set in transient storage, that value is returned;
    function getLatestPenalty() external view returns (uint256 result) {
        assembly {
            // Load dynamic penalty from transient storage.
            result := tload(TRANSIENT_LIQUIDATION_PENALTY_KEY)
        }
    }

    /// @notice Returns the current close factor.
    /// @dev If a dynamic close factor is set in transient storage, 
    ///      that value is returned;
    function getLatestCloseFactor() public view returns (uint256 result) {
        assembly {
            // Load dynamic close factor from transient storage.
            result := tload(TRANSIENT_CLOSE_FACTOR_KEY)
        }
    }
}