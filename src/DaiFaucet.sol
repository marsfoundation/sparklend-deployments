// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

interface PsmLike {
    function dai() external view returns (address);
    function gemJoin() external view returns (address);
    function sellGem(address usr, uint256 gemAmt) external;
}

interface GemJoinLike {
    function gem() external view returns (address);
}

interface GemLike {
    function approve(address, uint256) external;
    function transferFrom(address, address, uint256) external;
    function transfer(address, uint256) external;
    function balanceOf(address) external view returns (uint256);
}

interface FaucetLike {
    function gulp(address gem) external;
}

contract DaiFaucet {

    PsmLike public immutable psm;
    GemLike public immutable dai;
    GemLike public immutable gem;
    FaucetLike public immutable faucet;

    constructor(address _psm, address _faucet) {
        psm = PsmLike(_psm);
        dai = GemLike(psm.dai());
        gem = GemLike(GemJoinLike(psm.gemJoin()).gem());
        faucet = FaucetLike(_faucet);

        gem.approve(psm.gemJoin(), type(uint256).max);
    }

    function gulp(address usr, uint256 runs) external {
        for (uint256 i = 0; i < runs; i++) {
            faucet.gulp(address(gem));
        }
        psm.sellGem(usr, gem.balanceOf(address(this)));
    }

}
