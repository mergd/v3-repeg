// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPair} from "src/interfaces/IPair.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Setup} from "./Setup.sol";

contract mockPair is IPair {
    ERC20 public immutable _token0;
    ERC20 public immutable _token1;

    constructor(ERC20 __token0, ERC20 __token1) {
        _token0 = __token0;
        _token1 = __token1;
    }

    function initialize(address __token0, address __token1, bool _stable) external {}

    function metadata()
        external
        view
        returns (uint256 dec0, uint256 dec1, uint256 r0, uint256 r1, bool st, address t0, address t1)
    {}

    function claimFees() external returns (uint256, uint256) {}

    function tokens() external view returns (address, address) {}

    function token0() external view returns (address) {}

    function token1() external view returns (address) {}

    function transferFrom(address src, address dst, uint256 amount) external returns (bool) {}

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
    {}

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata) external {
        if (amount0Out > 0) {
            amount0Out = amount0Out * exchangeRate / 1e18;
            _token0.transfer(to, amount0Out);
        } else if (amount1Out > 0) {
            _token1.transfer(to, amount1Out);
        } else {
            revert("Pair: INSUFFICIENT_OUTPUT_AMOUNT");
        }
    }

    function burn(address to) external returns (uint256 amount0, uint256 amount1) {}

    function mint(address to) external returns (uint256 liquidity) {}

    function getReserves() external view returns (uint256 _reserve0, uint256 _reserve1, uint256 _blockTimestampLast) {}

    function getAmountOut(uint256, address) external view returns (uint256) {}

    function name() external view returns (string memory) {}

    function symbol() external view returns (string memory) {}

    function totalSupply() external view returns (uint256) {}

    function decimals() external view returns (uint8) {}

    function claimable0(address _user) external view returns (uint256) {}

    function claimable1(address _user) external view returns (uint256) {}

    function stable() external view returns (bool) {}

    function skim(address to) external {}

    uint256 public exchangeRate;

    function setExchangeRate(uint256 _exchangeRate) external {
        exchangeRate = _exchangeRate;
    }

    function current(address token, uint256 amountOut) external view returns (uint256) {
        if (token == address(_token0)) {
            return amountOut * exchangeRate / 1e18;
        } else if (token == address(_token1)) {
            return amountOut;
        } else {
            revert("Pair: INVALID_TOKEN");
        }
    }
}
