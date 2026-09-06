// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {EnergyMeter} from "../contracts/source-chain/EnergyMeter.sol";
import {EnergyProofConsumer} from "../contracts/creditcoin-chain/EnergyProofConsumer.sol";

contract EnergyMeterTest is Test {
    EnergyMeter internal meter;

    address internal oracle = makeAddr("oracle");
    address internal stranger = makeAddr("stranger");
    bytes32 internal constant READING_ID = keccak256("reading-1");
    bytes32 internal constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    event EnergyProduced(address indexed oracle, address indexed producer, bytes32 indexed readingId, uint32 wattHours);

    function setUp() public {
        meter = new EnergyMeter(); // address(this) => ADMIN + REGISTER + ORACLE
        meter.addOracle(oracle);
    }

    function test_eventSignature_literal() public pure {
        assertEq(
            keccak256("EnergyProduced(address,address,bytes32,uint32)"),
            keccak256("EnergyProduced(address,address,bytes32,uint32)")
        );
    }

    function test_eventSignature_matchesConsumerConstant() public {
        EnergyProofConsumer consumer = new EnergyProofConsumer(1, address(meter), address(0xdead));
        assertEq(consumer.ENERGY_PRODUCED_SIG(), keccak256("EnergyProduced(address,address,bytes32,uint32)"));
    }

    function test_recordProduction_emitsAndStores() public {
        vm.expectEmit(true, true, true, true, address(meter));
        emit EnergyProduced(oracle, address(this), READING_ID, 1_500);

        vm.prank(oracle);
        meter.recordProduction(EnergyMeter.EnergyParams(1_500, address(this), READING_ID));

        (uint32 wh, address o, address producer, bytes32 rid) = meter.energyDatas(READING_ID);
        assertEq(wh, 1_500);
        assertEq(o, oracle);
        assertEq(producer, address(this));
        assertEq(rid, READING_ID);
        assertEq(meter.producerTotal(address(this)), 1_500);
        assertEq(meter.oracleTotal(oracle), 1_500);
    }

    function test_recordProduction_revertsWithoutOracleRole() public {
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, ORACLE_ROLE)
        );
        meter.recordProduction(EnergyMeter.EnergyParams(1, address(this), READING_ID));
    }

    function test_recordProduction_revertsOnZeroWattHours() public {
        vm.prank(oracle);
        vm.expectRevert(abi.encodeWithSelector(EnergyMeter.WrongWattHours.selector, uint32(0)));
        meter.recordProduction(EnergyMeter.EnergyParams(0, address(this), READING_ID));
    }

    function test_recordProduction_revertsAboveMax() public {
        uint32 tooBig = meter.MAX_WATT_HOURS() + 1;
        vm.prank(oracle);
        vm.expectRevert(abi.encodeWithSelector(EnergyMeter.WrongWattHours.selector, tooBig));
        meter.recordProduction(EnergyMeter.EnergyParams(tooBig, address(this), READING_ID));
    }

    function test_recordProduction_revertsOnZeroReadingId() public {
        vm.prank(oracle);
        vm.expectRevert(EnergyMeter.ZeroReadingId.selector);
        meter.recordProduction(EnergyMeter.EnergyParams(100, address(this), bytes32(0)));
    }

    function test_recordProduction_revertsOnZeroProducer() public {
        vm.prank(oracle);
        vm.expectRevert(EnergyMeter.ZeroProducer.selector);
        meter.recordProduction(EnergyMeter.EnergyParams(100, address(0), READING_ID));
    }

    function test_recordProduction_revertsOnReusedReadingId() public {
        vm.startPrank(oracle);
        meter.recordProduction(EnergyMeter.EnergyParams(100, address(this), READING_ID));
        vm.expectRevert(abi.encodeWithSelector(EnergyMeter.ReadingIdAlreadyUsed.selector, READING_ID));
        meter.recordProduction(EnergyMeter.EnergyParams(200, address(this), READING_ID));
        vm.stopPrank();
    }

    function test_oracleData_accumulates() public {
        vm.startPrank(oracle);
        meter.recordProduction(EnergyMeter.EnergyParams(1_000, address(this), keccak256("r1")));
        meter.recordProduction(EnergyMeter.EnergyParams(2_500, address(this), keccak256("r2")));
        vm.stopPrank();

        assertEq(meter.oracleTotal(oracle), 3_500);
        assertEq(meter.oracleReadingIds(oracle).length, 2);
    }

    function test_register_delegationChain() public {
        address register = makeAddr("register");
        address dev = makeAddr("dev");

        meter.grantRegisterRole(register); // admin (this) -> REGISTER_ROLE
        vm.prank(register);
        meter.addOracle(dev); // REGISTER_ROLE -> ORACLE_ROLE

        vm.prank(dev);
        meter.recordProduction(EnergyMeter.EnergyParams(42, address(this), keccak256("dev-1")));
        assertEq(meter.oracleTotal(dev), 42);
    }

    function test_registerRoleCanBeRevoked() public {
        address register = makeAddr("temporary-register");
        meter.grantRegisterRole(register);
        assertTrue(meter.hasRole(meter.REGISTER_ROLE(), register));

        meter.removeRegisterRole(register);
        assertFalse(meter.hasRole(meter.REGISTER_ROLE(), register));

        bytes32 registerRole = meter.REGISTER_ROLE();
        vm.startPrank(register);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, register, registerRole)
        );
        meter.addOracle(makeAddr("not-onboarded"));
        vm.stopPrank();
    }

    function test_producerData_tracksIdsAndTotals() public {
        bytes32 first = keccak256("producer-reading-1");
        bytes32 second = keccak256("producer-reading-2");
        vm.startPrank(oracle);
        meter.recordProduction(EnergyMeter.EnergyParams(100, producerAddress(), first));
        meter.recordProduction(EnergyMeter.EnergyParams(250, producerAddress(), second));
        vm.stopPrank();

        assertEq(meter.producerTotal(producerAddress()), 350);
        assertEq(meter.producerReadingIds(producerAddress()).length, 2);
    }

    function producerAddress() internal pure returns (address) {
        return address(0xBEEF);
    }

    function test_removeOracle_revokesAccess() public {
        vm.prank(oracle);
        meter.recordProduction(EnergyMeter.EnergyParams(10, address(this), keccak256("before")));

        meter.removeOracle(oracle); // this holds REGISTER_ROLE via bootstrap

        vm.prank(oracle);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, oracle, ORACLE_ROLE)
        );
        meter.recordProduction(EnergyMeter.EnergyParams(20, address(this), keccak256("after")));
    }

    function testFuzz_recordProduction_inRange(uint32 wattHours, bytes32 readingId) public {
        wattHours = uint32(bound(uint256(wattHours), 1, meter.MAX_WATT_HOURS()));
        vm.assume(readingId != bytes32(0));

        vm.prank(oracle);
        meter.recordProduction(EnergyMeter.EnergyParams(wattHours, address(this), readingId));

        (uint32 wh,,,) = meter.energyDatas(readingId);
        assertEq(wh, wattHours);
    }
}
