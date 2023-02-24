// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {JBGovernanceNFTStake} from "./structs/JBGovernanceNFTStake.sol";
import {JBGovernanceNFTMint} from "./structs/JBGovernanceNFTMint.sol";
import {JBGovernanceNFTBurn} from "./structs/JBGovernanceNFTBurn.sol";

import "@openzeppelin/contracts/utils/Checkpoints.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EIP712, ERC721, ERC721Votes} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Votes.sol";

contract JBGovernanceNFT is ERC721Votes {
    using Checkpoints for Checkpoints.History;
    using SafeERC20 for IERC20;

    IERC20 immutable token;
    mapping(address => uint256) stakingTokenBalance;
    mapping(uint256 => JBGovernanceNFTStake) stakes;

    uint256 nextokenId = 1;

    constructor(IERC20 _token) ERC721("", "") EIP712("", "") {
        token = _token;
    }

    function mint(JBGovernanceNFTMint[] calldata _mints) external returns (uint256 _tokenId) {
        for (uint256 _i; _i < _mints.length;) {
            // Should never be more than a uint200
            require(_mints[_i].stakeAmount <= type(uint200).max);
            // Transfer the stake amount from the user
            token.safeTransferFrom(msg.sender, address(this), _mints[_i].stakeAmount);
            // Get the tokenId to use and increment it for the next usage
            unchecked {
                _tokenId = ++nextokenId;
            }
            // Store the info regarding this staked position
            stakes[_tokenId] = JBGovernanceNFTStake({amount: uint200(_mints[_i].stakeAmount)});
            // Living on the edge, using safemint because we can
            _safeMint(_mints[_i].beneficiary, _tokenId);
            unchecked {
                ++_i;
            }
        }
    }

    function burn(JBGovernanceNFTBurn[] calldata _burns) external {
        for (uint256 _i; _i < _burns.length;) {
            // Make sure only the owner can do this
            require(ownerOf(_burns[_i].tokenId) == msg.sender);
            // Immedialty burn to prevernt reentrency
            _burn(_burns[_i].tokenId);
            // Release the stake
            // We can transfer before deleting from storage since the NFT is burned
            // Any attempt at reentrence will revert since the storage delete is non-critical
            // we are just recouping some gas cost
            token.transferFrom(address(this), _burns[_i].beneficiary, stakes[_burns[_i].tokenId].amount);
            // Delete the position
            delete stakes[_burns[_i].tokenId];
        }
    }

    /**
     * @dev See {ERC721-_afterTokenTransfer}. Adjusts votes when tokens are transferred.
     *
     * Emits a {IVotes-DelegateVotesChanged} event.
     */
    function _afterTokenTransfer(address from, address to, uint256 firstTokenId, uint256 batchSize)
        internal
        virtual
        override
    {
        // batchSize is used if inherited from `ERC721Consecutive`
        // which we don't, so this should always be 1
        assert(batchSize == 1);
        uint256 _stakingTokenAmount = stakes[firstTokenId].amount;

        // TODO: check if we can do this 'unchecked'
        if (from != address(0)) {
            stakingTokenBalance[from] -= _stakingTokenAmount;
        }

        if (to != address(0)) {
            stakingTokenBalance[to] += _stakingTokenAmount;
        }

        _transferVotingUnits(from, to, _stakingTokenAmount);
        super._afterTokenTransfer(from, to, firstTokenId, batchSize);
    }

    /**
     * @dev Returns the balance of `account`.
     */
    function _getVotingUnits(address account) internal view virtual override returns (uint256) {
        return stakingTokenBalance[account];
    }
}
