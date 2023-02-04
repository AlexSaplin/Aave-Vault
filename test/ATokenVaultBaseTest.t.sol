// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import {IERC20Upgradeable} from "@openzeppelin-upgradeable/interfaces/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {IPoolAddressesProvider} from "@aave-v3-core/interfaces/IPoolAddressesProvider.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";

import {ATokenVault, MathUpgradeable} from "../src/ATokenVault.sol";

contract ATokenVaultBaseTest is Test {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using MathUpgradeable for uint256;

    bytes32 constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    // Fork tests using Polygon for Aave v3
    address constant POLYGON_DAI = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
    address constant POLYGON_ADAI = 0x82E64f49Ed5EC1bC6e43DAD4FC8Af9bb3A2312EE;
    address constant POLYGON_AAVE_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address constant POLYGON_POOL_ADDRESSES_PROVIDER = 0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb;
    address constant POLYGON_REWARDS_CONTROLLER = 0x929EC64c34a17401F460460D4B9390518E5B473e;

    uint256 constant SCALE = 1e18;
    uint256 constant ONE = 1e18;
    uint256 constant TEN = 10e18;
    uint256 constant HUNDRED = 100e18;
    uint256 constant ONE_PERCENT = 0.01e18;
    uint256 constant ONE_BPS = 0.0001e18;

    uint256 constant PROXY_ADMIN_PRIV_KEY = 4546;
    uint256 constant OWNER_PRIV_KEY = 11111;
    uint256 constant ALICE_PRIV_KEY = 12345;
    uint256 constant BOB_PRIV_KEY = 54321;
    uint256 constant CHAD_PRIV_KEY = 98765;

    address PROXY_ADMIN = vm.addr(PROXY_ADMIN_PRIV_KEY);
    address OWNER = vm.addr(OWNER_PRIV_KEY);
    address ALICE = vm.addr(ALICE_PRIV_KEY);
    address BOB = vm.addr(BOB_PRIV_KEY);
    address CHAD = vm.addr(CHAD_PRIV_KEY);

    string constant SHARE_NAME = "Wrapped aDAI";
    string constant SHARE_SYMBOL = "waDAI";

    uint256 fee = 0.2e18; // 20%
    uint16 referralCode = 4546;

    ATokenVault vault;
    address vaultAssetAddress; // aDAI, must be set in every setUp
    uint256 initialLockDeposit; // Must be set in every setUp

    // Initializer Errors
    bytes constant ERR_INITIALIZED = bytes("Initializable: contract is already initialized");

    // Ownable Errors
    bytes constant ERR_NOT_OWNER = bytes("Ownable: caller is not the owner");

    // Meta Tx Errors
    bytes constant ERR_INVALID_SIGNER = bytes("INVALID_SIGNER");
    bytes constant ERR_PERMIT_DEADLINE_EXPIRED = bytes("PERMIT_DEADLINE_EXPIRED");
    bytes constant ERR_SIG_INVALID = bytes("SIG_INVALID");
    bytes constant ERR_SIG_EXPIRED = bytes("SIG_EXPIRED");

    // Vault Errors
    bytes constant ERR_ZERO_ASSETS = bytes("ZERO_ASSETS");
    bytes constant ERR_ZERO_SHARES = bytes("ZERO_SHARES");
    bytes constant ERR_TRANSFER_FROM_FAILED = bytes("TRANSFER_FROM_FAILED");
    bytes constant ERR_CANNOT_RESCUE_ATOKEN = bytes("CANNOT_RESCUE_ATOKEN");
    bytes constant ERR_FEE_TOO_HIGH = bytes("FEE_TOO_HIGH");
    bytes constant ERR_ASSET_NOT_SUPPORTED = bytes("ASSET_NOT_SUPPORTED");
    bytes constant ERR_INSUFFICIENT_FEES = bytes("INSUFFICIENT_FEES");
    bytes constant ERR_CANNOT_CLAIM_TO_ZERO_ADDRESS = bytes("CANNOT_CLAIM_TO_ZERO_ADDRESS");
    bytes constant SAFE_TRANSFER_ARITHMETIC = bytes("NH{q");
    bytes constant ERR_DEPOSIT_EXCEEDS_MAX = bytes("DEPOSIT_EXCEEDS_MAX");
    bytes constant ERR_MINT_EXCEEDS_MAX = bytes("MINT_EXCEEDS_MAX");
    bytes constant ERR_WITHDRAW_EXCEEDS_MAX = bytes("WITHDRAW_EXCEEDS_MAX");
    bytes constant ERR_REDEEM_EXCEEDS_MAX = bytes("REDEEM_EXCEEDS_MAX");

    // ERC4626 Events
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);

    // ATokenVault Events
    event FeeUpdated(uint256 oldFee, uint256 newFee);
    event FeesWithdrawn(address indexed to, uint256 amount, uint256 newVaultBalance, uint256 newTotalFeesAccrued);
    event YieldAccrued(uint256 accruedYield, uint256 newFeesFromYield, uint256 newVaultBalance);
    event RewardsClaimed(address indexed to, address[] rewardsList, uint256[] claimedAmounts);
    event EmergencyRescue(address indexed token, address indexed to, uint256 amount);

    function setUp() public virtual {}

    // For debug purposes
    function _logVaultBalances(address user, string memory label) internal view {
        console.log("\n", label);
        console.log("ERC20 Assets\t\t\t", ERC20(vaultAssetAddress).balanceOf(address(vault)));
        console.log("totalAssets()\t\t\t", vault.totalAssets());
        console.log("lastVaultBalance()\t\t", vault.getLastVaultBalance());
        console.log("User Withdrawable\t\t", vault.maxWithdraw(user));
        console.log("claimable fees\t\t", vault.getClaimableFees());
        console.log("lastUpdated\t\t\t", vault.getLastUpdated());
        console.log("current time\t\t\t", block.timestamp);
    }

    function _deploy(address underlying, address addressesProvider) internal {
        // vm.startPrank(OWNER);
        // vault = new ATokenVault(underlying, referralCode, IPoolAddressesProvider(addressesProvider));
        // bytes memory data = abi.encodeWithSelector(ATokenVault.initialize.selector, OWNER, fee, SHARE_NAME, SHARE_SYMBOL, 0);
        // TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(vault), PROXY_ADMIN, data);
        // vault = ATokenVault(address(proxy));
        // vm.stopPrank();
        _baseDeploy(underlying, addressesProvider, 18);
    }

    function _deploy(
        address underlying,
        address addressesProvider,
        uint256 decimals
    ) internal {
        _baseDeploy(underlying, addressesProvider, decimals);
    }

    function _baseDeploy(
        address underlying,
        address addressesProvider,
        uint256 decimals
    ) internal {
        uint256 amount = 10**decimals;
        initialLockDeposit = amount;
        vault = new ATokenVault(underlying, referralCode, IPoolAddressesProvider(addressesProvider));

        bytes memory data = abi.encodeWithSelector(
            ATokenVault.initialize.selector,
            OWNER,
            fee,
            SHARE_NAME,
            SHARE_SYMBOL,
            amount
        );
        address proxyAddr = computeCreateAddress(address(this), vm.getNonce(address(this)));

        deal(underlying, address(this), amount);
        IERC20Upgradeable(underlying).safeApprove(address(proxyAddr), amount);

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(vault), PROXY_ADMIN, data);

        vault = ATokenVault(address(proxy));
    }
}
