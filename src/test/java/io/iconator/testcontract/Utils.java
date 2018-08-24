package io.iconator.testcontract;

import io.iconator.testonator.Contract;
import org.ethereum.crypto.cryptohash.Keccak256;
import org.junit.Assert;
import org.web3j.abi.FunctionEncoder;
import org.web3j.abi.datatypes.*;
import org.web3j.abi.datatypes.generated.Uint256;
import org.web3j.utils.Numeric;

import java.io.File;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import static io.iconator.testonator.TestBlockchain.CREDENTIAL_2;
import static io.iconator.testonator.TestBlockchain.CREDENTIAL_3;
import static io.iconator.testonator.TestBlockchain.compile;

public class Utils {

    private static Map<String, Contract> contracts = null;

    public static Map<String, Contract> setup() throws Exception {
        if(contracts != null) {
            return contracts;
        }
        File contractFile1 = Paths.get(ClassLoader.getSystemResource("SafeMath.sol").toURI()).toFile();
        File contractFile2 = Paths.get(ClassLoader.getSystemResource("Utils.sol").toURI()).toFile();
        File contractFile3 = Paths.get(ClassLoader.getSystemResource("Eureka.sol").toURI()).toFile();
        Map<String, Contract> contracts = compile(contractFile3, contractFile1, contractFile2);
        Assert.assertEquals(5, contracts.size());
        for(String name:contracts.keySet()) {
            System.out.println("Available contract names: " + name);
        }
        Utils.contracts = contracts;
        return contracts;
    }


}
