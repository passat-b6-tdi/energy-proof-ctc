// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {EnergyCreditLedger} from "../contracts/creditcoin-chain/EnergyCreditLedger.sol";
import {EnergyProofConsumer} from "../contracts/creditcoin-chain/EnergyProofConsumer.sol";

contract DeployCreditcoin is Script {
    function run() external returns (EnergyCreditLedger ledger, EnergyProofConsumer consumer) {
        uint64 sourceChainKey = uint64(vm.envUint("SOURCE_CHAIN_KEY"));
        address energyMeter = vm.envAddress("ENERGY_METER_ADDRESS");

        vm.startBroadcast();
        ledger = new EnergyCreditLedger();
        consumer = new EnergyProofConsumer(sourceChainKey, energyMeter, address(ledger));
        ledger.grantRole(ledger.CONSUMER_ROLE(), address(consumer));
        vm.stopBroadcast();

        require(ledger.hasRole(ledger.CONSUMER_ROLE(), address(consumer)), "consumer wiring failed");
        require(consumer.sourceChainKey() == sourceChainKey, "source chain key mismatch");
        require(consumer.energyMeter() == energyMeter, "meter address mismatch");

        console2.log("EnergyCreditLedger", address(ledger));
        console2.log("EnergyProofConsumer", address(consumer));
    }
}
