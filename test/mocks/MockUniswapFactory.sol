// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MockUniswapFactory {
    mapping(address => mapping(address => mapping(uint24 => address))) public getPool;
    address[] public allPools;

    event PoolCreated(address indexed token0, address indexed token1, uint24 indexed fee, address pool);

    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool) {
        require(tokenA != tokenB, "MockFactory: IDENTICAL_ADDRESSES");
        require(tokenA != address(0) && tokenB != address(0), "MockFactory: ZERO_ADDRESS");
        require(getPool[tokenA][tokenB][fee] == address(0), "MockFactory: POOL_EXISTS");

        // Create mock pool address
        pool = address(uint160(uint256(keccak256(abi.encodePacked(tokenA, tokenB, fee, block.timestamp)))));

        getPool[tokenA][tokenB][fee] = pool;
        getPool[tokenB][tokenA][fee] = pool;
        allPools.push(pool);

        emit PoolCreated(tokenA, tokenB, fee, pool);
    }

    function allPoolsLength() external view returns (uint256) {
        return allPools.length;
    }

    // Legacy V2 compatibility for tests that might still use it
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, "MockFactory: IDENTICAL_ADDRESSES");
        require(tokenA != address(0) && tokenB != address(0), "MockFactory: ZERO_ADDRESS");
        require(getPair[tokenA][tokenB] == address(0), "MockFactory: PAIR_EXISTS");

        // Create mock pair address
        pair = address(uint160(uint256(keccak256(abi.encodePacked(tokenA, tokenB, block.timestamp)))));

        getPair[tokenA][tokenB] = pair;
        getPair[tokenB][tokenA] = pair;
        allPairs.push(pair);

        emit PairCreated(tokenA, tokenB, pair, allPairs.length);
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }
}
