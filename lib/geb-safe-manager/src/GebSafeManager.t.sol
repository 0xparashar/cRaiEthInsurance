pragma solidity 0.6.7;

import { GebDeployTestBase, SAFEEngine, DSToken } from "geb-deploy/test/GebDeploy.t.base.sol";
import "./GetSafes.sol";

contract FakeUser {
    function doSafeAllow(
        GebSafeManager manager,
        uint safe,
        address usr,
        uint ok
    ) public {
        manager.allowSAFE(safe, usr, ok);
    }

    function doHandlerAllow(
        GebSafeManager manager,
        address usr,
        uint ok
    ) public {
        manager.allowHandler(usr, ok);
    }

    function doTransferSAFEOwnership(
        GebSafeManager manager,
        uint safe,
        address dst
    ) public {
        manager.transferSAFEOwnership(safe, dst);
    }

    function doModifySAFECollateralization(
        GebSafeManager manager,
        uint safe,
        int deltaCollateral,
        int deltaDebt
    ) public {
        manager.modifySAFECollateralization(safe, deltaCollateral, deltaDebt);
    }

    function doApproveSAFEModification(
        SAFEEngine safeEngine,
        address usr
    ) public {
        safeEngine.approveSAFEModification(usr);
    }

    function doSAFEEngineMOdifySAFECollateralization(
        SAFEEngine safeEngine,
        bytes32 collateralType,
        address safe,
        address collateralSource,
        address debtDst,
        int deltaCollateral,
        int deltaDebt
    ) public {
        safeEngine.modifySAFECollateralization(collateralType, safe, collateralSource, debtDst, deltaCollateral, deltaDebt);
    }

    function doProtectSAFE(
        GebSafeManager manager,
        uint safe,
        address liquidationEngine,
        address saviour
    ) public {
        manager.protectSAFE(safe, liquidationEngine, saviour);
    }
}

contract LiquidationEngineMock {
    mapping(bytes32 => mapping(address => address)) public chosenSAFESaviour;

    function protectSAFE(bytes32 collateralType, address safe, address saviour) external {
        chosenSAFESaviour[collateralType][safe] = saviour;
    }
}

contract GebSafeManagerTest is GebDeployTestBase {
    GebSafeManager manager;
    LiquidationEngineMock liquidationEngineMock;
    GetSafes   getSafes;
    FakeUser  user;

    DSToken   tkn1;
    DSToken   tkn2;

    bytes32 collateralAuctionType = bytes32("ENGLISH");

    function setUp() override public {
        super.setUp();
        deployIndex(collateralAuctionType);
        manager = new GebSafeManager(address(safeEngine));
        liquidationEngineMock = new LiquidationEngineMock();
        getSafes = new GetSafes();
        user = new FakeUser();
    }

    function testOpenSAFE() public {
        uint safe = manager.openSAFE("ETH", address(this));
        assertEq(safe, 1);
        assertEq(safeEngine.safeRights(address(bytes20(manager.safes(safe))), address(manager)), 1);
        assertEq(manager.ownsSAFE(safe), address(this));
    }

    function testOpenSAFEOtherAddress() public {
        uint safe = manager.openSAFE("ETH", address(123));
        assertEq(manager.ownsSAFE(safe), address(123));
    }

    function testFailOpenSAFEZeroAddress() public {
        manager.openSAFE("ETH", address(0));
    }

    function testGiveSAFE() public {
        uint safe = manager.openSAFE("ETH", address(this));
        manager.transferSAFEOwnership(safe, address(123));
        assertEq(manager.ownsSAFE(safe), address(123));
    }

    function testAllowAllowed() public {
        uint safe = manager.openSAFE("ETH", address(this));
        manager.allowSAFE(safe, address(user), 1);
        user.doSafeAllow(manager, safe, address(123), 1);
        assertEq(manager.safeCan(address(this), safe, address(123)), 1);
    }

    function testFailAllowNotAllowed() public {
        uint safe = manager.openSAFE("ETH", address(this));
        user.doSafeAllow(manager, safe, address(123), 1);
    }

    function testGiveAllowed() public {
        uint safe = manager.openSAFE("ETH", address(this));
        manager.allowSAFE(safe, address(user), 1);
        user.doTransferSAFEOwnership(manager, safe, address(123));
        assertEq(manager.ownsSAFE(safe), address(123));
    }

    function testFailGiveNotAllowed() public {
        uint safe = manager.openSAFE("ETH", address(this));
        user.doTransferSAFEOwnership(manager, safe, address(123));
    }

    function testFailGiveNotAllowed2() public {
        uint safe = manager.openSAFE("ETH", address(this));
        manager.allowSAFE(safe, address(user), 1);
        manager.allowSAFE(safe, address(user), 0);
        user.doTransferSAFEOwnership(manager, safe, address(123));
    }

    function testFailGiveNotAllowed3() public {
        uint safe = manager.openSAFE("ETH", address(this));
        uint safe2 = manager.openSAFE("ETH", address(this));
        manager.allowSAFE(safe2, address(user), 1);
        user.doTransferSAFEOwnership(manager, safe, address(123));
    }

    function testFailGiveToZeroAddress() public {
        uint safe = manager.openSAFE("ETH", address(this));
        manager.transferSAFEOwnership(safe, address(0));
    }

    function testFailGiveToSameOwner() public {
        uint safe = manager.openSAFE("ETH", address(this));
        manager.transferSAFEOwnership(safe, address(this));
    }

    function testDoubleLinkedList() public {
        uint safe1 = manager.openSAFE("ETH", address(this));
        uint safe2 = manager.openSAFE("ETH", address(this));
        uint safe3 = manager.openSAFE("ETH", address(this));

        uint safe4 = manager.openSAFE("ETH", address(user));
        uint safe5 = manager.openSAFE("ETH", address(user));
        uint safe6 = manager.openSAFE("ETH", address(user));
        uint safe7 = manager.openSAFE("ETH", address(user));

        assertEq(manager.safeCount(address(this)), 3);
        assertEq(manager.firstSAFEID(address(this)), safe1);
        assertEq(manager.lastSAFEID(address(this)), safe3);
        (uint prev, uint next) = manager.safeList(safe1);
        assertEq(prev, 0);
        assertEq(next, safe2);
        (prev, next) = manager.safeList(safe2);
        assertEq(prev, safe1);
        assertEq(next, safe3);
        (prev, next) = manager.safeList(safe3);
        assertEq(prev, safe2);
        assertEq(next, 0);

        assertEq(manager.safeCount(address(user)), 4);
        assertEq(manager.firstSAFEID(address(user)), safe4);
        assertEq(manager.lastSAFEID(address(user)), safe7);
        (prev, next) = manager.safeList(safe4);
        assertEq(prev, 0);
        assertEq(next, safe5);
        (prev, next) = manager.safeList(safe5);
        assertEq(prev, safe4);
        assertEq(next, safe6);
        (prev, next) = manager.safeList(safe6);
        assertEq(prev, safe5);
        assertEq(next, safe7);
        (prev, next) = manager.safeList(safe7);
        assertEq(prev, safe6);
        assertEq(next, 0);

        manager.transferSAFEOwnership(safe2, address(user));

        assertEq(manager.safeCount(address(this)), 2);
        assertEq(manager.firstSAFEID(address(this)), safe1);
        assertEq(manager.lastSAFEID(address(this)), safe3);
        (prev, next) = manager.safeList(safe1);
        assertEq(next, safe3);
        (prev, next) = manager.safeList(safe3);
        assertEq(prev, safe1);

        assertEq(manager.safeCount(address(user)), 5);
        assertEq(manager.firstSAFEID(address(user)), safe4);
        assertEq(manager.lastSAFEID(address(user)), safe2);
        (prev, next) = manager.safeList(safe7);
        assertEq(next, safe2);
        (prev, next) = manager.safeList(safe2);
        assertEq(prev, safe7);
        assertEq(next, 0);

        user.doTransferSAFEOwnership(manager, safe2, address(this));

        assertEq(manager.safeCount(address(this)), 3);
        assertEq(manager.firstSAFEID(address(this)), safe1);
        assertEq(manager.lastSAFEID(address(this)), safe2);
        (prev, next) = manager.safeList(safe3);
        assertEq(next, safe2);
        (prev, next) = manager.safeList(safe2);
        assertEq(prev, safe3);
        assertEq(next, 0);

        assertEq(manager.safeCount(address(user)), 4);
        assertEq(manager.firstSAFEID(address(user)), safe4);
        assertEq(manager.lastSAFEID(address(user)), safe7);
        (prev, next) = manager.safeList(safe7);
        assertEq(next, 0);

        manager.transferSAFEOwnership(safe1, address(user));
        assertEq(manager.safeCount(address(this)), 2);
        assertEq(manager.firstSAFEID(address(this)), safe3);
        assertEq(manager.lastSAFEID(address(this)), safe2);

        manager.transferSAFEOwnership(safe2, address(user));
        assertEq(manager.safeCount(address(this)), 1);
        assertEq(manager.firstSAFEID(address(this)), safe3);
        assertEq(manager.lastSAFEID(address(this)), safe3);

        manager.transferSAFEOwnership(safe3, address(user));
        assertEq(manager.safeCount(address(this)), 0);
        assertEq(manager.firstSAFEID(address(this)), 0);
        assertEq(manager.lastSAFEID(address(this)), 0);
    }

    function testGetSafesAsc() public {
        uint safe1 = manager.openSAFE("ETH", address(this));
        uint safe2 = manager.openSAFE("REP", address(this));
        uint safe3 = manager.openSAFE("GOLD", address(this));

        (uint[] memory ids,, bytes32[] memory collateralTypes) = getSafes.getSafesAsc(address(manager), address(this));
        assertEq(ids.length, 3);
        assertEq(ids[0], safe1);
        assertEq32(collateralTypes[0], bytes32("ETH"));
        assertEq(ids[1], safe2);
        assertEq32(collateralTypes[1], bytes32("REP"));
        assertEq(ids[2], safe3);
        assertEq32(collateralTypes[2], bytes32("GOLD"));

        manager.transferSAFEOwnership(safe2, address(user));
        (ids,, collateralTypes) = getSafes.getSafesAsc(address(manager), address(this));
        assertEq(ids.length, 2);
        assertEq(ids[0], safe1);
        assertEq32(collateralTypes[0], bytes32("ETH"));
        assertEq(ids[1], safe3);
        assertEq32(collateralTypes[1], bytes32("GOLD"));
    }

    function testGetSafesDesc() public {
        uint safe1 = manager.openSAFE("ETH", address(this));
        uint safe2 = manager.openSAFE("REP", address(this));
        uint safe3 = manager.openSAFE("GOLD", address(this));

        (uint[] memory ids,, bytes32[] memory collateralTypes) = getSafes.getSafesDesc(address(manager), address(this));
        assertEq(ids.length, 3);
        assertEq(ids[0], safe3);
        assertTrue(collateralTypes[0] == bytes32("GOLD"));
        assertEq(ids[1], safe2);
        assertTrue(collateralTypes[1] == bytes32("REP"));
        assertEq(ids[2], safe1);
        assertTrue(collateralTypes[2] == bytes32("ETH"));

        manager.transferSAFEOwnership(safe2, address(user));
        (ids,, collateralTypes) = getSafes.getSafesDesc(address(manager), address(this));
        assertEq(ids.length, 2);
        assertEq(ids[0], safe3);
        assertTrue(collateralTypes[0] == bytes32("GOLD"));
        assertEq(ids[1], safe1);
        assertTrue(collateralTypes[1] == bytes32("ETH"));
    }

    function testModifySAFECollateralization() public {
        uint safe = manager.openSAFE("ETH", address(this));
        weth.deposit{value: 1 ether}();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(manager.safes(safe), 1 ether);
        manager.modifySAFECollateralization(safe, 1 ether, 50 ether);
        assertEq(safeEngine.coinBalance(manager.safes(safe)), 50 ether * ONE);
        assertEq(safeEngine.coinBalance(address(this)), 0);
        manager.transferInternalCoins(safe, address(this), 50 ether * ONE);
        assertEq(safeEngine.coinBalance(manager.safes(safe)), 0);
        assertEq(safeEngine.coinBalance(address(this)), 50 ether * ONE);
        assertEq(coin.balanceOf(address(this)), 0);
        safeEngine.approveSAFEModification(address(coinJoin));
        coinJoin.exit(address(this), 50 ether);
        assertEq(coin.balanceOf(address(this)), 50 ether);
    }

    function testModifySAFECollateralizationAllowed() public {
        uint safe = manager.openSAFE("ETH", address(this));
        weth.deposit{value: 1 ether}();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(manager.safes(safe), 1 ether);
        manager.allowSAFE(safe, address(user), 1);
        user.doModifySAFECollateralization(manager, safe, 1 ether, 50 ether);
        assertEq(safeEngine.coinBalance(manager.safes(safe)), 50 ether * ONE);
    }

    function testFailModifySAFECollateralizationNotAllowed() public {
        uint safe = manager.openSAFE("ETH", address(this));
        weth.deposit{value: 1 ether}();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(manager.safes(safe), 1 ether);
        user.doModifySAFECollateralization(manager, safe, 1 ether, 50 ether);
    }

    function testModifySAFECollateralizationGetCollateralBack() public {
        uint safe = manager.openSAFE("ETH", address(this));
        weth.deposit{value: 1 ether}();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(manager.safes(safe), 1 ether);
        manager.modifySAFECollateralization(safe, 1 ether, 50 ether);
        manager.modifySAFECollateralization(safe, -int(1 ether), -int(50 ether));
        assertEq(safeEngine.coinBalance(address(this)), 0);
        assertEq(safeEngine.tokenCollateral("ETH", manager.safes(safe)), 1 ether);
        assertEq(safeEngine.tokenCollateral("ETH", address(this)), 0);
        manager.transferCollateral(safe, address(this), 1 ether);
        assertEq(safeEngine.tokenCollateral("ETH", manager.safes(safe)), 0);
        assertEq(safeEngine.tokenCollateral("ETH", address(this)), 1 ether);
        uint prevBalance = address(this).balance;
        ethJoin.exit(address(this), 1 ether);
        weth.withdraw(1 ether);
        assertEq(address(this).balance, prevBalance + 1 ether);
    }

    function testGetWrongCollateralBack() public {
        uint safe = manager.openSAFE("ETH", address(this));
        col.mint(1 ether);
        col.approve(address(colJoin), 1 ether);
        colJoin.join(manager.safes(safe), 1 ether);
        assertEq(safeEngine.tokenCollateral("COL", manager.safes(safe)), 1 ether);
        assertEq(safeEngine.tokenCollateral("COL", address(this)), 0);
        manager.transferCollateral("COL", safe, address(this), 1 ether);
        assertEq(safeEngine.tokenCollateral("COL", manager.safes(safe)), 0);
        assertEq(safeEngine.tokenCollateral("COL", address(this)), 1 ether);
    }

    function testQuit() public {
        uint safe = manager.openSAFE("ETH", address(this));
        weth.deposit{value: 1 ether}();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(manager.safes(safe), 1 ether);
        manager.modifySAFECollateralization(safe, 1 ether, 50 ether);

        (uint collateralType, uint art) = safeEngine.safes("ETH", manager.safes(safe));
        assertEq(collateralType, 1 ether);
        assertEq(art, 50 ether);
        (collateralType, art) = safeEngine.safes("ETH", address(this));
        assertEq(collateralType, 0);
        assertEq(art, 0);

        safeEngine.approveSAFEModification(address(manager));
        manager.quitSystem(safe, address(this));
        (collateralType, art) = safeEngine.safes("ETH", manager.safes(safe));
        assertEq(collateralType, 0);
        assertEq(art, 0);
        (collateralType, art) = safeEngine.safes("ETH", address(this));
        assertEq(collateralType, 1 ether);
        assertEq(art, 50 ether);
    }

    function testQuitOtherDst() public {
        uint safe = manager.openSAFE("ETH", address(this));
        weth.deposit{value: 1 ether}();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(manager.safes(safe), 1 ether);
        manager.modifySAFECollateralization(safe, 1 ether, 50 ether);

        (uint collateralType, uint art) = safeEngine.safes("ETH", manager.safes(safe));
        assertEq(collateralType, 1 ether);
        assertEq(art, 50 ether);
        (collateralType, art) = safeEngine.safes("ETH", address(this));
        assertEq(collateralType, 0);
        assertEq(art, 0);

        user.doApproveSAFEModification(safeEngine, address(manager));
        user.doHandlerAllow(manager, address(this), 1);
        manager.quitSystem(safe, address(user));
        (collateralType, art) = safeEngine.safes("ETH", manager.safes(safe));
        assertEq(collateralType, 0);
        assertEq(art, 0);
        (collateralType, art) = safeEngine.safes("ETH", address(user));
        assertEq(collateralType, 1 ether);
        assertEq(art, 50 ether);
    }

    function testFailQuitOtherDst() public {
        uint safe = manager.openSAFE("ETH", address(this));
        weth.deposit{value: 1 ether}();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(manager.safes(safe), 1 ether);
        manager.modifySAFECollateralization(safe, 1 ether, 50 ether);

        (uint collateralType, uint art) = safeEngine.safes("ETH", manager.safes(safe));
        assertEq(collateralType, 1 ether);
        assertEq(art, 50 ether);
        (collateralType, art) = safeEngine.safes("ETH", address(this));
        assertEq(collateralType, 0);
        assertEq(art, 0);

        user.doApproveSAFEModification(safeEngine, address(manager));
        manager.quitSystem(safe, address(user));
    }

    function testEnter() public {
        weth.deposit{value: 1 ether}();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(address(this), 1 ether);
        safeEngine.modifySAFECollateralization("ETH", address(this), address(this), address(this), 1 ether, 50 ether);
        uint safe = manager.openSAFE("ETH", address(this));

        (uint collateralType, uint art) = safeEngine.safes("ETH", manager.safes(safe));
        assertEq(collateralType, 0);
        assertEq(art, 0);

        (collateralType, art) = safeEngine.safes("ETH", address(this));
        assertEq(collateralType, 1 ether);
        assertEq(art, 50 ether);

        safeEngine.approveSAFEModification(address(manager));
        manager.enterSystem(address(this), safe);

        (collateralType, art) = safeEngine.safes("ETH", manager.safes(safe));
        assertEq(collateralType, 1 ether);
        assertEq(art, 50 ether);

        (collateralType, art) = safeEngine.safes("ETH", address(this));
        assertEq(collateralType, 0);
        assertEq(art, 0);
    }

    function testEnterOtherSrc() public {
        weth.deposit{value: 1 ether}();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(address(user), 1 ether);
        user.doSAFEEngineMOdifySAFECollateralization(safeEngine, "ETH", address(user), address(user), address(user), 1 ether, 50 ether);

        uint safe = manager.openSAFE("ETH", address(this));

        (uint collateralType, uint art) = safeEngine.safes("ETH", manager.safes(safe));
        assertEq(collateralType, 0);
        assertEq(art, 0);

        (collateralType, art) = safeEngine.safes("ETH", address(user));
        assertEq(collateralType, 1 ether);
        assertEq(art, 50 ether);

        user.doApproveSAFEModification(safeEngine, address(manager));
        user.doHandlerAllow(manager, address(this), 1);
        manager.enterSystem(address(user), safe);

        (collateralType, art) = safeEngine.safes("ETH", manager.safes(safe));
        assertEq(collateralType, 1 ether);
        assertEq(art, 50 ether);

        (collateralType, art) = safeEngine.safes("ETH", address(user));
        assertEq(collateralType, 0);
        assertEq(art, 0);
    }

    function testFailEnterOtherSrc() public {
        weth.deposit{value: 1 ether}();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(address(user), 1 ether);
        user.doSAFEEngineMOdifySAFECollateralization(safeEngine, "ETH", address(user), address(user), address(user), 1 ether, 50 ether);

        uint safe = manager.openSAFE("ETH", address(this));

        user.doApproveSAFEModification(safeEngine, address(manager));
        manager.enterSystem(address(user), safe);
    }

    function testFailEnterOtherSrc2() public {
        weth.deposit{value: 1 ether}();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(address(user), 1 ether);
        user.doSAFEEngineMOdifySAFECollateralization(safeEngine, "ETH", address(user), address(user), address(user), 1 ether, 50 ether);

        uint safe = manager.openSAFE("ETH", address(this));

        user.doHandlerAllow(manager, address(this), 1);
        manager.enterSystem(address(user), safe);
    }

    function testEnterOtherSafe() public {
        weth.deposit{value: 1 ether}();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(address(this), 1 ether);
        safeEngine.modifySAFECollateralization("ETH", address(this), address(this), address(this), 1 ether, 50 ether);
        uint safe = manager.openSAFE("ETH", address(this));
        manager.transferSAFEOwnership(safe, address(user));

        (uint collateralType, uint art) = safeEngine.safes("ETH", manager.safes(safe));
        assertEq(collateralType, 0);
        assertEq(art, 0);

        (collateralType, art) = safeEngine.safes("ETH", address(this));
        assertEq(collateralType, 1 ether);
        assertEq(art, 50 ether);

        safeEngine.approveSAFEModification(address(manager));
        user.doSafeAllow(manager, safe, address(this), 1);
        manager.enterSystem(address(this), safe);

        (collateralType, art) = safeEngine.safes("ETH", manager.safes(safe));
        assertEq(collateralType, 1 ether);
        assertEq(art, 50 ether);

        (collateralType, art) = safeEngine.safes("ETH", address(this));
        assertEq(collateralType, 0);
        assertEq(art, 0);
    }

    function testFailEnterOtherSafe() public {
        weth.deposit{value: 1 ether}();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(address(this), 1 ether);
        safeEngine.modifySAFECollateralization("ETH", address(this), address(this), address(this), 1 ether, 50 ether);
        uint safe = manager.openSAFE("ETH", address(this));
        manager.transferSAFEOwnership(safe, address(user));

        safeEngine.approveSAFEModification(address(manager));
        manager.enterSystem(address(this), safe);
    }

    function testFailEnterOtherSafe2() public {
        weth.deposit{value: 1 ether}();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(address(this), 1 ether);
        safeEngine.modifySAFECollateralization("ETH", address(this), address(this), address(this), 1 ether, 50 ether);
        uint safe = manager.openSAFE("ETH", address(this));
        manager.transferSAFEOwnership(safe, address(user));

        user.doSafeAllow(manager, safe, address(this), 1);
        manager.enterSystem(address(this), safe);
    }

    function testMove() public {
        weth.deposit{value: 1 ether}();
        weth.approve(address(ethJoin), 1 ether);
        uint safeSrc = manager.openSAFE("ETH", address(this));
        ethJoin.join(address(manager.safes(safeSrc)), 1 ether);
        manager.modifySAFECollateralization(safeSrc, 1 ether, 50 ether);
        uint safeDst = manager.openSAFE("ETH", address(this));

        (uint collateralType, uint art) = safeEngine.safes("ETH", manager.safes(safeDst));
        assertEq(collateralType, 0);
        assertEq(art, 0);

        (collateralType, art) = safeEngine.safes("ETH", manager.safes(safeSrc));
        assertEq(collateralType, 1 ether);
        assertEq(art, 50 ether);

        manager.moveSAFE(safeSrc, safeDst);

        (collateralType, art) = safeEngine.safes("ETH", manager.safes(safeDst));
        assertEq(collateralType, 1 ether);
        assertEq(art, 50 ether);

        (collateralType, art) = safeEngine.safes("ETH", manager.safes(safeSrc));
        assertEq(collateralType, 0);
        assertEq(art, 0);
    }

    function testMoveOtherSafeDst() public {
        weth.deposit{value: 1 ether}();
        weth.approve(address(ethJoin), 1 ether);
        uint safeSrc = manager.openSAFE("ETH", address(this));
        ethJoin.join(address(manager.safes(safeSrc)), 1 ether);
        manager.modifySAFECollateralization(safeSrc, 1 ether, 50 ether);
        uint safeDst = manager.openSAFE("ETH", address(this));
        manager.transferSAFEOwnership(safeDst, address(user));

        (uint collateralType, uint art) = safeEngine.safes("ETH", manager.safes(safeDst));
        assertEq(collateralType, 0);
        assertEq(art, 0);

        (collateralType, art) = safeEngine.safes("ETH", manager.safes(safeSrc));
        assertEq(collateralType, 1 ether);
        assertEq(art, 50 ether);

        user.doSafeAllow(manager, safeDst, address(this), 1);
        manager.moveSAFE(safeSrc, safeDst);

        (collateralType, art) = safeEngine.safes("ETH", manager.safes(safeDst));
        assertEq(collateralType, 1 ether);
        assertEq(art, 50 ether);

        (collateralType, art) = safeEngine.safes("ETH", manager.safes(safeSrc));
        assertEq(collateralType, 0);
        assertEq(art, 0);
    }

    function testFailMoveOtherSafeDst() public {
        weth.deposit{value: 1 ether}();
        weth.approve(address(ethJoin), 1 ether);
        uint safeSrc = manager.openSAFE("ETH", address(this));
        ethJoin.join(address(manager.safes(safeSrc)), 1 ether);
        manager.modifySAFECollateralization(safeSrc, 1 ether, 50 ether);
        uint safeDst = manager.openSAFE("ETH", address(this));
        manager.transferSAFEOwnership(safeDst, address(user));

        manager.moveSAFE(safeSrc, safeDst);
    }

    function testMoveOtherSafeSrc() public {
        weth.deposit{value: 1 ether}();
        weth.approve(address(ethJoin), 1 ether);
        uint safeSrc = manager.openSAFE("ETH", address(this));
        ethJoin.join(address(manager.safes(safeSrc)), 1 ether);
        manager.modifySAFECollateralization(safeSrc, 1 ether, 50 ether);
        uint safeDst = manager.openSAFE("ETH", address(this));
        manager.transferSAFEOwnership(safeSrc, address(user));

        (uint collateralType, uint art) = safeEngine.safes("ETH", manager.safes(safeDst));
        assertEq(collateralType, 0);
        assertEq(art, 0);

        (collateralType, art) = safeEngine.safes("ETH", manager.safes(safeSrc));
        assertEq(collateralType, 1 ether);
        assertEq(art, 50 ether);

        user.doSafeAllow(manager, safeSrc, address(this), 1);
        manager.moveSAFE(safeSrc, safeDst);

        (collateralType, art) = safeEngine.safes("ETH", manager.safes(safeDst));
        assertEq(collateralType, 1 ether);
        assertEq(art, 50 ether);

        (collateralType, art) = safeEngine.safes("ETH", manager.safes(safeSrc));
        assertEq(collateralType, 0);
        assertEq(art, 0);
    }

    function testFailMoveOtherSafeSrc() public {
        weth.deposit{value: 1 ether}();
        weth.approve(address(ethJoin), 1 ether);
        uint safeSrc = manager.openSAFE("ETH", address(this));
        ethJoin.join(address(manager.safes(safeSrc)), 1 ether);
        manager.modifySAFECollateralization(safeSrc, 1 ether, 50 ether);
        uint safeDst = manager.openSAFE("ETH", address(this));
        manager.transferSAFEOwnership(safeSrc, address(user));

        manager.moveSAFE(safeSrc, safeDst);
    }

    function testProtectSAFE() public {
        uint safe = manager.openSAFE("ETH", address(this));
        weth.deposit{value: 1 ether}();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(manager.safes(safe), 1 ether);
        manager.allowSAFE(safe, address(user), 1);
        user.doModifySAFECollateralization(manager, safe, 1 ether, 50 ether);
        user.doProtectSAFE(manager, safe, address(liquidationEngineMock), address(0x1));
        assertEq(liquidationEngineMock.chosenSAFESaviour("ETH", manager.safes(safe)), address(0x1));
    }
}
