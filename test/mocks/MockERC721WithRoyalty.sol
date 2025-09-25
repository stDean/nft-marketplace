// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

contract MockERC721WithRoyalty is ERC721, IERC2981 {
    address public royaltyRecipient;
    uint256 public royaltyBasisPoints;

    constructor(address _royaltyRecipient, uint256 _royaltyBasisPoints) ERC721("MockNFTWithRoyalty", "MNRY") {
        royaltyRecipient = _royaltyRecipient;
        royaltyBasisPoints = _royaltyBasisPoints;
    }

    function mint(address to, uint256 tokenId) public {
        _mint(to, tokenId);
    }

    function royaltyInfo(uint256, /* tokenId */ uint256 salePrice)
        external
        view
        override
        returns (address receiver, uint256 royaltyAmount)
    {
        royaltyAmount = (salePrice * royaltyBasisPoints) / 10000;
        return (royaltyRecipient, royaltyAmount);
    }

    // Simple override without complex inheritance
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, IERC165) returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }
}
