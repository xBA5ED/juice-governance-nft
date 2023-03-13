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

    event NFTStaked(uint256 _tokenId, address _stakedAt);
    event NFTUnstaked(uint256 _tokenId);

    error NO_PERMISSION(uint256 _tokenId);
    error INVALID_STAKE_AMOUNT(uint256 _i, uint256 _amount);
    error NFT_IS_STAKED(uint256 _tokenId, address _stakedAt);

    IERC20 immutable token;
    mapping(address => uint256) public stakingTokenBalance;
    mapping(uint256 => JBGovernanceNFTStake) stakes;

    uint256 nextokenId = 1;

    constructor(IERC20 _token) ERC721("", "") EIP712("", "") {
        token = _token;
    }

    function mint(JBGovernanceNFTMint[] calldata _mints) external returns (uint256 _tokenId) {
        address _sender = _msgSender();
        for (uint256 _i; _i < _mints.length;) {
            // Should never be more than a uint200 or 0
            if (_mints[_i].stakeAmount == 0 || _mints[_i].stakeAmount > type(uint200).max) {
                revert INVALID_STAKE_AMOUNT(_i, _mints[_i].stakeAmount);
            }
            // Transfer the stake amount from the user
            token.safeTransferFrom(_sender, address(this), _mints[_i].stakeAmount);
            // Get the tokenId to use and increment it for the next usage
            unchecked {
                _tokenId = ++nextokenId;
            }
            // If the NFT should staked immediatly then we do so
            // otherwise stakedAt becomes address(0) which means unstaked
            address _stakedAt;
            if (_mints[_i].stakeNFT) {
                _stakedAt = _sender;
                emit NFTStaked(_tokenId, _sender);
            }
            // Store the info regarding this staked position
            stakes[_tokenId] = JBGovernanceNFTStake({
                amount: uint200(_mints[_i].stakeAmount),
                stakedAt: _stakedAt
            });
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
            if (_ownerOf(_burns[_i].tokenId) != msg.sender) revert NO_PERMISSION(_burns[_i].tokenId);
            // Immedialty burn to prevernt reentrency
            _burn(_burns[_i].tokenId);
            // Release the stake
            // We can transfer before deleting from storage since the NFT is burned
            // Any attempt at reentrence will revert since the storage delete is non-critical
            // we are just recouping some gas cost
            token.transferFrom(address(this), _burns[_i].beneficiary, stakes[_burns[_i].tokenId].amount);
            // Delete the position
            delete stakes[_burns[_i].tokenId];
            unchecked {
                ++_i;
            }
        }
    }

    function stake(uint256[] calldata _tokenIds) external {
        address _sender = _msgSender();
        for (uint256 _i; _i < _tokenIds.length;) {
            uint256 _tokenId = _tokenIds[_i];
            // Only the owner or a approved sender can stake the nft
            if(!_isApprovedOrOwner(_sender, _tokenId))
                revert NO_PERMISSION(_tokenId);
            // If a nft is already staked it has to be unstaked first
            if(stakes[_tokenId].stakedAt != address(0))
                revert NFT_IS_STAKED(_tokenId, stakes[_tokenId].stakedAt);
            // Stake the nft at the sender address
            stakes[_tokenId].stakedAt = _sender;
            emit NFTStaked(_tokenId, _sender);
            unchecked {
                ++_i;
            }
        }
    }

    function unstake(uint256[] calldata _tokenIds) external {
        address _sender = _msgSender();
           for (uint256 _i; _i < _tokenIds.length;) {
            uint256 _tokenId = _tokenIds[_i];
            // Can only unstake tokens that are staked at the senders address
            // This way contracts can control when users are allowed to unstake
            if(stakes[_tokenId].stakedAt != _sender)
                revert NO_PERMISSION(_tokenId);

            // Release the nft
            stakes[_tokenId].stakedAt = address(0);
            emit NFTUnstaked(_tokenId);
            unchecked {
                ++_i;
            }
        }
    }

    /**
     * @dev Hook that is called before any token transfer. This includes minting and burning. If {ERC721Consecutive} is
     * used, the hook may be called as part of a consecutive (batch) mint, as indicated by `batchSize` greater than 1.
     *
     * Calling conditions:
     *
     * - When `from` and `to` are both non-zero, ``from``'s tokens will be transferred to `to`.
     * - When `from` is zero, the tokens will be minted for `to`.
     * - When `to` is zero, ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     * - `batchSize` is non-zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address from,
        address, // to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal virtual override {
        // batchSize is used if inherited from `ERC721Consecutive`
        // which we don't, so this should always be 1
        assert(batchSize == 1);
        // Check if the NFT is staked, if it is staked transfer is not allowed
        // if the from is address 0 then this is a mint in which case we don't need to revert
        if (from != address(0)) {
            address _stakedAt = stakes[firstTokenId].stakedAt;
            if(_stakedAt != address(0)) 
                revert NFT_IS_STAKED(firstTokenId, _stakedAt);
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
