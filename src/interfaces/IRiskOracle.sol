// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

interface IRiskOracle {
    function getRiskParameters() external view returns (uint256 liquidationPenalty, uint256 closeFactor);
}
