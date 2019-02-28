const {
    Web3HDWalletProvider,
    Recover
} = require("./recoverto-aws-lambda-bundle.js");

async function handler(provider, admin, contractAddress, event) {
    Recover.setProvider(provider);
    const recover = await Recover.at(contractAddress);

    const errorReason = await recover.validateClaimMetaTransaction.call(
        event.goodID, event.finder, event.descriptionLink,
        event.sig.v, event.sig.r, event.sig.s,
        { from: admin }
    );
    if (errorReason) {
        return {
            statusCode: 400,
            body: {
                success: false,
                reason: errorReason
            },
        };
    }

    try {
        const tx = await recover.claimMetaTransaction(
            event.goodID, event.finder, event.descriptionLink,
            event.sig.v, event.sig.r, event.sig.s,
            { from: admin }
        );
        return {
            statusCode: 200,
            body: {
                success: true,
                txHash: tx.tx
            }
        };
    } catch(error) {
        return {
            statusCode: 200,
            body: {
                success: true,
                reason: "claimMetaTransaction failed",
                error
            }
        };
    }
}

exports.testHandler = async ({provider, admin, contractAddress, event}) => {
    return await handler(provider, admin, contractAddress, event);
};

exports.handler = async (event) => {
    const provider = new Web3HDWalletProvider(
        process.env.MNEMONIC,
        process.env.PROVIDER_URL, 0, 1, {
            no_nonce_tracking: true
        });
    const admin = provider.addresses[0];
    const contractAddress = process.env.CONTRACT_ADDRESS;
    return await handler(provider, admin, contractAddress, event);
};
