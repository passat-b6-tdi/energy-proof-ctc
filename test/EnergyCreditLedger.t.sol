// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {EnergyCreditLedger} from "../contracts/creditcoin-chain/EnergyCreditLedger.sol";
import {IEnergyCreditLedger} from "../contracts/interfaces/IEnergyCreditLedger.sol";

contract EnergyCreditLedgerTest is Test {
    EnergyCreditLedger internal ledger;

    address internal deployer = address(this);
    address internal consumer = makeAddr("consumer");
    address internal producer = makeAddr("producer");
    address internal stranger = makeAddr("stranger");

    bytes32 internal constant READING_ID = keccak256("reading-1");
    bytes32 internal constant QUERY_ID = keccak256("query-1");

    event SettlementRecorded(
        address indexed producer,
        uint256 wattHours,
        bytes32 indexed readingId,
        bytes32 indexed queryId,
        uint256 newBalance
    );

    function setUp() public {
        ledger = new EnergyCreditLedger();
        ledger.grantRole(ledger.CONSUMER_ROLE(), consumer);
    }

    function test_credit_onlyConsumer() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, ledger.CONSUMER_ROLE()
            )
        );
        vm.prank(stranger);
        ledger.credit(producer, 100, READING_ID, QUERY_ID, 1, 100);
    }

    function test_credit_happyPath() public {
        vm.expectEmit(true, true, true, true, address(ledger));
        emit SettlementRecorded(producer, 1_500, READING_ID, QUERY_ID, 1_500);

        vm.prank(consumer);
        ledger.credit(producer, 1_500, READING_ID, QUERY_ID, 1, 100);

        assertEq(ledger.balanceOf(producer), 1_500);
        assertEq(ledger.totalCredited(), 1_500);
        assertTrue(ledger.settled(READING_ID));
        IEnergyCreditLedger.Settlement memory settlement = ledger.settlementOf(READING_ID);
        assertEq(settlement.producer, producer);
        assertEq(settlement.wattHours, 1_500);
        assertEq(settlement.queryId, QUERY_ID);
        assertEq(settlement.sourceChainKey, 1);
        assertEq(settlement.sourceBlockHeight, 100);
    }

    function test_credit_rejectsReplayOfReadingId() public {
        vm.prank(consumer);
        ledger.credit(producer, 1_500, READING_ID, QUERY_ID, 1, 100);

        vm.prank(consumer);
        vm.expectRevert(abi.encodeWithSelector(EnergyCreditLedger.ReadingAlreadySettled.selector, READING_ID));
        ledger.credit(producer, 1, READING_ID, keccak256("query-2"), 1, 101);
    }

    function test_credit_rejectsZeroProducer() public {
        vm.prank(consumer);
        vm.expectRevert(EnergyCreditLedger.ZeroProducer.selector);
        ledger.credit(address(0), 1_500, READING_ID, QUERY_ID, 1, 100);
    }

    function test_credit_rejectsZeroReadingId() public {
        vm.prank(consumer);
        vm.expectRevert(EnergyCreditLedger.ZeroReadingId.selector);
        ledger.credit(producer, 1_500, bytes32(0), QUERY_ID, 1, 100);
    }

    function test_credit_rejectsZeroQueryId() public {
        vm.prank(consumer);
        vm.expectRevert(EnergyCreditLedger.ZeroQueryId.selector);
        ledger.credit(producer, 1_500, READING_ID, bytes32(0), 1, 100);
    }

    function test_credit_rejectsZeroWattHours() public {
        vm.prank(consumer);
        vm.expectRevert(EnergyCreditLedger.ZeroWattHours.selector);
        ledger.credit(producer, 0, READING_ID, QUERY_ID, 1, 100);
    }

    function test_onlyAdminCanGrantConsumerRole() public {
        bytes32 consumerRole = ledger.CONSUMER_ROLE();
        bytes32 adminRole = ledger.DEFAULT_ADMIN_ROLE();
        vm.startPrank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, adminRole)
        );
        ledger.grantRole(consumerRole, stranger);
        vm.stopPrank();
    }

    function test_credit_accumulatesAcrossReadings() public {
        vm.startPrank(consumer);
        ledger.credit(producer, 1_000, keccak256("r1"), keccak256("q1"), 1, 100);
        ledger.credit(producer, 2_500, keccak256("r2"), keccak256("q2"), 1, 101);
        vm.stopPrank();

        assertEq(ledger.balanceOf(producer), 3_500);
        assertEq(ledger.totalCredited(), 3_500);
    }

    function testFuzz_credit_preservesBalanceAndTotal(uint256 wattHours, bytes32 readingId, bytes32 queryId) public {
        wattHours = bound(wattHours, 1, type(uint128).max);
        vm.assume(readingId != bytes32(0));
        vm.assume(queryId != bytes32(0));

        vm.prank(consumer);
        ledger.credit(producer, wattHours, readingId, queryId, 77, 999);

        assertEq(ledger.balanceOf(producer), wattHours);
        assertEq(ledger.totalCredited(), wattHours);
        assertTrue(ledger.settled(readingId));
        IEnergyCreditLedger.Settlement memory settlement = ledger.settlementOf(readingId);
        assertEq(settlement.producer, producer);
        assertEq(settlement.wattHours, wattHours);
        assertEq(settlement.queryId, queryId);
        assertEq(settlement.sourceChainKey, 77);
        assertEq(settlement.sourceBlockHeight, 999);
    }
}
