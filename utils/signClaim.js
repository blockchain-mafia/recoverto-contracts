module.exports = function signClaim(web3, privateKey, goodID, finder, descriptionLink) {
    const account = web3.eth.accounts.privateKeyToAccount(privateKey);
    const msg = web3.eth.abi.encodeParameters(["bytes32", "address", "string"], [goodID, finder, descriptionLink]);
    const msgHash = web3.utils.sha3(msg);
    const sig = account.sign(msgHash);
    return sig;
};
