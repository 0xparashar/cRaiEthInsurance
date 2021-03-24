// Copyright (C) 2018-2020 Maker Ecosystem Growth Holdings, INC.

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity 0.6.7;

import "./GebSafeManager.sol";

contract GetSafes {
    function getSafesAsc(address manager, address guy) external view returns (uint[] memory ids, address[] memory safes, bytes32[] memory collateralTypes) {
        uint count = GebSafeManager(manager).safeCount(guy);
        ids = new uint[](count);
        safes = new address[](count);
        collateralTypes = new bytes32[](count);
        uint i = 0;
        uint id = GebSafeManager(manager).firstSAFEID(guy);

        while (id > 0) {
            ids[i] = id;
            safes[i] = GebSafeManager(manager).safes(id);
            collateralTypes[i] = GebSafeManager(manager).collateralTypes(id);
            (,id) = GebSafeManager(manager).safeList(id);
            i++;
        }
    }

    function getSafesDesc(address manager, address guy) external view returns (uint[] memory ids, address[] memory safes, bytes32[] memory collateralTypes) {
        uint count = GebSafeManager(manager).safeCount(guy);
        ids = new uint[](count);
        safes = new address[](count);
        collateralTypes = new bytes32[](count);
        uint i = 0;
        uint id = GebSafeManager(manager).lastSAFEID(guy);

        while (id > 0) {
            ids[i] = id;
            safes[i] = GebSafeManager(manager).safes(id);
            collateralTypes[i] = GebSafeManager(manager).collateralTypes(id);
            (id,) = GebSafeManager(manager).safeList(id);
            i++;
        }
    }
}
