// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/console2.sol";

import {ERC20Mock} from "../src/mocks/ERC20Mock.sol";
import {IrmMock} from "../src/mocks/IrmMock.sol";
import {OracleMock} from "../src/mocks/OracleMock.sol";

import {MarketParams, IMorpho, Id} from "../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {IOracle} from "../lib/morpho-blue/src/interfaces/IOracle.sol";
import {MarketParamsLib} from "../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {ORACLE_PRICE_SCALE} from "../lib/morpho-blue/src/libraries/ConstantsLib.sol";
import {WAD, MathLib} from "../lib/morpho-blue/src/libraries/MathLib.sol";
import {UtilsLib} from "../lib/morpho-blue/src/libraries/UtilsLib.sol";

import {PreLiquidationParams, IPreLiquidation} from "../src/interfaces/IPreLiquidation.sol";
import {PreLiquidationFactory} from "../src/PreLiquidationFactory.sol";
import {RiskOracle} from "../src/RiskOracle.sol";

contract BaseTest is Test {
    using MarketParamsLib for MarketParams;
    using MathLib for uint256;

    address internal SUPPLIER = makeAddr("Supplier");
    address internal BORROWER = makeAddr("Borrower");
    address internal LIQUIDATOR = makeAddr("Liquidator");
    address internal MORPHO_OWNER = makeAddr("MorphoOwner");
    address internal MORPHO_FEE_RECIPIENT = makeAddr("MorphoFeeRecipient");

    IMorpho internal MORPHO = IMorpho(deployCode("Morpho.sol", abi.encode(MORPHO_OWNER)));
    ERC20Mock internal loanToken = new ERC20Mock("loan", "B", 18);
    ERC20Mock internal collateralToken = new ERC20Mock("collateral", "C", 18);
    OracleMock internal oracle = new OracleMock();
    IrmMock internal irm = new IrmMock();
    uint256 internal lltv = 0.8 ether; // 80%

    MarketParams internal marketParams;
    Id internal id;

    uint256 internal minCollateral = 10 ** 18;
    uint256 internal maxCollateral = 10 ** 24;

    PreLiquidationFactory internal factory;
    IPreLiquidation internal preLiquidation;

    RiskOracle internal riskOracle;

    function setUp() public virtual {
        vm.label(address(MORPHO), "Morpho");
        vm.label(address(loanToken), "Loan");
        vm.label(address(collateralToken), "Collateral");
        vm.label(address(oracle), "Oracle");
        vm.label(address(irm), "Irm");

        oracle.setPrice(ORACLE_PRICE_SCALE);

        irm.setApr(0.5 ether); // 50%.

        vm.startPrank(MORPHO_OWNER);
        MORPHO.enableIrm(address(irm));
        MORPHO.setFeeRecipient(MORPHO_FEE_RECIPIENT);

        MORPHO.enableLltv(lltv);
        vm.stopPrank();

        marketParams = MarketParams({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(oracle),
            irm: address(irm),
            lltv: lltv
        });
        id = marketParams.id();

        MORPHO.createMarket(marketParams);

        vm.startPrank(SUPPLIER);
        loanToken.approve(address(MORPHO), type(uint256).max);
        vm.stopPrank();

        vm.prank(BORROWER);
        collateralToken.approve(address(MORPHO), type(uint256).max);

        address riskFactorOperator = makeAddr("RiskFactorOperator");
        riskOracle = new RiskOracle();
        riskOracle.setRiskOracleOperator(riskFactorOperator);

        vm.prank(riskFactorOperator);
        uint256 preLif = 5000;
        uint256 preLcf = 5000;
        riskOracle.setRiskParameters(preLif, preLcf);
    }

    function boundPreLiquidationParameters(
        PreLiquidationParams memory preLiquidationParams,
        uint256 minPreLltv,
        uint256 maxPreLltv,
        uint256 minPreLCF,
        uint256 maxPreLCF,
        uint256 minPreLIF,
        uint256 maxPreLIF,
        address preLiqOracle
    ) internal pure returns (PreLiquidationParams memory) {
        preLiquidationParams.preLltv = bound(preLiquidationParams.preLltv, minPreLltv, maxPreLltv);
        preLiquidationParams.preLCF1 = bound(preLiquidationParams.preLCF1, minPreLCF, maxPreLCF);
        preLiquidationParams.preLCF2 = bound(preLiquidationParams.preLCF2, preLiquidationParams.preLCF1, maxPreLCF);
        preLiquidationParams.preLIF1 = bound(preLiquidationParams.preLIF1, minPreLIF, maxPreLIF);
        preLiquidationParams.preLIF2 = bound(preLiquidationParams.preLIF2, preLiquidationParams.preLIF1, maxPreLIF);
        preLiquidationParams.preLiquidationOracle = preLiqOracle;

        return preLiquidationParams;
    }

    function _preparePreLiquidation(
        PreLiquidationParams memory preLiquidationParams,
        uint256 collateralAmount,
        uint256 borrowAmount,
        address liquidator
    ) internal {
        preLiquidation = factory.createPreLiquidation(id, preLiquidationParams, address(riskOracle));

        loanToken.mint(SUPPLIER, borrowAmount);
        vm.prank(SUPPLIER);
        if (borrowAmount > 0) {
            MORPHO.supply(marketParams, borrowAmount, 0, SUPPLIER, hex"");
        }

        collateralToken.mint(BORROWER, collateralAmount);
        vm.startPrank(BORROWER);

        MORPHO.supplyCollateral(marketParams, collateralAmount, BORROWER, hex"");

        if (borrowAmount > 0) {
            MORPHO.borrow(marketParams, borrowAmount, 0, BORROWER, BORROWER);
        }
        MORPHO.setAuthorization(address(preLiquidation), true);
        vm.stopPrank();

        loanToken.mint(liquidator, type(uint128).max);
        vm.prank(liquidator);
        loanToken.approve(address(preLiquidation), type(uint256).max);
    }

    function _closeFactor(PreLiquidationParams memory preLiquidationParams, uint256 ltv)
        internal
        view
        returns (uint256)
    {
        (uint256 preLif, uint256 preLcf) = riskOracle.getRiskParameters();
        return preLcf;
        // return (ltv - preLiquidationParams.preLltv).wDivDown(marketParams.lltv - preLiquidationParams.preLltv).wMulDown(
        //     preLiquidationParams.preLCF2 - preLiquidationParams.preLCF1
        // ) + preLiquidationParams.preLCF1;
    }

    function _preLIF(PreLiquidationParams memory preLiquidationParams, uint256 ltv) internal view returns (uint256) {
        (uint256 preLif, uint256 preLcf) = riskOracle.getRiskParameters();
        return preLif;
        // return (ltv - preLiquidationParams.preLltv).wDivDown(marketParams.lltv - preLiquidationParams.preLltv).wMulDown(
        //     preLiquidationParams.preLIF2 - preLiquidationParams.preLIF1
        // ) + preLiquidationParams.preLIF1;
    }

    function _getBorrowBounds(
        PreLiquidationParams memory preLiquidationParams,
        MarketParams memory _marketParams,
        uint256 collateralAmount
    ) internal view returns (uint256, uint256, uint256) {
        uint256 collateralPrice = IOracle(preLiquidationParams.preLiquidationOracle).price();
        uint256 collateralQuoted = collateralAmount.mulDivDown(collateralPrice, ORACLE_PRICE_SCALE);
        uint256 borrowPreLiquidationThreshold = collateralQuoted.wMulDown(preLiquidationParams.preLltv);
        uint256 borrowLiquidationThreshold = collateralQuoted.wMulDown(_marketParams.lltv);

        return (collateralQuoted, borrowPreLiquidationThreshold, borrowLiquidationThreshold);
    }
}
