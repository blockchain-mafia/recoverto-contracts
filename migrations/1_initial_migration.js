const Migrations = artifacts.require("Migrations");
const Recover = artifacts.require("./Recover.sol");

module.exports = async function(deployer) {
    try {
        await deployer.deploy(Migrations);
        await deployer.deploy(Recover, "0x0000000000000000000000000000000000000000", "0x", 100000);
    } catch (err) {
        console.error(err.message);
        throw err;
    }
};
