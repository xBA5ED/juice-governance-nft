// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {JBStake} from "./structs/JBStake.sol";

import "@openzeppelin/contracts/utils/Checkpoints.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EIP712, ERC721, ERC721Votes} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Votes.sol";

contract JBGovernanceNFT is ERC721Votes {
    using Checkpoints for Checkpoints.History;
    using SafeERC20 for IERC20;

    IERC20 immutable token;
    mapping(address => uint256) stakingTokenBalance;
    mapping(uint256 => JBStake) stakes;

    uint256 nextokenId = 1;

    constructor(IERC20 _token) ERC721("", "") EIP712("", "") {
        token = _token;
    }

    function mint(uint256 _stakeAmount, address _beneficiary) external returns (uint256 _tokenId) {
        // Should never be more than a uint200
        require(_stakeAmount <= type(uint200).max);

        // Transfer the stake amount from the user
        token.safeTransferFrom(msg.sender, address(this), _stakeAmount);

        // Get the tokenId to use and increment it for the next usage
        unchecked {
            _tokenId = ++nextokenId;
        }

        stakes[_tokenId] = JBStake({amount: uint200(_stakeAmount)});

        // Living on the edge, using safemint because we can
        _safeMint(_beneficiary, _tokenId);
    }

    function burn(uint256 _tokenId, address _beneficiary) external {
        // Make sure only the owner can do this
        require(ownerOf(_tokenId) == msg.sender);
        // Immedialty burn to prevernt reentrency
        _burn(_tokenId);

        uint256 _amount = stakes[_tokenId].amount;

        // Delete the position
        delete stakes[_tokenId];

        // Release the stake
        token.transferFrom(address(this), _beneficiary, _amount);
    }

    /**
     * @dev See {ERC721-_beforeTokenTransfer}. Adjusts votes when tokens are transferred.
     */
    function _beforeTokenTransfer(address from, address to, uint256 firstTokenId, uint256 batchSize)
        internal
        virtual
        override
    {
        assert(batchSize == 1);
        uint256 _stakingTokenAmount = stakes[firstTokenId].amount;

        // TODO: check if we can do this 'unchecked'
        if (from != address(0)) {
            stakingTokenBalance[from] -= _stakingTokenAmount;
        }

        if (to != address(0)) {
            stakingTokenBalance[to] += _stakingTokenAmount;
        }

        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
    }

    /**
     * @dev Returns the balance of `account`.
     */
    function _getVotingUnits(address account) internal view virtual override returns (uint256) {
        return stakingTokenBalance[account];
    }
}
