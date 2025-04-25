// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;
// Force foundry to compile Morpho Blue even though it's not imported by PreLiquidation or by the tests.
// Morpho Blue will be compiled with its own solidity version.
// The resulting bytecode is then loaded by BaseTest.sol.

import "../../lib/morpho-blue/src/Morpho.sol";
