const TruffleContract = require("truffle-contract");

module.exports = {
    Web3HDWalletProvider : require("web3-hdwallet-provider"),
    Recover: TruffleContract(require("../build/contracts/Recover.json")),
};
