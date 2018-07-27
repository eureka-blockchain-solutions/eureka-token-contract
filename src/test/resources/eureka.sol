pragma solidity ^0.4.24;

import "./SafeMath.sol";
import "./Utils.sol";

contract ERC20 {
    function allowance(address owner, address spender) public view returns (uint256);
    function transferFrom(address from, address to, uint256 value) public returns (bool);
    function approve(address spender, uint256 value) public returns (bool);
    function totalSupply() public view returns (uint256);
    function balanceOf(address who) public view returns (uint256);
    function transfer(address to, uint256 value) public returns (bool);

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);
}

/**
 * @title ERC677 transferAndCall token interface
 * @dev See https://github.com/ethereum/EIPs/issues/677 for specification and
 *      discussion.
 *
 * We deviate from the specification and we don't define a tokenfallback. That menas
 * tranferAndCall can specify the function to call (bytes4(sha3("setN(uint256)")))
 * and its arguments, and the respective function is called.
 * TODO: find out what happens if the function is not found. Will the default function
 * be called, or will the function return false?
 *
 * We also deviate from ERC865 and added a pre signed transaction for transferAndCall.
 */
contract ERC865Plus677ish {
    event Transfer(address indexed _from, address indexed _to, uint256 _value, bytes4 _methodName, bytes _args);
    function transferAndCall(address _to, uint _value, bytes4 _methodName, bytes _args) public returns (bool success);

    event TransferPreSigned(address indexed _from, address indexed _to, address indexed _delegate,
        uint256 _amount, uint256 _fee);
    event TransferPreSigned(address indexed _from, address indexed _to, address indexed _delegate,
        uint256 _amount, uint256 _fee, bytes4 _methodName, bytes _args);

    function transferPreSigned(bytes _signature, address _to, uint256 _value,
        uint256 _fee, uint256 _nonce) public returns (bool);
    function transferAndCallPreSigned(bytes _signature, address _to, uint256 _value,
        uint256 _fee, uint256 _nonce, bytes4 _methodName, bytes _args) public returns (bool);
}

contract Eureka is ERC20, ERC865Plus677ish {

    using SafeMath for uint256;

    string public constant name = "EUREKA Token";
    string public constant symbol = "EKA";
    uint8 public constant decimals = 18;

    uint256 public loyalty;
    mapping(address => mapping(address => uint256)) internal allowed;
    /* Nonces of transfers performed */
    mapping(bytes => bool) signatures;
    mapping(address => AmountReward) balances;
    uint256 public totalSupply_;
    uint256 constant public maxSupply = 298607040 * (10 ** uint256(decimals));

    uint256 constant public oneYearsInBlocks = 4 * 60 * 24 * 365;
    uint256 constant public max88 = 2**88;

    struct SnapshotReward { //256bits
        uint48 fromBlock;
        uint88 reward1;
        uint88 reward2;
        uint32 counter;
    }

    struct SnapshotAmount { //512bits
        uint48 fromBlock;
        address fromAddress;
        //0 is regular, 1 is loyalty, rest is for accumulation
        uint88 amount; //amount type 0
        uint88 claimedLoyalty; //amount type 1
        uint88 payedLoyalty;
        uint24 counter;
    }

    struct AmountReward {
        mapping(address => SnapshotReward[]) rewards;
        SnapshotAmount[] amounts;
    }

    // token lockups
    mapping(address => uint256) public lockups;

    // ownership
    address public owner;

    // minting
    bool public mintingDone = false;

    event TokensLocked(address indexed _holder, uint256 _timeout);

    event TokensLoyalty(uint256 _amount);

    constructor() public {
        owner = msg.sender;
    }

    /**
     * @dev Allows the current owner to transfer the ownership.
     * @param _newOwner The address to transfer ownership to.
     */
    function transferOwnership(address _newOwner) public {
        require(owner == msg.sender);
        owner = _newOwner;
    }

    // minting functionality
    function mint(address[] _recipients, uint256[] _amounts) public {
        require(owner == msg.sender);
        require(mintingDone == false);
        require(_recipients.length == _amounts.length);
        require(_recipients.length <= 256);

        for (uint8 i = 0; i < _recipients.length; i++) {
            address recipient = _recipients[i];
            uint256 amount = _amounts[i];

            if(balances[recipient].amounts.length == 0) {
                SnapshotAmount memory tmp;
                tmp.fromAddress = msg.sender;
                tmp.fromBlock = uint48(block.number);
                balances[recipient].amounts.push(tmp);
            }
            SnapshotAmount storage current = balances[recipient].amounts[balances[recipient].amounts.length - 1];

            uint256 tmpAmount = uint256(current.amount).add(amount);
            require(tmpAmount < max88);
            current.amount = uint88(tmpAmount);

            totalSupply_ = totalSupply_.add(amount);
            require(totalSupply_ <= maxSupply); // enforce maximum token supply

            emit Transfer(0, recipient, amount);
        }
    }

    function lockTokens(address[] _holders, uint256[] _timeouts) public {
        require(owner == msg.sender);
        require(mintingDone == false);
        require(_holders.length == _timeouts.length);
        require(_holders.length <= 256);

        for (uint8 i = 0; i < _holders.length; i++) {
            address holder = _holders[i];
            uint256 timeout = _timeouts[i];

            // make sure lockup period can not be overwritten
            require(lockups[holder] == 0);

            lockups[holder] = timeout;
            emit TokensLocked(holder, timeout);
        }
    }

    function finishMinting() public {
        require(owner == msg.sender);
        require(mintingDone == false);

        mintingDone = true;
    }

    /**
    * @dev total number of tokens in existence
    */
    function totalSupply() public view returns (uint256) {
        return totalSupply_;
    }

    /**
    * @dev transfer token for a specified address
    * @param _to The address to transfer to.
    * @param _value The amount to be transferred.
    */
    function transfer(address _to, uint256 _value) public returns (bool) {
        return transfer(_to, _value, 0);
    }

    function transfer(address _to, uint256 _value, uint8 _rewardType) public returns (bool) {
        doTransfer(msg.sender, _to, _value, 0, address(0), _rewardType);
        emit Transfer(msg.sender, _to, _value);
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _value) public returns (bool) {
        return transferFrom(_from, _to, _value, 0);
    }

    function transferFrom(address _from, address _to, uint256 _value, uint8 _rewardType) public returns (bool) {
        require(_value <= allowed[_from][msg.sender]);
        doTransfer(_from, _to, _value, 0, address(0), _rewardType);
        allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value);
        emit Transfer(_from, _to, _value);
        return true;
    }

    function reclaim(address[] loyaltyOwners) public {
        require(owner == msg.sender);
        require(mintingDone == true);

        uint256 loyalityBalanceTotal = 0;
        uint8 len = uint8(loyaltyOwners.length);
        for(uint8 i=0;i<len;i++) {
            require(balances[loyaltyOwners[i]].amounts.length > 0);
            //give the unclaimed (1 year old) loyalties to the owner
            require(balances[loyaltyOwners[i]].amounts[balances[loyaltyOwners[i]].amounts.length - 1].fromBlock + oneYearsInBlocks < block.number);
            (uint256 balance, uint256 loyaltyNow) = balanceWithLoyaltyClaimOf(loyaltyOwners[i]);
            from(balance, 0, loyaltyOwners[i]);
            loyalityBalanceTotal = loyalityBalanceTotal.add(loyaltyNow);
        }

        (uint256 toBalance, uint256 toLoyalty) = balanceWithLoyaltyClaimOf(owner);
        to(toBalance.add(toLoyalty), loyalityBalanceTotal, 0, 0, owner);
        emit Transfer(address(this), owner, loyalityBalanceTotal);
    }

    function loyalty(uint256 _amount) public {
        (uint256 balance, uint256 loyaltyNow) = balanceWithLoyaltyClaimOf(msg.sender);
        require(_amount <= balance.add(loyaltyNow));
        from(balance.add(loyaltyNow), _amount, msg.sender);
        loyalty = loyalty.add(_amount);
        emit TokensLoyalty(_amount);
    }

    function rewardOf(address _owner, address _from) public view returns (uint256, uint256, uint256) {
        //if no balances are present, the balance is 0
        if (balances[_owner].rewards[_from].length == 0) {
            return (0,0,0);
        }
        //return last amount
        SnapshotReward memory r = balances[_owner].rewards[_from][balances[_owner].rewards[_from].length - 1];
        return (r.reward1, r.reward2, r.counter);
    }

    function rewardOf(address _owner, address _from, uint48 _fromBlock) public view returns (uint256, uint256, uint256) {
        //if no balances are present, the balance is 0
        if (balances[_owner].rewards[_from].length == 0) {
            return (0,0,0);
        }
        // Binary search of the value in the array
        //TODO: check overflow
        uint256 min = 0;
        uint256 max = balances[_owner].rewards[_from].length-1;
        while (max > min) {
            uint256 mid = (max + min + 1)/ 2;
            if (balances[_owner].rewards[_from][mid].fromBlock<=_fromBlock) {
                min = mid;
            } else {
                max = mid-1;
            }
        }
        return rewardOf_internal(_owner, _from, min);
    }

    function rewardOf_internal(address _owner, address _from, uint256 _index) internal view returns (uint256, uint256, uint256) {
        SnapshotReward memory sr = balances[_owner].rewards[_from][_index];
        return (sr.reward1, sr.reward2, sr.counter);
    }


    function doTransfer(address _from, address _to, uint256 _value, uint256 _fee, address _feeAddress, uint8 _rewardType) internal {
        require(_to != address(0));
        require(mintingDone == true);

        (uint256 fromBalance, uint256 fromLoyalty) = balanceWithLoyaltyClaimOf(_from);
        if(fromLoyalty > 0) {
            emit Transfer(address(this), _from, fromLoyalty);
        }

        (uint256 toBalance, uint256 toLoyalty) = balanceWithLoyaltyClaimOf(_to);
        if(toLoyalty > 0) {
            emit Transfer(address(this), _to, toLoyalty);
        }

        uint256 totalValue = _value.add(_fee);
        require(totalValue <= fromBalance);

        // check lockups
        if (lockups[_from] != 0) {
            require(now >= lockups[_from]);
        }

        from(fromBalance.add(fromLoyalty), totalValue, _from);
        fee(_fee, _feeAddress); //event is TransferPreSigned, that will be emitted after this function call

        uint256 tmpLoyalty = 0;
        totalValue = _value;
        if(_rewardType > 0) {
            tmpLoyalty = totalValue.div(100); //1%
            totalValue = totalValue.sub(tmpLoyalty);
            emit TokensLoyalty(tmpLoyalty);
        }

        to(toBalance.add(toLoyalty), totalValue, _value, _rewardType, _to);

        if(_rewardType > 0) {
            loyalty = loyalty.add(tmpLoyalty);
        }
    }

    function balanceWithLoyaltyClaimOf(address _addr) public view returns (uint256, uint256) {
        uint256 balance = balanceOf(_addr);
        uint256 toClaim = loyalty.sub(balanceOf(_addr, false));
        return (balance, toClaim.mul(balance).div(totalSupply_));
    }

    function from(uint256 _fromBalance, uint256 _totalValue, address _fromAddress) internal {
        SnapshotAmount memory tmpFrom;
        tmpFrom.fromAddress = msg.sender;
        tmpFrom.fromBlock = uint48(block.number);
        require(loyalty < max88);
        tmpFrom.claimedLoyalty = uint88(loyalty);
        uint256 amount = _fromBalance.sub(_totalValue);
        require(amount < max88);
        tmpFrom.amount = uint88(amount);
        balances[_fromAddress].amounts.push(tmpFrom);
    }

    function fee(uint256 _fee, address _feeAddress) internal {
        if(_fee > 0 && _feeAddress != address(0)) {
            SnapshotAmount memory tmpFee;
            tmpFee.fromAddress = msg.sender;
            tmpFee.fromBlock = uint48(block.number);
            require(loyalty < max88);
            tmpFee.claimedLoyalty = uint88(loyalty); //the fee claimer cannot claim loyalty
            uint256 amount = balanceOf(_feeAddress).add(_fee);
            require(amount < max88);
            tmpFee.amount = uint88(amount);
            balances[_feeAddress].amounts.push(tmpFee);
        }
    }

    function to(uint256 _toBalance, uint256 _totalValue, uint256 _reward, uint24 _rewardType, address _toAddress) internal {
        SnapshotAmount memory tmpTo;
        tmpTo.fromAddress = msg.sender;
        tmpTo.fromBlock = uint48(block.number);
        require(loyalty < max88);
        tmpTo.claimedLoyalty = uint88(loyalty);
        uint256 amount = _toBalance.add(_totalValue);
        require(amount < max88);
        tmpTo.amount = uint88(amount);
        balances[_toAddress].amounts.push(tmpTo);

        if(_rewardType > 0) {
            SnapshotReward memory sr;
            sr.fromBlock = uint48(block.number);
            sr.reward1 = balances[_toAddress].rewards[msg.sender][balances[_toAddress].rewards[msg.sender].length - 1].reward1;
            sr.reward2 = balances[_toAddress].rewards[msg.sender][balances[_toAddress].rewards[msg.sender].length - 1].reward2;
            sr.counter = balances[_toAddress].rewards[msg.sender][balances[_toAddress].rewards[msg.sender].length - 1].counter;

            uint256 total = 0;
            if(_rewardType == 1) {
                total =  _reward.add(sr.reward1);
                require(total < max88);
                sr.reward1 = uint88(total);
            } else if(_rewardType == 2) {
                total =  _reward.add(sr.reward2);
                require(total < max88);
                sr.reward2 = uint88(total);
            } else {
                if(uint32(sr.counter + 1) > 0) { //it will always stay at max, don't overflow
                    sr.counter = uint32(sr.counter + 1);
                }
            }
            balances[_toAddress].rewards[msg.sender].push(sr);
        }
    }

    /**
    * @dev Gets the balance of the specified address.
    * @param _owner The address to query the the balance of.
    * @return An uint256 representing the amount owned by the passed address.
    */
    function balanceOf(address _owner) public view returns (uint256) {
        return balanceOf(_owner, true);
    }

    function balanceOf(address _owner, bool _amountType) public view returns (uint256) {
        //if no balances are present, the balance is 0
        if (balances[_owner].amounts.length == 0) {
            return 0;
        }
        //return last amount
        return balanceOf0(_owner, _amountType, balances[_owner].amounts.length - 1);
    }

    function balanceOf(address _owner, bool _amountType, uint64 _fromBlock) public view returns (uint256) {
        //if no balances are present, the balance is 0
        if (balances[_owner].amounts.length == 0) {
            return 0;
        }
        // Binary search of the value in the array
        //TODO: check overflow
        uint256 min = 0;
        uint256 max = balances[_owner].amounts.length-1;
        while (max > min) {
            uint256 mid = (max + min + 1)/ 2;
            if (balances[_owner].amounts[mid].fromBlock<=_fromBlock) {
                min = mid;
            } else {
                max = mid-1;
            }
        }
        return balanceOf0(_owner, _amountType, min);
    }

    function balanceOf0(address _owner, bool _amountType, uint256 _index) internal view returns (uint256) {
        if(_amountType) {
            return balances[_owner].amounts[_index].amount;
        } else {
            return balances[_owner].amounts[_index].claimedLoyalty;
        }
    }

    /**
     * @dev Approve the passed address to spend the specified amount of tokens on behalf of msg.sender.
     *
     * Beware that changing an allowance with this method brings the risk that someone may use both the old
     * and the new allowance by unfortunate transaction ordering. One possible solution to mitigate this
     * race condition is to first reduce the spender's allowance to 0 and set the desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     * @param _spender The address which will spend the funds.
     * @param _value The amount of tokens to be spent.
     */
    function approve(address _spender, uint256 _value) public returns (bool) {
        require(mintingDone == true);
        allowed[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    /**
     * @dev Function to check the amount of tokens that an owner allowed to a spender.
     * @param _owner address The address which owns the funds.
     * @param _spender address The address which will spend the funds.
     * @return A uint256 specifying the amount of tokens still available for the spender.
     */
    function allowance(address _owner, address _spender) public view returns (uint256) {
        return allowed[_owner][_spender];
    }

    /**
     * @dev Increase the amount of tokens that an owner allowed to a spender.
     *
     * approve should be called when allowed[_spender] == 0. To increment
     * allowed value is better to use this function to avoid 2 calls (and wait until
     * the first transaction is mined)
     * From MonolithDAO Token.sol
     * @param _spender The address which will spend the funds.
     * @param _addedValue The amount of tokens to increase the allowance by.
     */
    function increaseApproval(address _spender, uint _addedValue) public returns (bool) {
        require(mintingDone == true);

        allowed[msg.sender][_spender] = allowed[msg.sender][_spender].add(_addedValue);
        emit Approval(msg.sender, _spender, allowed[msg.sender][_spender]);
        return true;
    }

    /**
     * @dev Decrease the amount of tokens that an owner allowed to a spender.
     *
     * approve should be called when allowed[_spender] == 0. To decrement
     * allowed value is better to use this function to avoid 2 calls (and wait until
     * the first transaction is mined)
     * From MonolithDAO Token.sol
     * @param _spender The address which will spend the funds.
     * @param _subtractedValue The amount of tokens to decrease the allowance by.
     */
    function decreaseApproval(address _spender, uint _subtractedValue) public returns (bool) {
        require(mintingDone == true);

        uint oldValue = allowed[msg.sender][_spender];
        if (_subtractedValue > oldValue) {
            allowed[msg.sender][_spender] = 0;
        } else {
            allowed[msg.sender][_spender] = oldValue.sub(_subtractedValue);
        }
        emit Approval(msg.sender, _spender, allowed[msg.sender][_spender]);
        return true;
    }

    function transferAndCall(address _to, uint _value, bytes4 _methodName, bytes _args) public returns (bool) {
        return transferAndCall(_to, _value, 0, _methodName, _args);
    }

    // ERC677 functionality
    function transferAndCall(address _to, uint _value, uint8 _rewardType, bytes4 _methodName, bytes _args) public returns (bool) {
        require(mintingDone == true);
        //require(transfer(_to, _value, _rewardType));

        emit Transfer(msg.sender, _to, _value, _methodName, _args);

        // call receiver
        if (Utils.isContract(_to)) {
            require(_to.call(_methodName, _args));
        }
        return true;
    }

    //ERC 865 + delegate transfer and call

    function transferPreSigned(bytes _signature, address _to, uint256 _value, uint256 _fee,
        uint256 _nonce) public returns (bool) {
        return transferPreSigned(_signature, _to, _value, _fee, _nonce, 0);
    }

    function transferPreSigned(bytes _signature, address _to, uint256 _value, uint256 _fee,
        uint256 _nonce, uint8 _fromType) public returns (bool) {

        require(signatures[_signature] == false);

        bytes32 hashedTx = Utils.transferPreSignedHashing(address(this), _to, _value, _fee, _nonce);
        address from = Utils.recover(hashedTx, _signature);
        require(from != address(0));

        doTransfer(from, _to, _value, _fee, msg.sender, _fromType);
        signatures[_signature] = true;

        emit Transfer(from, _to, _value);
        emit Transfer(from, msg.sender, _fee);
        emit TransferPreSigned(from, _to, msg.sender, _value, _fee);
        return true;
    }

    function transferAndCallPreSigned(bytes _signature, address _to, uint256 _value, uint256 _fee, uint256 _nonce,
        bytes4 _methodName, bytes _args) public returns (bool) {
        return transferAndCallPreSigned(_signature, _to, _value, _fee, _nonce, 0, _methodName, _args);
    }

    function transferAndCallPreSigned(bytes _signature, address _to, uint256 _value, uint256 _fee,
        uint256 _nonce, uint8 _rewardType, bytes4 _methodName, bytes _args) public returns (bool) {

        require(signatures[_signature] == false);

        bytes32 hashedTx = Utils.transferPreSignedHashing(address(this), _to, _value, _fee, _nonce, _methodName, _args);
        address from = Utils.recover(hashedTx, _signature);
        require(from != address(0));

        doTransfer(from, _to, _value, _fee, msg.sender, _rewardType);
        signatures[_signature] = true;

        emit Transfer(from, _to, _value);
        emit Transfer(from, msg.sender, _fee);
        emit TransferPreSigned(from, _to, msg.sender, _value, _fee, _methodName, _args);

        // call receiver
        if (Utils.isContract(_to)) {
            require(_to.call(_methodName, _args));
        }
        return true;
    }

}
