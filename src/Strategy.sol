// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {BaseStrategy, ERC20} from "@tokenized-strategy/BaseStrategy.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPair} from "./interfaces/IPair.sol";
// Import interfaces for many popular DeFi projects, or add your own!
//import "../interfaces/<protocol>/<Interface>.sol";

/**
 * The `TokenizedStrategy` variable can be used to retrieve the strategies
 * specific storage data your contract.
 *
 *       i.e. uint256 totalAssets = TokenizedStrategy.totalAssets()
 *
 * This can not be used for write functions. Any TokenizedStrategy
 * variables that need to be updated post deployment will need to
 * come from an external call from the strategies specific `management`.
 */

// NOTE: To implement permissioned functions you can use the onlyManagement, onlyEmergencyAuthorized and onlyKeepers modifiers

contract Strategy is BaseStrategy {
    using SafeERC20 for ERC20;

    event PriceTargetSet(uint256 targetPrice);
    event DepositCapSet(uint256 depositCap);

    // USDC.e on Polygon – token0
    ERC20 public constant USDC = ERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);

    // token1
    ERC20 public constant USDR = ERC20(0x40379a439D4F6795B6fc9aa5687dB461677A2dBa);

    // USDC_USDR pair on
    IPair public constant USDC_USDR = IPair(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);

    uint256 public constant SCALAR = 1e6;

    // Target price, scaled by SCALAR
    uint256 public targetPrice;

    constructor(address _asset, string memory _name) BaseStrategy(_asset, _name) {
        USDR.approve(address(USDC_USDR), type(uint256).max);
        USDC.approve(address(USDC_USDR), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                NEEDED TO BE OVERRIDDEN BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Should deploy up to '_amount' of 'asset' in the yield source.
     *
     * This function is called at the end of a {deposit} or {mint}
     * call. Meaning that unless a whitelist is implemented it will
     * be entirely permissionless and thus can be sandwiched or otherwise
     * manipulated.
     *
     * @param _amount The amount of 'asset' that the strategy should attempt
     * to deposit in the yield source.
     */
    function _deployFunds(uint256 _amount) internal override {
        if (depositLimit < type(uint256).max) {
            if (depositLimit < _amount) revert("Deposit cap exceeded");
            depositLimit -= _amount;
        }
        uint256 _usdrOut = ((USDC_USDR.current(address(USDC), _amount) * 99) / 100);

        USDC_USDR.swap(0, _usdrOut, address(this), "");
    }

    /**
     * @dev Will attempt to free the '_amount' of 'asset'.
     *
     * The amount of 'asset' that is already loose has already
     * been accounted for.
     *
     * This function is called during {withdraw} and {redeem} calls.
     * Meaning that unless a whitelist is implemented it will be
     * entirely permissionless and thus can be sandwiched or otherwise
     * manipulated.
     *
     * Should not rely on asset.balanceOf(address(this)) calls other than
     * for diff accounting purposes.
     *
     * Any difference between `_amount` and what is actually freed will be
     * counted as a loss and passed on to the withdrawer. This means
     * care should be taken in times of illiquidity. It may be better to revert
     * if withdraws are simply illiquid so not to realize incorrect losses.
     *
     * @param _amount, The amount of 'asset' to be freed.
     */
    function _freeFunds(uint256 _amount) internal override {
        if (_amount < USDC.balanceOf(address(this))) revert("Not enough funds to withdraw");

        if (depositLimit < type(uint256).max) {
            depositLimit += _amount;
        }
    }

    /**
     * @dev Internal function to harvest all rewards, redeploy any idle
     * funds and return an accurate accounting of all funds currently
     * held by the Strategy.
     *
     * This should do any needed harvesting, rewards selling, accrual,
     * redepositing etc. to get the most accurate view of current assets.
     *
     * NOTE: All applicable assets including loose assets should be
     * accounted for in this function.
     *
     * Care should be taken when relying on oracles or swap values rather
     * than actual amounts as all Strategy profit/loss accounting will
     * be done based on this returned value.
     *
     * This can still be called post a shutdown, a strategist can check
     * `TokenizedStrategy.isShutdown()` to decide if funds should be
     * redeployed or simply realize any profits/losses.
     *
     * @return _totalAssets A trusted and accurate account for the total
     * amount of 'asset' the strategy currently holds including idle funds.
     */
    function _harvestAndReport() internal view override returns (uint256 _totalAssets) {
        _totalAssets = USDC_USDR.current(address(USDR), USDR.balanceOf(address(this)));
    }

    /*//////////////////////////////////////////////////////////////
                    OPTIONAL TO OVERRIDE BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Optional function for strategist to override that can
     *  be called in between reports.
     *
     * If '_tend' is used tendTrigger() will also need to be overridden.
     *
     * This call can only be called by a permissioned role so may be
     * through protected relays.
     *
     * This can be used to harvest and compound rewards, deposit idle funds,
     * perform needed position maintenance or anything else that doesn't need
     * a full report for.
     *
     *   EX: A strategy that can not deposit funds without getting
     *       sandwiched can use the tend when a certain threshold
     *       of idle to totalAssets has been reached.
     *
     * The TokenizedStrategy contract will do all needed debt and idle updates
     * after this has finished and will have no effect on PPS of the strategy
     * till report() is called.
     *
     *
     */
    function _tend(uint256) internal override {
        uint256 _usdrBal = USDR.balanceOf(address(this));
        // Calculate amount out, in addition to slippage
        uint256 _amountOut = ((USDC_USDR.current(address(USDR), _usdrBal) * SCALAR / _usdrBal) * 99) / 100;

        USDC_USDR.swap(_amountOut, 0, address(this), "");
    }

    /**
     * @dev Optional trigger to override if tend() will be used by the strategy.
     * This must be implemented if the strategy hopes to invoke _tend().
     *
     * @return . Should return true if tend() should be called by keeper or false if not.
     *
     */
    function _tendTrigger() internal view override returns (bool) {
        uint256 _usdrBal = USDR.balanceOf(address(this));
        // If the price is above the target price, sell USDR for USDC
        if (USDC_USDR.current(address(USDR), _usdrBal) * SCALAR / _usdrBal >= targetPrice) {
            return true;
        }
        return false;
    }

    /**
     * @notice Gets the max amount of `asset` that an address can deposit.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overridden by strategists.
     *
     * This function will be called before any deposit or mints to enforce
     * any limits desired by the strategist. This can be used for either a
     * traditional deposit limit or for implementing a whitelist etc.
     *
     *   EX:
     *      if(isAllowed[_owner]) return super.availableDepositLimit(_owner);
     *
     * This does not need to take into account any conversion rates
     * from shares to assets. But should know that any non max uint256
     * amounts may be converted to shares. So it is recommended to keep
     * custom amounts low enough as not to cause overflow when multiplied
     * by `totalSupply`.
     *
     * @param . The address that is depositing into the strategy.
     * @return . The available amount the `_owner` can deposit in terms of `asset`
     *
     * function availableDepositLimit(
     *     address _owner
     * ) public view override returns (uint256) {
     *     TODO: If desired Implement deposit limit logic and any needed state variables .
     *
     *     EX:
     *         uint256 totalAssets = TokenizedStrategy.totalAssets();
     *         return totalAssets >= depositLimit ? 0 : depositLimit - totalAssets;
     * }
     */

    function availableDepositLimit(address) public view override returns (uint256) {
        return depositLimit;
    }

    /**
     * @notice Gets the max amount of `asset` that can be withdrawn.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overridden by strategists.
     *
     * This function will be called before any withdraw or redeem to enforce
     * any limits desired by the strategist. This can be used for illiquid
     * or sandwichable strategies. It should never be lower than `totalIdle`.
     *
     *   EX:
     *       return TokenIzedStrategy.totalIdle();
     *
     * This does not need to take into account the `_owner`'s share balance
     * or conversion rates from shares to assets.
     *
     * @param . The address that is withdrawing from the strategy.
     * @return . The available amount that can be withdrawn in terms of `asset`
     *
     *     TODO: If desired Implement withdraw limit logic and any needed state variables.
     */

    function availableWithdrawLimit(address) public view override returns (uint256) {
        return USDC.balanceOf(address(this));
    }

    /**
     * @dev Optional function for a strategist to override that will
     * allow management to manually withdraw deployed funds from the
     * yield source if a strategy is shutdown.
     *
     * This should attempt to free `_amount`, noting that `_amount` may
     * be more than is currently deployed.
     *
     * NOTE: This will not realize any profits or losses. A separate
     * {report} will be needed in order to record any profit/loss. If
     * a report may need to be called after a shutdown it is important
     * to check if the strategy is shutdown during {_harvestAndReport}
     * so that it does not simply re-deploy all funds that had been freed.
     *
     * EX:
     *   if(freeAsset > 0 && !TokenizedStrategy.isShutdown()) {
     *       depositFunds...
     *    }
     *
     * @param _amount The amount of asset to attempt to free.
     *
     */
    function _emergencyWithdraw(uint256 _amount) internal override {
        USDC_USDR.swap(_amount, 0, address(this), "");
    }

    /* -------------------------------------------------------------------------- */
    /*                            Additional Functions                            */
    /* -------------------------------------------------------------------------- */

    uint256 depositLimit = type(uint256).max;

    function setDepositCap(uint256 _amount) external onlyManagement {
        // Deposit cap is not retroactive
        depositLimit = _amount;

        emit DepositCapSet(_amount);
    }

    function setPriceTarget(uint256 _targetPrice) external onlyManagement {
        targetPrice = _targetPrice;

        emit PriceTargetSet(_targetPrice);
    }

    function governanceRecoverUnsupported(ERC20 _asset, uint256 _amount, address _recipient) external onlyManagement {
        bool _shutdown = TokenizedStrategy.isShutdown();
        // If strategy isn't shut down – the base assets can't be withdrawn
        require(!_shutdown && asset != USDR || _asset != USDC, "Strategy: asset");
        _asset.safeTransfer(_recipient, _amount);
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
