package io.iconator.testcontract;

import io.iconator.testrpcj.Contract;
import io.iconator.testrpcj.DeployedContract;
import io.iconator.testrpcj.Event;
import io.iconator.testrpcj.TestBlockchain;
import org.junit.After;
import org.junit.Assert;
import org.junit.BeforeClass;
import org.junit.Test;
import org.web3j.abi.datatypes.Type;

import java.io.File;
import java.io.IOException;
import java.lang.reflect.InvocationTargetException;
import java.math.BigInteger;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutionException;

//in case of module error message, see:
//https://intellij-support.jetbrains.com/hc/en-us/community/posts/360000162670-In-2018-1-1-version-Problem-with-Error-cannot-start-process-the-working-directory-idea-modules-does-not-exist-?page=1#community_comment_360000142650
public class TestContract {

    private static TestBlockchain blockchain;
    private static Contract contract;
    private static Map<String, Contract> contracts;

    @BeforeClass
    public static void setup() throws Exception {
        blockchain = TestBlockchain.start();
        File contractFile1 = Paths.get(ClassLoader.getSystemResource("SafeMath.sol").toURI()).toFile();
        File contractFile2 = Paths.get(ClassLoader.getSystemResource("Utils.sol").toURI()).toFile();
        File contractFile3 = Paths.get(ClassLoader.getSystemResource("eureka.sol").toURI()).toFile();
        contracts = TestBlockchain.compileInline(contractFile3, contractFile1, contractFile2);
        Assert.assertEquals(7, contracts.size());
        for(String name:contracts.keySet()) {
            System.out.println("Available contract names: " + name);
        }
        contract = contracts.get("Eureka");
    }

    @After
    public void afterTests() {
        blockchain.reset();
    }

    @Test
    public void testContract() throws InterruptedException, ExecutionException, IOException, NoSuchMethodException, InstantiationException, IllegalAccessException, InvocationTargetException {
        DeployedContract dc = blockchain.deploy(TestBlockchain.CREDENTIAL_0, contract);
        Type t1 = blockchain.callConstant(dc, "name").get(0);
        Type t2 = blockchain.callConstant(dc, "symbol").get(0);
        Type t3 = blockchain.callConstant(dc, "decimals").get(0);
        Type t4 = blockchain.callConstant(dc, "maxSupply").get(0);

        Assert.assertEquals("EUREKA Token", t1.getValue());
        Assert.assertEquals("EKA", t2.getValue());
        Assert.assertEquals(new BigInteger("18"), t3.getValue());
        Assert.assertEquals(new BigInteger("298607040000000000000000000"), t4.getValue());
    }

    @Test
    public void testMint() throws InterruptedException, ExecutionException, IOException, NoSuchMethodException, InstantiationException, IllegalAccessException, InvocationTargetException {
        DeployedContract dc = blockchain.deploy(TestBlockchain.CREDENTIAL_0, "Eureka", contracts);
        List<String> addresses = new ArrayList<>();
        List<BigInteger> values = new ArrayList<>();

        addresses.add(TestBlockchain.CREDENTIAL_1.getAddress());
        addresses.add(TestBlockchain.CREDENTIAL_2.getAddress());
        values.add(new BigInteger("10000"));
        values.add(new BigInteger("20000"));

        System.out.println(dc.contractAddress());
        List<Event> events = blockchain.call(dc, "mint", addresses, values);

        Assert.assertEquals(2, events.size());
    }
}
