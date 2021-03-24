/// value.sol - a value is a simple thing, it can be get and set

// Copyright (C) 2017  DappHub, LLC

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity >=0.4.23;

import 'ds-thing/thing.sol';

contract DSValue is DSThing {
    bool    isValid;
    uint256 medianPrice;
    address public priceSource;

    // --- Events ---
    event UpdateResult(uint256 newMedian, uint256 lastUpdateTime);
    event RestartValue();

    function getResultWithValidity() public view returns (uint256, bool) {
        return (medianPrice,isValid);
    }
    function read() public view returns (uint256) {
        uint256 value; bool valid;
        (value, valid) = getResultWithValidity();
        require(valid, "not-valid");
        return value;
    }
    function updateResult(uint256 newMedian) public auth {
        medianPrice = newMedian;
        isValid = true;
        emit UpdateResult(newMedian, now);
    }
    function restartValue() public auth {  // unset the value
        isValid = false;
        emit RestartValue();
    }
}
