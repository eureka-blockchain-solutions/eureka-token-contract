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

    //we want to create a snapshot of the token balances will fit into 2 x 256bit
    struct Snapshot {
        // `fromBlock` is the block number that the value was generated from
        uint64 fromBlock;
        address fromAddress;
        //0 is regular, rest is for accumulation
        mapping(uint8 => uint256) amount;
    }

    // token lockups
    mapping(address => uint256) public lockups;

    // ownership
    address public owner;

    // minting
    bool public mintingDone = false;

    event TokensLocked(address indexed _holder, uint256 _timeout);

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
            current.amount[0] = current.amount[0].add(amount);

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

    function transferFrom(address _from, address _to, uint256 _value, uint8 _fromType) public returns (bool) {
        require(_value <= allowed[_from][msg.sender]);
        doTransfer(_from, _to, _value, 0, address(0), _fromType);
        allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value);
        emit Transfer(_from, _to, _value);
        return true;
    }

    function doTransfer(address _from, address _to, uint256 _value, uint256 _fee, address _feeAddress, uint8 _fromType) internal {
        require(_to != address(0));
        uint256 fromLoyalty = claim(_from);
        uint256 fromValue = balanceOf(_from).add(fromLoyalty);
        uint256 total = _value.add(_fee);
        require(total <= fromValue);
        require(mintingDone == true);
        // check lockups
        if (lockups[_from] != 0) {
            require(now >= lockups[_from]);
        }

        Snapshot tmpFrom;
        tmpFrom.fromAddress = tx.origin;
        tmpFrom.fromBlock = uint64(block.number);
        tmpFrom.amount[0] = fromValue.sub(total);
        if(fromLoyalty > 0) {
            tmpFrom.amount[1] = balanceOf(_from, 1).add(fromLoyalty);
        }
        balances[_from].push(tmpFrom);

        if(_fee > 0 && _feeAddress != address(0)) {
            Snapshot tmpFee;
            tmpFee.fromAddress = tx.origin;
            tmpFee.fromBlock = uint64(block.number);
            tmpFee.amount[0] = balanceOf(_feeAddress).add(_fee);
            balances[_feeAddress].push(tmpFee);
        }

        uint256 toLoyalty = claim(_to);
        uint256 valueTo = _value.add(toLoyalty);

        if(_fromType > 1) {
            uint256 loyaltyValue = _value.div(1000); //1 per mille
            valueTo = valueTo.sub(loyaltyValue);
            loyalty = loyalty.add(loyaltyValue);
        }

        Snapshot tmpTo;
        tmpTo.fromAddress = tx.origin;
        tmpTo.fromBlock = uint64(block.number);
        tmpTo.amount[0] = balanceOf(_to).add(valueTo);
        if(toLoyalty > 0) {
            tmpTo.amount[1] = balanceOf(_to, 1).add(toLoyalty);
        }

        if(_fromType > 1) { //0 is the balance, 1 is the loyality
            tmpTo.amount[_fromType] = balanceOf(_to, _fromType).add(valueTo);
        }
        balances[_to].push(tmpTo);
    }

    function claim(address _addr) internal returns (uint256) {
        uint256 maxClaim = loyalty.mul(balanceOf(_addr)).div(totalSupply_);
        uint256 alreadyClaimed = balanceOf(_addr, 1);

        return maxClaim - alreadyClaimed;
    }

    /**
    * @dev Gets the balance of the specified address.
    * @param _owner The address to query the the balance of.
    * @return An uint256 representing the amount owned by the passed address.
    */
    function balanceOf(address _owner) public view returns (uint256) {
        return balances[_owner][balances[_owner].length - 1].amount[0];
        //return balanceOf(_owner, 0, uint64(block.number));
    }

    function balanceOf(address _owner, uint8 _fromType) public view returns (uint256) {
        return balances[_owner][balances[_owner].length - 1].amount[_fromType];
        //return balanceOf(_owner, _fromType, uint64(block.number));
    }

    function balanceOf(address _owner, uint8 _fromType, uint64 _fromBlock) public view returns (uint256) {
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
        return balances[_owner][min].amount[_fromType];
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
        require(transfer(_to, _value));

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
