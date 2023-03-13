// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/JBGovernanceNFT.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract JBGovernanceNFTTest is Test {
    JBGovernanceNFT public jbGovernanceNFT;
    ERC20 public stakeToken;

    address public user = address(0x420); 

    function setUp() public {
        vm.startPrank(user);

        stakeToken = new mockERC20();
        jbGovernanceNFT = new JBGovernanceNFT(
            stakeToken
        );

        vm.stopPrank();
    }

    function testStake(uint200[] calldata _amounts, address _beneficiary) public {
        uint256 _sumStaked;
        JBGovernanceNFTMint[] memory _mints = new JBGovernanceNFTMint[](_amounts.length);

        // Can't mint to the 0 address
        vm.assume(_beneficiary != address(0));

        for(uint256 _i; _i < _amounts.length; _i++){
            uint200 _amount = _amounts[_i];
            vm.assume(_amount != 0);
            unchecked{
                // If we overflow the combined amount will be less than the original
                vm.assume(_sumStaked + _amount >= _sumStaked);
                _sumStaked = _sumStaked + _amount;
            }

            _mints[_i] = JBGovernanceNFTMint({
                stakeAmount: _amount,
                beneficiary: _beneficiary,
                stakeNFT: false
            });
        }
        // Make sure we have enough balance
        vm.assume(_sumStaked < stakeToken.totalSupply());

        vm.prank(user);
        stakeToken.increaseAllowance(address(jbGovernanceNFT), _sumStaked);

        vm.prank(user);
        jbGovernanceNFT.mint(_mints);

        assertEq(
            jbGovernanceNFT.stakingTokenBalance(_beneficiary),
            _sumStaked
        );
    }
}


contract mockERC20 is ERC20 {
    constructor() ERC20("MockToken", "MCK") {
        _mint(msg.sender, 100_000 * (10 ** decimals()) );
    }
}