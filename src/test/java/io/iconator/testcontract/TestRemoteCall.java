package io.iconator.testcontract;

import io.iconator.testrpcj.Contract;
import io.iconator.testrpcj.DeployedContract;
import io.iconator.testrpcj.Event;
import io.iconator.testrpcj.TestBlockchain;
import org.ethereum.crypto.cryptohash.Keccak256;
import org.junit.After;
import org.junit.Assert;
import org.junit.BeforeClass;
import org.junit.Test;
import org.web3j.abi.FunctionEncoder;
import org.web3j.abi.datatypes.*;
import org.web3j.abi.datatypes.generated.Uint256;
import org.web3j.utils.Numeric;

import java.io.File;
import java.io.IOException;
import java.lang.reflect.InvocationTargetException;
import java.math.BigInteger;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutionException;

import static io.iconator.testrpcj.TestBlockchain.*;

public class TestRemoteCall {

    private static TestBlockchain blockchain;
    private static Map<String, Contract> contracts;

    @BeforeClass
    public static void setup() throws Exception {
        blockchain = TestBlockchain.run();
        contracts = Utils.setup();

        //compile test receiving contract
        File contractFile = Paths.get(ClassLoader.getSystemResource("TestSomeContract.sol").toURI()).toFile();
        Map<String, Contract> testContracts = compile(contractFile);
        contracts.putAll(testContracts);

    }

    @After
    public void afterTests() {
        blockchain.reset();
    }

    @Test
    public void testCallNoArgs() throws InterruptedException, ExecutionException, IOException, InvocationTargetException, NoSuchMethodException, InstantiationException, IllegalAccessException {
        DeployedContract dcEureka = blockchain.deploy(CREDENTIAL_0, contracts.get("Eureka"));
        DeployedContract dcTest = blockchain.deploy(CREDENTIAL_0, contracts.get("TestSomeContract"));
        dcEureka.addReferencedContract(dcTest.contract());

        mint(dcEureka);

        //in order to call function someName(address _from, uint256 _value, bool _testBoolean, string _testString, address[] _testArray)
        //we need to find the function hash first, use keccak for the signature: someName(address,uint256,bool,string,address[]) -> aef6af1c
        // with no arguments: "fac42a59": "someName(address,uint256)"

        byte[] hash = new Keccak256().digest("someName(address,uint256)".getBytes());
        byte[] name = new byte[4];
        System.arraycopy(hash, 0, name, 0, 4);
        String methodName = Numeric.toHexString(name);
        System.out.println("method name: "+methodName);

        List<Event> result = blockchain.call(CREDENTIAL_1, dcEureka, "transferAndCall", dcTest.contractAddress(), new BigInteger("100"), Numeric.hexStringToByteArray(methodName), new byte[0]);
        Assert.assertEquals(2, result.size());
        System.out.println(result.size());
    }

    @Test
    public void testCallSimpleArgs() throws InterruptedException, ExecutionException, IOException, InvocationTargetException, NoSuchMethodException, InstantiationException, IllegalAccessException {
        DeployedContract dcEureka = blockchain.deploy(CREDENTIAL_0, contracts.get("Eureka"));
        DeployedContract dcTest = blockchain.deploy(CREDENTIAL_0, contracts.get("TestSomeContract"));
        dcEureka.addReferencedContract(dcTest.contract());

        mint(dcEureka);

        //in order to call function someName(address _from, uint256 _value, bool _testBoolean, string _testString, address[] _testArray)
        //we need to find the function hash first, use keccak for the signature: someName(address,uint256,bool,string,address[]) -> aef6af1c
        // with one arguments:  "a67045bf": "someName(address,uint256,uint256)"

        byte[] hash = new Keccak256().digest("someName(address,uint256,uint256)".getBytes());
        byte[] name = new byte[4];
        System.arraycopy(hash, 0, name, 0, 4);
        String methodName = Numeric.toHexString(name);
        System.out.println("method name: "+methodName);

        List<Type> params = new ArrayList<Type>();
        params.add(new Uint256(new BigInteger("1234")));
        String encoded = FunctionEncoder.encodeConstructor(params);
        //parameters: 00000000000000000000000000000000000000000000000000000000000004d2
        System.out.println("parameters: "+encoded);

        List<Event> result = blockchain.call(CREDENTIAL_1, dcEureka, "transferAndCall", dcTest.contractAddress(), new BigInteger("100"), Numeric.hexStringToByteArray(methodName), Numeric.hexStringToByteArray(encoded));
        Assert.assertEquals(2, result.size());
        System.out.println(result.size());
    }

    @Test
    public void testCallComplexArgs() throws InterruptedException, ExecutionException, IOException, InvocationTargetException, NoSuchMethodException, InstantiationException, IllegalAccessException {
        DeployedContract dcEureka = blockchain.deploy(CREDENTIAL_0, contracts.get("Eureka"));
        DeployedContract dcTest = blockchain.deploy(CREDENTIAL_0, contracts.get("TestSomeContract"));
        dcEureka.addReferencedContract(dcTest.contract());

        mint(dcEureka);

        //in order to call function someName(address _from, uint256 _value, bool _testBoolean, string _testString, address[] _testArray)
        //we need to find the function hash first, use keccak for the signature: someName(address,uint256,bool,string,address[]) -> aef6af1c
        // with no arguments: "fac42a59": "someName(address,uint256)"

        byte[] hash = new Keccak256().digest("someName(address,uint256,bool,string,address[])".getBytes());
        byte[] name = new byte[4];
        System.arraycopy(hash, 0, name, 0, 4);
        String methodName = Numeric.toHexString(name);
        System.out.println("method name: "+methodName);

        List<Type> params = new ArrayList<Type>();
        params.add(new Bool(true));
        params.add(new Utf8String("testme"));
        List<Type> addresses = new ArrayList<Type>();
        addresses.add(new Address(CREDENTIAL_2.getAddress()));
        addresses.add(new Address(CREDENTIAL_3.getAddress()));
        params.add(new DynamicArray(addresses));
        String encoded = FunctionEncoder.encodeConstructor(params);
        //parameters: 000000000000000000000000cb14cf291bfd9dc1f4c78dba1e35cffd8ecf85f800000000000000000000000000000000000000000000000000000000000004d2000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000002000000000000000000000000c70df86c15e05817f1173274f886f9d7154da41b00000000000000000000000048ae229972260fa8628ce888c3f3ba11b83eae87
        System.out.println("parameters: "+encoded);


        List<Event> result = blockchain.call(CREDENTIAL_1, dcEureka, "transferAndCall", dcTest.contractAddress(), new BigInteger("100"), Numeric.hexStringToByteArray(methodName), Numeric.hexStringToByteArray(encoded));

        Assert.assertEquals(2, result.size());
        //Assert.assertEquals("testme", result.get(1).values().get(3).toString().trim());
        System.out.println(result.size());
    }

    private void mint(DeployedContract dc) throws NoSuchMethodException, InterruptedException, ExecutionException, InstantiationException, IllegalAccessException, InvocationTargetException, IOException {
        List<String> addresses = new ArrayList<>();
        List<BigInteger> values = new ArrayList<>();

        addresses.add(CREDENTIAL_1.getAddress());
        addresses.add(CREDENTIAL_2.getAddress());

        values.add(new BigInteger("20000"));
        values.add(new BigInteger("20000"));

        System.out.println(dc.contractAddress());
        List<Event> result1 = blockchain.call(dc, "mint", addresses, values);

        Assert.assertEquals(2, result1.size());
        Assert.assertEquals(new BigInteger("20000"), result1.get(0).values().get(2).getValue());

        List<Event> result2 = blockchain.call(dc, "finishMinting");
    }

}
