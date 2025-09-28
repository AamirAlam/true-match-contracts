// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {ReputationSBT} from "../src/ReputationSBT.sol";
import {TrueMatchProtocol} from "../src/TrueMatchProtocol.sol";

contract Deploy is Script {
    function run() external {
        // Load env
        address token    = vm.envAddress("TOKEN");
        address treasury = vm.envAddress("TREASURY");

        // Remove manual gas price setting to let 0G chain handle it automatically
        
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        // 1) Deploy SBT (removed CREATE2 to fix ownership issue)
        ReputationSBT sbt = new ReputationSBT();

        // 2) Deploy protocol (token, treasury, sbt)
        TrueMatchProtocol love = new TrueMatchProtocol(token, treasury, address(sbt));

        // 3) Give protocol control over SBT tier updates
        sbt.transferOwnership(address(love));

        vm.stopBroadcast();

        console2.log("SBT:           %s", address(sbt));
        console2.log("TrueMatchProtocol:  %s", address(love));
        console2.log("Treasury:      %s", treasury);
        console2.log("Token:         %s", token);
    }
}
