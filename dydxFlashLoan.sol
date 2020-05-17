pragma solidity ^0.5.0;
pragma experimental ABIEncoderV2;

import "@studydefi/money-legos/dydx/contracts/DydxFlashloanBase.sol";
import "@studydefi/money-legos/dydx/contracts/ICallee.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract DydxFlashloaner is ICallee, DydxFlashloanBase {
    struct MyCustomData {
        address token;
        bytes script;
    }

    // This is the function that will be called postLoan
    // i.e. Encode the logic to handle your flashloaned funds here
    function callFunction(
        address sender,
        Account.Info memory account,
        bytes memory data
    ) public {
        MyCustomData memory mcd = abi.decode(data, (MyCustomData));

        // Note that you can ignore the line below
        // if your dydx account (this contract in this case)
        // has deposited at least ~2 Wei of assets into the account
        // to balance out the collaterization ratio
        // require(
        //     balOfLoanedToken >= mcd.repayAmount,
        //     "Not enough funds to repay dydx loan!"
        // );

        // sequentially call contacts, abort on failed calls (TxManager)
        invokeContracts(mcd.script);

        // withdraw profits
        IERC20(mcd.token).transfer(msg.sender, IERC20(mcd.token).balanceOf(this));
    }

    function initateFlashLoan(address _solo, address _token, uint256 _amount, bytes _script)
        external
    {
        ISoloMargin solo = ISoloMargin(_solo);

        // Get marketId from token address
        uint256 marketId = _getMarketIdFromTokenAddress(_solo, _token);

        // Calculate repay amount (_amount + (2 wei))
        // Approve transfer from
        uint256 repayAmount = _getRepaymentAmountInternal(_amount);
        IERC20(_token).approve(_solo, repayAmount);

        // 1. Withdraw $
        // 2. Call callFunction(...)
        // 3. Deposit back $
        Actions.ActionArgs[] memory operations = new Actions.ActionArgs[](3);

        operations[0] = _getWithdrawAction(marketId, _amount);
        operations[1] = _getCallAction(
            abi.encode(MyCustomData({token: _token, script: _script}))
        );
        operations[2] = _getDepositAction(marketId, repayAmount);

        Account.Info[] memory accountInfos = new Account.Info[](1);
        accountInfos[0] = _getAccountInfo();

        solo.operate(accountInfos, operations);
    }

        // from MakerDAO's TxManager
    // from MakerDAO's TxManager
    function invokeContracts(bytes script) internal {
        uint256 location = 0;
        while (location < script.length) {
            address contractAddress = addressAt(script, location);
            uint256 calldataLength = uint256At(script, location + 0x14);
            uint256 calldataStart = locationOf(script, location + 0x14 + 0x20);
            assembly {
                switch call(sub(gas, 5000), contractAddress, 0, calldataStart, calldataLength, 0, 0)
                case 0 {
                    revert(0, 0)
                }
            }

            location += (0x14 + 0x20 + calldataLength);
        }
    }

    function uint256At(bytes data, uint256 location) internal pure returns (uint256 result) {
        assembly {
            result := mload(add(data, add(0x20, location)))
        }
    }

    function addressAt(bytes data, uint256 location) internal pure returns (address result) {
        uint256 word = uint256At(data, location);
        assembly {
            result := div(and(word, 0xffffffffffffffffffffffffffffffffffffffff000000000000000000000000),
                          0x1000000000000000000000000)
        }
    }

    function locationOf(bytes data, uint256 location) internal pure returns (uint256 result) {
        assembly {
            result := add(data, add(0x20, location))
        }
    }
}
