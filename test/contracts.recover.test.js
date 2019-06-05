const Recover = artifacts.require("Recover.sol");

contract("Recover contract", accounts => {
    const admin = accounts[0];
    const itemOwner = accounts[1];
    const REWARD_AMOUNT = web3.utils.toWei("1", "ether");
    const TIMEOUT_LOCKED = 0;

    let recover;

    before(async () => {
        recover = await Recover.new(
            "0x0000000000000000000000000000000000000000", // arbitrator
            "0x", // arbitratorExtraData
            "100000", // timeout
            { from: admin }
          )
    });

    it("Recover flow the sending of 2100000 wei to the `itemClaimerAccount`", async () => {
        const ITEM_ID = "0x1"
        const itemClaimerAccount = await web3.eth.accounts.create()
        const finder = accounts[2]

        // add item
        await recover.addItem(
            ITEM_ID,
            itemClaimerAccount.address, 
            "description encrypted link", 
            REWARD_AMOUNT, 
            TIMEOUT_LOCKED, 
            { from: itemOwner }
        )

        assert.isTrue(await recover.isItemExist.call(ITEM_ID))

        // fund the item claim account and send claim
        await web3.eth.sendTransaction({ from: finder, to: itemClaimerAccount.address, value: web3.utils.toWei("2100000" /* 100 Gas Price * 21000 */, "gwei") })
        const claimTx = recover.contract.methods.claim(ITEM_ID, finder, "description link")
        const claimTxSigned = await itemClaimerAccount.signTransaction({
                to: recover.address,
                data: await claimTx.encodeABI(),
                gas: parseInt(await claimTx.estimateGas({ from: itemClaimerAccount.address }) * 1.2)
            }
        )
        // claim the discovered
        await web3.eth.sendSignedTransaction(claimTxSigned.rawTransaction)
        const itemsClaimed = await recover.getPastEvents("ItemClaimed", {_itemID: ITEM_ID, _finder: finder})
        assert.equal(itemsClaimed.length, 1)
        // Owner accepts the claim.
        const claimID = itemsClaimed[0].args._claimID
        await recover.acceptClaim(claimID, {from: itemOwner, value: REWARD_AMOUNT})
        const oldBalance = await web3.eth.getBalance(finder)
        await recover.pay(claimID, REWARD_AMOUNT, {from: itemOwner})
        const newBalance = await web3.eth.getBalance(finder)
        assert.equal(web3.utils.toBN(newBalance).sub(web3.utils.toBN(oldBalance)).toString(), REWARD_AMOUNT)
    })
})
