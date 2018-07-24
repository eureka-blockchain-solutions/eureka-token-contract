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
 */
contract ERC677 {
    event Transfer(address indexed _from, address indexed _to, uint256 _value, bytes _data);

    function transferAndCall(address _to, uint _value, bytes _data) public returns (bool success);
}

/**
 * @title Receiver interface for ERC677 transferAndCall
 * @dev See https://github.com/ethereum/EIPs/issues/677 for specification and
 *      discussion.
 */
contract ERC677Receiver {
    function tokenFallback(address _from, uint _value, bytes _data) public;
}

contract ERC865Plus677 {
    event TransferPreSigned(address indexed _from, address indexed _to, address indexed _delegate,
        uint256 _amount, uint256 _fee);
    event TransferPreSigned(address indexed _from, address indexed _to, address indexed _delegate,
        uint256 _amount, uint256 _fee, bytes _data);

    function transferPreSigned(bytes _signature, address _to, uint256 _value,
        uint256 _fee, uint256 _nonce) public returns (bool);
    function transferAndCallPreSigned(bytes _signature, address _to, uint256 _value,
        uint256 _fee, uint256 _nonce, bytes _data) public returns (bool);
}

contract Eureka is ERC677, ERC20, ERC865Plus677 {

    using SafeMath for uint256;

    string public constant name = "EUREKA Token";
    string public constant symbol = "EKA";
    uint8 public constant decimals = 18;

    mapping(address => Snapshot[]) balances;
    uint256 public loyalty;
    mapping(address => mapping(address => uint256)) internal allowed;
    /* Nonces of transfers performed */
    mapping(bytes => bool) signatures;

    uint256 public totalSupply_;
    uint256 constant public maxSupply = 298607040 * (10 ** uint256(decimals));

    uint256 constant public oneYearsInBlocks = 4 * 60 * 24 * 365;

    //we want to create a snapshot of the token balances will fit into 2 x 256bit
    struct Snapshot {
        // `fromBlock` is the block number that the value was generated from
        uint64 fromBlock;
        address fromAddress;
        //0 is regular, 1 is loyalty, rest is for accumulation
        mapping(uint256 => uint256) amounts;
    }

    // token lockups
    mapping(address => uint256) public lockups;

    // ownership
    address public owner;

    // minting
    bool public mintingDone = false;

    event TokensLocked(address indexed _holder, uint256 _timeout);

    event TokensFrom(address indexed _holder, uint256 _amount);
    event TokensTo(address indexed _holder, uint256 _amount);
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

            if(balances[recipient].length == 0) {
                Snapshot memory tmp;
                tmp.fromAddress = tx.origin;
                tmp.fromBlock = uint64(block.number);
                balances[recipient].push(tmp);
            }
            Snapshot storage current = balances[recipient][balances[recipient].length - 1];
            current.amounts[0] = current.amounts[0].add(amount);

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

    function transfer(address _to, uint256 _value, uint8 _fromType) public returns (bool) {
        doTransfer(msg.sender, _to, _value, 0, address(0), _fromType);
        emit Transfer(msg.sender, _to, _value);
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _value) public returns (bool) {
        return transferFrom(_from, _to, _value, 0);
    }

    function transferFrom(address _from, address _to, uint256 _value, uint256 _fromType) public returns (bool) {
        require(_value <= allowed[_from][msg.sender]);
        doTransfer(_from, _to, _value, 0, address(0), _fromType);
        allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value);
        emit Transfer(_from, _to, _value);
        return true;
    }

    function reclaim(address[] loyaltyOwners) {
        require(owner == msg.sender);
        require(mintingDone == true);

        uint256 loyalityBalanceTotal = 0;
        uint8 len = uint8(loyaltyOwners.length);
        for(uint8 i=0;i<len;i++) {
            require(balances[loyaltyOwners[i]].length > 0);
            require(balances[loyaltyOwners[i]][balances[loyaltyOwners[i]].length - 1].fromBlock + oneYearsInBlocks < block.number);
            uint256 loyalityBalanceNow = claim(loyaltyOwners[i]);
            uint256 loyalityBalanceCumulated = balanceOf(loyaltyOwners[i], 1).add(loyalityBalanceNow);
            balances[loyaltyOwners[i]][balances[loyaltyOwners[i]].length - 1].amounts[1] = loyalityBalanceCumulated;

            loyalityBalanceTotal = loyalityBalanceTotal.add(loyalityBalanceNow);
        }

        //give the unclaimed (1 year old) loyalties to the owner
        Snapshot memory tmpLoyalty;
        tmpLoyalty.fromAddress = tx.origin;
        tmpLoyalty.fromBlock = uint64(block.number);
        balances[owner].push(tmpLoyalty);
        balances[owner][balances[owner].length - 1].amounts[0] = balanceOf(owner).add(loyalityBalanceTotal);
        emit Transfer(address(this), owner, loyalityBalanceTotal);
    }

    function doTransfer(address _from, address _to, uint256 _value, uint256 _fee, address _feeAddress, uint256 _fromType) internal {
        require(_to != address(0));
        uint256 fromLoyalty = 0;
        uint256 toLoyalty = 0;
        uint256 fromValue = balanceOf(_from);

        fromLoyalty = claim(_from);
        toLoyalty = claim(_to);
        fromValue = fromValue.add(fromLoyalty);
        uint256 toValue = _value.add(toLoyalty);

        uint256 total = toValue.add(_fee);
        require(total <= fromValue);
        require(mintingDone == true);
        // check lockups
        if (lockups[_from] != 0) {
            require(now >= lockups[_from]);
        }

        from(fromValue, total, fromLoyalty, _from);
        emit TokensFrom(_from, fromValue);

        fee(_fee, _feeAddress);
        //event is TransferPreSigned, that will be emitted after this function call

        if(_fromType > 1) {
            uint256 tmpLoyalty = toValue.div(100); //1%
            toValue = toValue.sub(tmpLoyalty);
            loyalty = loyalty.add(tmpLoyalty);
            emit TokensLoyalty(loyalty);
        }

        to(toValue, _value, toLoyalty, _to, _fromType);
        emit TokensTo(_to, toValue);
    }

    function claim(address _addr) public view returns (uint256) {
        uint256 maxClaim = loyalty.mul(balanceOf(_addr)).div(totalSupply_);
        uint256 alreadyClaimed = balanceOf(_addr, 1);

        return maxClaim.sub(alreadyClaimed);
    }

    function from(uint256 fromValue, uint256 total, uint256 fromLoyalty, address _from) internal {
        Snapshot memory tmpFrom;
        tmpFrom.fromAddress = tx.origin;
        tmpFrom.fromBlock = uint64(block.number);
        uint256 amounts0  = fromValue.sub(total);

        uint256 amounts1 = 0;
        if(fromLoyalty > 0) {
            amounts1 = balanceOf(_from, 1).add(fromLoyalty);
        }
        balances[_from].push(tmpFrom);

        uint256 index = balances[_from].length - 1;
        balances[_from][index].amounts[0] = amounts0;
        if(fromLoyalty > 0) {
            balances[_from][index].amounts[1] = amounts1;
        }
    }

    function fee(uint256 _fee, address _feeAddress) internal {
        if(_fee > 0 && _feeAddress != address(0)) {
            Snapshot memory tmpFee;
            tmpFee.fromAddress = tx.origin;
            tmpFee.fromBlock = uint64(block.number);
            uint256 amounts0 = balanceOf(_feeAddress).add(_fee);
            balances[_feeAddress].push(tmpFee);
            balances[_feeAddress][balances[_feeAddress].length - 1].amounts[0] = amounts0;
        }
    }

    function to(uint256 valueTo, uint256 valueToOrig, uint256 toLoyalty, address _to, uint256 _fromType) internal {
        Snapshot memory tmpTo;
        tmpTo.fromAddress = tx.origin;
        tmpTo.fromBlock = uint64(block.number);
        uint256 amounts0 = balanceOf(_to).add(valueTo);
        uint256 amounts1 = 0;
        if(toLoyalty > 0) {
            amounts1 = balanceOf(_to, 1).add(toLoyalty);
            emit Transfer(address(this), _to, toLoyalty);
        }

        uint256 amountsX = 0;
        if(_fromType > 1) { //0 is the balance, 1 is the loyality
            amountsX = balanceOf(_to, _fromType).add(valueToOrig);
        }
        balances[_to].push(tmpTo);

        uint256 index = balances[_to].length - 1;

        balances[_to][index].amounts[0] = amounts0;
        if(toLoyalty > 0) {
            balances[_to][index].amounts[1] = amounts1;
        }
        if(_fromType > 1) {
            balances[_to][index].amounts[_fromType] = amountsX;
        }
    }

    /**
    * @dev Gets the balance of the specified address.
    * @param _owner The address to query the the balance of.
    * @return An uint256 representing the amount owned by the passed address.
    */
    function balanceOf(address _owner) public view returns (uint256) {
        return balanceOf(_owner, 0);
    }

    function balanceOf(address _owner, uint256 _fromType) public view returns (uint256) {
        //if no balances are present, the balance is 0
        if (balances[_owner].length == 0) {
            return 0;
        }
        //return last amount
        return balances[_owner][balances[_owner].length - 1].amounts[_fromType];
    }

    function balanceOf(address _owner, uint256 _fromType, uint64 _fromBlock) public view returns (uint256) {
        //if no balances are present, the balance is 0
        if (balances[_owner].length == 0) {
            return 0;
        }
        // Binary search of the value in the array
        uint min = 0;
        uint max = balances[_owner].length-1;
        while (max > min) {
            uint mid = (max + min + 1)/ 2;
            if (balances[_owner][mid].fromBlock<=_fromBlock) {
                min = mid;
            } else {
                max = mid-1;
            }
        }
        return balances[_owner][min].amounts[_fromType];
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

    function transferAndCall(address _to, uint _value, bytes _data) public returns (bool) {
        return transferAndCall(_to, _value, _data, 0);
    }

    // ERC677 functionality
    function transferAndCall(address _to, uint _value, bytes _data, uint8 _fromType) public returns (bool) {
        require(mintingDone == true);
        require(transfer(_to, _value, _fromType));

        emit Transfer(msg.sender, _to, _value, _data);

        // call receiver
        if (Utils.isContract(_to)) {
            ERC677Receiver receiver = ERC677Receiver(_to);
            receiver.tokenFallback(msg.sender, _value, _data);
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
        bytes _data) public returns (bool) {
        return transferAndCallPreSigned(_signature, _to, _value, _fee, _nonce, _data, 0);
    }

    function transferAndCallPreSigned(bytes _signature, address _to, uint256 _value, uint256 _fee, uint256 _nonce,
        bytes _data, uint8 _fromType) public returns (bool) {


        require(signatures[_signature] == false);

        bytes32 hashedTx = Utils.transferPreSignedHashing(address(this), _to, _value, _fee, _nonce, _data);
        address from = Utils.recover(hashedTx, _signature);
        require(from != address(0));

        doTransfer(from, _to, _value, _fee, msg.sender, _fromType);
        signatures[_signature] = true;

        emit Transfer(from, _to, _value);
        emit Transfer(from, msg.sender, _fee);
        emit TransferPreSigned(from, _to, msg.sender, _value, _fee, _data);

        // call receiver
        if (Utils.isContract(_to)) {
            ERC677Receiver receiver = ERC677Receiver(_to);
            receiver.tokenFallback(from, _value, _data);
        }
        return true;
    }

}
