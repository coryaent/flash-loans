pragma solidity ^0.5.0;
pragma experimental ABIEncoderV2;

import "@studydefi/money-legos/aave/contracts/ILendingPool.sol";
import "@studydefi/money-legos/aave/contracts/IFlashLoanReceiver.sol";
import "@studydefi/money-legos/aave/contracts/FlashloanReceiverBase.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ContractWithFlashLoan is FlashLoanReceiverBase {
    address constant AaveLendingPoolAddressProviderAddress = 0x24a42fD28C976A61Df5D00D0599C34c4f90748c8;

    function executeOperation(
        address _reserve,
        uint _amount,
        uint _fee,
        bytes calldata _params
    ) external {
        // You can pass in some byte-encoded params
        memory script = _params;

        // sequentially call contacts, abort on failed calls (TxManager)
        invokeContracts(script);

        // repay flash loan
        transferFundsBackToPoolInternal(_reserve, _amount.add(_fee));

        // withdraw profits
        if (_reserve == '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE') {
            msg.sender.transfer(this.balance);
        } else {
            IERC20(_reserve).transfer(msg.sender, IERC20(_reserve).balanceOf(this));
        }

    }

    // Entry point
    function initateFlashLoan(
        address contractWithFlashLoan,
        address assetToFlashLoan,
        uint amountToLoan,
        bytes calldata _params
    ) external {
        // Get Aave lending pool
        ILendingPool lendingPool = ILendingPool(
            ILendingPoolAddressesProvider(AaveLendingPoolAddressProviderAddress)
                .getLendingPool()
        );

        // Ask for a flashloan
        // LendingPool will now execute the `executeOperation` function above
        lendingPool.flashLoan(
            contractWithFlashLoan, // Which address to callback into, alternatively: address(this)
            assetToFlashLoan,
            amountToLoan,
            _params
        );
    }

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
