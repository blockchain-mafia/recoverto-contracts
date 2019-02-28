const Recover = artifacts.require("Recover.sol");
const { signClaim } = require("../utils");
const recovertoClaimHandler = require("../aws-lambda/recoverto-claim").testHandler;

contract("Recover contract", accounts => {
    const admin = accounts[0];
    const goodOwner = accounts[1];
    const REWARD_AMOUNT = web3.utils.toWei("1", "ether");
    const TIMEOUT_LOCKED = 0;

    let recover;

    before(async () => {
        recover = await Recover.deployed();
    });

    it("Recover flow without metatx", async () => {
        const GOOD_ID = "0x1";
        const goodClaimerAccount = await web3.eth.accounts.create();
        const finder = accounts[2];

        // report new lost goodie
        await recover.addGood(GOOD_ID, goodClaimerAccount.address, "description encrypted link", REWARD_AMOUNT, TIMEOUT_LOCKED, { from: goodOwner });
        assert.isTrue(await recover.isGoodExist.call(GOOD_ID));

        // fund the good claim account and send claim
        web3.eth.sendTransaction({ from: finder, to: goodClaimerAccount.address, value: web3.utils.toWei("2100000" /* 100 Gas Price * 21000 */, "gwei") });
        const claimTx = recover.contract.methods.claim(GOOD_ID, finder, "description link");
        const claimTxSigned = await goodClaimerAccount.signTransaction({
            to: recover.address,
            data: await claimTx.encodeABI(),
            gas: parseInt(await claimTx.estimateGas({ from: goodClaimerAccount.address }) * 1.2)
        });
        await web3.eth.sendSignedTransaction(claimTxSigned.rawTransaction);
        const goodsClaimed = await recover.getPastEvents("GoodClaimed", {goodID: GOOD_ID, finder: finder});
        assert.equal(goodsClaimed.length, 1);
    });

    it("Recover flow with metatx", async () => {
        const GOOD_ID = "0x2";
        const goodClaimerAccount = await web3.eth.accounts.create();
        const finder = accounts[2];

        // report new lost good
        await recover.addGood(GOOD_ID, goodClaimerAccount.address, "description encrypted link", REWARD_AMOUNT, TIMEOUT_LOCKED, { from: goodOwner });
        assert.isTrue(await recover.isGoodExist.call(GOOD_ID));

        // request a meta transaction
        const claimMetaTxSig = signClaim(web3, goodClaimerAccount.privateKey, GOOD_ID, finder, "description link");
        const claimMetaTxResult = await recovertoClaimHandler({
            provider: web3.currentProvider,
            admin,
            contractAddress: recover.address,
            event: {
                goodID: GOOD_ID,
                finder: finder,
                descriptionLink: "description link",
                sig: {v: claimMetaTxSig.v, r: claimMetaTxSig.r, s: claimMetaTxSig.s}
            }
        });
        assert.isTrue(claimMetaTxResult.body.success);
        const goodsClaimed = await recover.getPastEvents("GoodClaimed", {goodID: GOOD_ID, finder: finder});
        assert.equal(goodsClaimed.length, 1);
    });
});
