package io.iconator.testcontract;

import io.iconator.testonator.*;
import org.junit.After;
import org.junit.Assert;
import org.junit.BeforeClass;
import org.junit.Test;
import org.web3j.abi.datatypes.Type;

import java.io.IOException;
import java.lang.reflect.InvocationTargetException;
import java.math.BigInteger;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutionException;

import static io.iconator.testonator.TestBlockchain.*;

//in case of module error message, see:
//https://intellij-support.jetbrains.com/hc/en-us/community/posts/360000162670-In-2018-1-1-version-Problem-with-Error-cannot-start-process-the-working-directory-idea-modules-does-not-exist-?page=1#community_comment_360000142650
public class TestContract {

    private static TestBlockchain blockchain;
    private static Map<String, Contract> contracts;

    @BeforeClass
    public static void setup() throws Exception {
        blockchain = TestBlockchain.run();
        contracts = TestUtils.setup();
    }

    @After
    public void afterTests() {
        blockchain.reset();
    }

    @Test
    public void testContract() throws InterruptedException, ExecutionException, IOException, NoSuchMethodException, InstantiationException, IllegalAccessException, InvocationTargetException, ConvertException {
        DeployedContract dc = blockchain.deploy(CREDENTIAL_0, contracts.get("Eureka"));
        Type t1 = blockchain.callConstant(dc, "name").get(0);
        Type t2 = blockchain.callConstant(dc, "symbol").get(0);
        Type t3 = blockchain.callConstant(dc, "decimals").get(0);
        Type t4 = blockchain.callConstant(dc, "maxSupply").get(0);

        Assert.assertEquals("EUREKA Token", t1.getValue());
        Assert.assertEquals("EKA", t2.getValue());
        Assert.assertEquals(new BigInteger("18"), t3.getValue());
        Assert.assertEquals(new BigInteger("298607040000000000000000000"), t4.getValue());
    }

    private List<Event> mint(DeployedContract dc) throws NoSuchMethodException, InterruptedException, ExecutionException, InstantiationException, IllegalAccessException, InvocationTargetException, IOException, ConvertException {
        List<String> addresses = new ArrayList<>();
        List<BigInteger> values = new ArrayList<>();

        addresses.add(CREDENTIAL_1.getAddress());
        addresses.add(CREDENTIAL_2.getAddress());

        values.add(new BigInteger("10000"));
        values.add(new BigInteger("20000"));

        System.out.println(dc.contractAddress());
        return blockchain.call(dc, "mint", addresses, values);
    }

    private List<Event> finishMint(DeployedContract dc) throws NoSuchMethodException, InterruptedException, ExecutionException, InstantiationException, IllegalAccessException, InvocationTargetException, IOException, ConvertException {
        return blockchain.call(dc, "finishMinting");
    }

    @Test
    public void testMint() throws InterruptedException, ExecutionException, IOException, NoSuchMethodException, InstantiationException, IllegalAccessException, InvocationTargetException, ConvertException {
        DeployedContract dc = blockchain.deploy(CREDENTIAL_0, "Eureka", contracts);
        List<Event> events = mint(dc);
        Assert.assertEquals(6, events.size());
        Assert.assertEquals(new BigInteger("10000"), events.get(0).values().get(2).getValue());
    }

    @Test
    public void testBalance() throws NoSuchMethodException, InterruptedException, ExecutionException, InstantiationException, IllegalAccessException, InvocationTargetException, IOException, ConvertException {
        DeployedContract dc = blockchain.deploy(CREDENTIAL_0, "Eureka", contracts);
        List<Event> events = mint(dc);
        List<Type> result = blockchain.callConstant(dc, "balanceOf", CREDENTIAL_1.getAddress());
        Assert.assertEquals(new BigInteger("10000"), result.get(0).getValue());
    }

    @Test
    public void testTransfer() throws InterruptedException, ExecutionException, IOException, InvocationTargetException, NoSuchMethodException, InstantiationException, IllegalAccessException, ConvertException {
        DeployedContract dc = blockchain.deploy(CREDENTIAL_0, "Eureka", contracts);
        List<Event> events1 = mint(dc);
        List<Event> events2 = finishMint(dc);
        List<Event> events3 = blockchain.call(dc.from(CREDENTIAL_1),"transfer", CREDENTIAL_3.getAddress(), 10000);
        List<Type> result = blockchain.callConstant(dc, "balanceOf", CREDENTIAL_3.getAddress());
        Assert.assertEquals(new BigInteger("10000"), result.get(0).getValue());
    }
}
