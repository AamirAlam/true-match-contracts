// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ReputationSBT
 * @dev Soulbound Token (non-transferable NFT) for user reputation.
 * - tokenId = address(user) cast to uint160
 * - Each address can only have one SBT
 * - Admin (protocol) can mint, update tier, and burn
 */
contract ReputationSBT {
    string public name = "TrueMatch Protocol Reputation";
    string public symbol = "TM-SBT";

    address public owner;

    mapping(uint256 => bool) public exists;
    mapping(uint256 => uint256) public level; // tokenId => tier (0..n)

    event OwnershipTransferred(address indexed prev, address indexed next);
    event Minted(address indexed to, uint256 tokenId, uint256 tier);
    event LevelUpdated(address indexed to, uint256 oldTier, uint256 newTier);
    event Burned(address indexed from, uint256 tokenId);

    modifier onlyOwner() {
        require(msg.sender == owner, "NOT_OWNER");
        _;
    }

    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function transferOwnership(address next) external onlyOwner {
        require(next != address(0), "ZERO_ADDR");
        emit OwnershipTransferred(owner, next);
        owner = next;
    }

    function tokenIdFor(address user) public pure returns (uint256) {
        return uint256(uint160(user));
    }

    function balanceOf(address account) external view returns (uint256) {
        return exists[tokenIdFor(account)] ? 1 : 0;
    }

    function ownerOf(uint256 tokenId) external pure returns (address) {
        return address(uint160(tokenId));
    }

    function mintOrUpdate(address to, uint256 newTier) external onlyOwner {
        uint256 id = tokenIdFor(to);
        if (!exists[id]) {
            exists[id] = true;
            level[id] = newTier;
            emit Minted(to, id, newTier);
        } else {
            uint256 old = level[id];
            level[id] = newTier;
            emit LevelUpdated(to, old, newTier);
        }
    }

    function burn(address from) external onlyOwner {
        uint256 id = tokenIdFor(from);
        require(exists[id], "NO_SBT");
        delete exists[id];
        delete level[id];
        emit Burned(from, id);
    }
}
