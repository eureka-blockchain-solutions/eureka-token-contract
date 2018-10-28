package io.iconator.testcontract;

import io.iconator.testonator.*;
import io.iconator.testonator.Event;
import org.junit.After;
import org.junit.Assert;
import org.junit.BeforeClass;
import org.junit.Test;
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

import static io.iconator.testonator.TestBlockchain.*;

public class TestRemoteCall {

    private static TestBlockchain blockchain;
    private static Map<String, Contract> contracts;

    @BeforeClass
    public static void setup() throws Exception {
        blockchain = TestBlockchain.run();
        contracts = TestUtils.setup();

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
    public void testCallNoArgs() throws InterruptedException, ExecutionException, IOException, InvocationTargetException, NoSuchMethodException, InstantiationException, IllegalAccessException, ConvertException {
        DeployedContract dcEureka = blockchain.deploy(CREDENTIAL_0, contracts.get("Eureka"));
        DeployedContract dcTest = blockchain.deploy(CREDENTIAL_0, contracts.get("TestSomeContract"));
        dcEureka.addReferencedContract(dcTest.contract());

        mint(dcEureka);

        //in order to call function someName(address _from, uint256 _value, bool _testBoolean, string _testString, address[] _testArray)
        //we need to find the function hash first, use keccak for the signature: someName(address,uint256) -> fac42a59
        String methodName = io.iconator.testonator.Utils.functionHash("someName(address,uint256)");
        System.out.println("method name: "+methodName);

        List<Event> result = blockchain.call(CREDENTIAL_1, dcEureka, "transferAndCall", dcTest.contractAddress(), new BigInteger("100"), Numeric.hexStringToByteArray(methodName), new byte[0]);
        Assert.assertEquals(3, result.size());
        System.out.println(result.size());
    }

    @Test
    public void testCallSimpleArgs() throws InterruptedException, ExecutionException, IOException, InvocationTargetException, NoSuchMethodException, InstantiationException, IllegalAccessException, ConvertException {
        DeployedContract dcEureka = blockchain.deploy(CREDENTIAL_0, contracts.get("Eureka"));
        DeployedContract dcTest = blockchain.deploy(CREDENTIAL_0, contracts.get("TestSomeContract"));
        dcEureka.addReferencedContract(dcTest.contract());

        mint(dcEureka);

        //in order to call function someName(address _from, uint256 _value, bool _testBoolean, string _testString, address[] _testArray)
        //we need to find the function hash first, use keccak for the signature: someName(address,uint256,uint256) -> a67045bf
        String methodName = io.iconator.testonator.Utils.functionHash("someName(address,uint256,uint256)");
        System.out.println("method name: "+methodName);

        String encoded = io.iconator.testonator.Utils.encodeParameters(2, new Uint256(new BigInteger("1234")));
        System.out.println("parameters: "+encoded);

        List<Event> result = blockchain.call(CREDENTIAL_1, dcEureka, "transferAndCall", dcTest.contractAddress(), new BigInteger("100"), Numeric.hexStringToByteArray(methodName), Numeric.hexStringToByteArray(encoded));
        Assert.assertEquals(3, result.size());
        Uint256 u1 = (Uint256) result.get(2).values().get(2);
        Uint256 u2 = (Uint256) result.get(2).values().get(3);
        Assert.assertEquals(new Uint256(new BigInteger("100")).getValue(), u1.getValue());
        Assert.assertEquals(new Uint256(new BigInteger("1234")).getValue(), u2.getValue());
        System.out.println(result.size());
    }

    @Test
    public void testCallComplexArgs() throws InterruptedException, ExecutionException, IOException, InvocationTargetException, NoSuchMethodException, InstantiationException, IllegalAccessException, ConvertException {
        DeployedContract dcEureka = blockchain.deploy(CREDENTIAL_0, contracts.get("Eureka"));
        DeployedContract dcTest = blockchain.deploy(CREDENTIAL_0, contracts.get("TestSomeContract"));
        dcEureka.addReferencedContract(dcTest.contract());

        mint(dcEureka);

        //in order to call function someName(address _from, uint256 _value, bool _testBoolean, string _testString, address[] _testArray)
        //we need to find the function hash first, use keccak for the signature: someName(address,uint256,bool,string,address[]) -> aef6af1c
        String methodName = io.iconator.testonator.Utils.functionHash("someName(address,uint256,bool,string,address[])");
        System.out.println("method name: "+methodName);

        List<Type> params = new ArrayList<Type>();

        String encoded = io.iconator.testonator.Utils.encodeParameters(2,
                new Bool(true),
                new Utf8String("testme"),
                io.iconator.testonator.Utils.createArray(
                        new Address(CREDENTIAL_2.getAddress()),
                        new Address(CREDENTIAL_3.getAddress()))
        );
        System.out.println("parameters: "+encoded);

        List<Event> result = blockchain.call(CREDENTIAL_1, dcEureka, "transferAndCall", dcTest.contractAddress(), new BigInteger("100"), Numeric.hexStringToByteArray(methodName), Numeric.hexStringToByteArray(encoded));

        Assert.assertEquals(3, result.size());
        Assert.assertEquals("testme", result.get(2).values().get(3).toString().trim());
        System.out.println(result.size());
    }

    private void mint(DeployedContract dc) throws NoSuchMethodException, InterruptedException, ExecutionException, InstantiationException, IllegalAccessException, InvocationTargetException, IOException, ConvertException {
        List<String> addresses = new ArrayList<>();
        List<BigInteger> values = new ArrayList<>();

        addresses.add(CREDENTIAL_1.getAddress());
        addresses.add(CREDENTIAL_2.getAddress());

        values.add(new BigInteger("20000"));
        values.add(new BigInteger("20000"));

        System.out.println(dc.contractAddress());
        List<Event> result1 = blockchain.call(dc, "mint", addresses, values);

        Assert.assertEquals(2, result1.size());
        Assert.assertEquals(new BigInteger("20000"), result1.get(1).values().get(2).getValue());

        List<Event> result2 = blockchain.call(dc, "finishMinting");
    }

}
