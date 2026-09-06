// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {EnergyMeter} from "../contracts/source-chain/EnergyMeter.sol";

contract DeployMeter is Script {
    function run() external returns (EnergyMeter meter) {
        vm.startBroadcast();
        meter = new EnergyMeter();
        vm.stopBroadcast();

        console2.log("EnergyMeter", address(meter));
    }
}
