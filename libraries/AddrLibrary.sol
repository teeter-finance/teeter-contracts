pragma solidity ^0.5.6;


library AddrLibrary {

    // calculates the CREATE2 address for a pair without making any external calls
    function underlyingFor(
        address factory,
        address tokenA,
        uint8 lever,
        uint8 direction
    ) internal pure returns (address underlying) {
        underlying = address(
            uint256(
                keccak256(
                    abi.encodePacked(
                        hex"ff",
                        factory,
                        keccak256(abi.encodePacked(tokenA, lever, direction)),
                        hex"c4d3d4f8d18ac5611209f32903142288d5fcc7dcdbe17b7ef66e7d6b1f44a5d4" // init code hash
                    )
                )
            )
        );
    }

    function underlyingTopFor(
        address factory,
        address tokenA,
        uint8 lever,
        uint8 direction
    ) internal pure returns (address underlying) {
        underlying = address(
            uint256(
                keccak256(
                    abi.encodePacked(
                        hex"ff",
                        factory,
                        keccak256(abi.encodePacked(tokenA, lever, direction)),
                        hex"e25733d43ecf5ad2efcf91876b3318f8faa95e4636a419aab71b7c29bfe49bd4" // init code hash
                    )
                )
            )
        );
    }
}
