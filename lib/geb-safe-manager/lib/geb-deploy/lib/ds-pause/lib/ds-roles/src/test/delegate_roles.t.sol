// roles.t.sol - test for roles.sol

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

import 'ds-test/test.sol';
import 'ds-auth/auth.sol';
import '../delegate_roles.sol';
import '../roles.sol';

contract authed is DSAuth {
	bool public flag1;
	bool public flag2;
	function cap1() public auth {
		flag1 = true;
	}
	function cap2() public auth {
		flag2 = true;
	}
}

contract User {
    authed target;
    
    constructor (address _target) public {
        target = authed(_target);
    }

    function doCallCap1() public {
        target.cap1();
    }
}

contract DSDelegateRolesTest is DSTest {
	DSDelegateRoles r;
    DSRoles authority;
	address a;
    address self;
    address user;

	function setUp() public {
		r = new DSDelegateRoles();
		a = address(new authed());
        self = address(this);
        user = address(new User(a));
        authority = new DSRoles();

        authed(a).setAuthority(r);
        r.setAuthority(authority);
	}

	function testBasics() public {
		uint8 root_role = 0;
		uint8 admin_role = 1;
		uint8 mod_role = 2;
		uint8 user_role = 3;

		r.setUserRole(user, root_role, true);
		r.setUserRole(user, admin_role, true);

		assertEq32(bytes32(hex"0000000000000000000000000000000000000000000000000000000000000003"), r.getUserRoles(user));

		r.setRoleCapability(admin_role, a, bytes4(keccak256("cap1()")), true);

		assertTrue(r.canCall(user, a, bytes4(keccak256("cap1()"))));
		User(user).doCallCap1();
		assertTrue(authed(a).flag1());
	
		r.setRoleCapability(admin_role, a, bytes4(keccak256("cap1()")), false);

		assertTrue(!r.canCall(user, a, bytes4(keccak256("cap1()"))));

		assertTrue(r.hasUserRole(user, root_role));
		assertTrue(r.hasUserRole(user, admin_role));
		assertTrue(!r.hasUserRole(user, mod_role));
		assertTrue(!r.hasUserRole(user, user_role));
	}

	function testRoot() public {
		assertTrue(!r.isUserRoot(user));
		assertTrue(!r.canCall(user, a, bytes4(keccak256("cap1()"))));

		r.setRootUser(user, true);
		assertTrue(r.isUserRoot(user));
		assertTrue(r.canCall(user, a, bytes4(keccak256("cap1()"))));

		r.setRootUser(user, false);
		assertTrue(!r.isUserRoot(user));
		assertTrue(!r.canCall(user, a, bytes4(keccak256("cap1()"))));
	}

	function testPublicCapabilities() public {
		assertTrue(!r.isCapabilityPublic(a, bytes4(keccak256("cap1()"))));
		assertTrue(!r.canCall(user, a, bytes4(keccak256("cap1()"))));

		r.setPublicCapability(a, bytes4(keccak256("cap1()")), true);
		assertTrue(r.isCapabilityPublic(a, bytes4(keccak256("cap1()"))));
		assertTrue(r.canCall(user, a, bytes4(keccak256("cap1()"))));

		r.setPublicCapability(a, bytes4(keccak256("cap1()")), false);
		assertTrue(!r.isCapabilityPublic(a, bytes4(keccak256("cap1()"))));
		assertTrue(!r.canCall(user, a, bytes4(keccak256("cap1()"))));
	}

    function testFailSetAuthorityToSelf() public {
		r.setAuthority(r);
	}

    function testDelegateBasics() public {
		uint8 root_role = 0;
		uint8 admin_role = 1;
		uint8 mod_role = 2;
		uint8 user_role = 3;

		authority.setUserRole(user, root_role, true);
		authority.setUserRole(user, admin_role, true);

		assertEq32(bytes32(hex"0000000000000000000000000000000000000000000000000000000000000003"), authority.getUserRoles(user));

		authority.setRoleCapability(admin_role, a, bytes4(keccak256("cap1()")), true);

		assertTrue(authority.canCall(user, a, bytes4(keccak256("cap1()"))));
		User(user).doCallCap1();
		assertTrue(authed(a).flag1());
	
		authority.setRoleCapability(admin_role, a, bytes4(keccak256("cap1()")), false);

		assertTrue(!authority.canCall(user, a, bytes4(keccak256("cap1()"))));

		assertTrue(authority.hasUserRole(user, root_role));
		assertTrue(authority.hasUserRole(user, admin_role));
		assertTrue(!authority.hasUserRole(user, mod_role));
		assertTrue(!authority.hasUserRole(user, user_role));
	}

	function testDelegateRoot() public {
		assertTrue(!authority.isUserRoot(user));
		assertTrue(!authority.canCall(user, a, bytes4(keccak256("cap1()"))));

		authority.setRootUser(user, true);
		assertTrue(authority.isUserRoot(user));
		assertTrue(authority.canCall(user, a, bytes4(keccak256("cap1()"))));

		authority.setRootUser(user, false);
		assertTrue(!authority.isUserRoot(user));
		assertTrue(!authority.canCall(user, a, bytes4(keccak256("cap1()"))));
	}

	function testDelegatePublicCapabilities() public {
		assertTrue(!authority.isCapabilityPublic(a, bytes4(keccak256("cap1()"))));
		assertTrue(!authority.canCall(user, a, bytes4(keccak256("cap1()"))));

		authority.setPublicCapability(a, bytes4(keccak256("cap1()")), true);
		assertTrue(authority.isCapabilityPublic(a, bytes4(keccak256("cap1()"))));
		assertTrue(authority.canCall(user, a, bytes4(keccak256("cap1()"))));

		authority.setPublicCapability(a, bytes4(keccak256("cap1()")), false);
		assertTrue(!authority.isCapabilityPublic(a, bytes4(keccak256("cap1()"))));
		assertTrue(!authority.canCall(user, a, bytes4(keccak256("cap1()"))));
	}
}
