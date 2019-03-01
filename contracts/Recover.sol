pragma solidity ^0.4.25;

import {IArbitrable, Arbitrator} from "@kleros/kleros-interaction/contracts/standard/arbitration/Arbitrator.sol";

contract Recover is IArbitrable {

    // **************************** //
    // *    Contract variables    * //
    // **************************** //

    // Amount of choices to solve the dispute if needed.
    uint8 constant AMOUNT_OF_CHOICES = 2;

    // Enum relative to different periods in the case of a negotiation or dispute.
    enum Status {NoDispute, WaitingFinder, WaitingOwner, DisputeCreated, Resolved}
    // The different parties of the dispute.
    enum Party {Owner, Finder}
    // The different ruling for the dispute resolution.
    enum RulingOptions {NoRuling, OwnerWins, FinderWins}

    struct Good {
        address owner; // Owner of the good.
        uint rewardAmount; // Amount of the reward in ETH.
        address addressForEncryption; // Address used to encrypt the link of description and to make a claim.
        string descriptionEncryptedLink; // Description encrypted link to chat/find the owner of the good (ex: IPFS URL with the encrypted description).
        uint[] claimIDs; // Collection of the claim to give back the good and get the reward.
        uint amountLocked; // Amount locked while a claim is accepted.
        uint timeoutLocked; // Timeout after which the finder can call the function `executePayment`.
        uint ownerFee; // Total fees paid by the owner of the good.
        bool exists; // Boolean to check if the good exists or not in the collection.
    }

    struct Owner {
        string description; // (optionnal) Public description of the owner (ENS, Twitter, Telegram...)
        bytes32[] goodIDs; // Owner collection of the goods.
    }

    struct Claim {
        bytes32 goodID; // Relation one-to-one with the good.
        address finder; // Address of the good finder.
        string descriptionLink; // Public link description to proof we found the good (ex: IPFS URL with the content).
        uint lastInteraction; // Last interaction for the dispute procedure.
        uint finderFee; // Total fees paid by the finder.
        uint disputeID; // If dispute exists, the ID of the claim.
        Status status; // Status of the claim relative to a dispute.
    }

    mapping(address => Owner) public owners; // Collection of the owners.

    mapping(bytes32 => Good) public goods; // Collection of the goods.

    mapping(bytes32 => uint) public goodIDtoClaimAcceptedID; // One-to-one relationship between the good and the claim accepted.
    mapping(uint => uint) public disputeIDtoClaimAcceptedID; // One-to-one relationship between the dispute and the claim accepted.

    Claim[] public claims; // Collection of the claims.
    Arbitrator arbitrator; // Address of the arbitrator contract.
    bytes arbitratorExtraData; // Extra data to set up the arbitration.
    uint public feeTimeout; // Time in seconds a party can take to pay arbitration fees before being considered unresponding and lose the dispute.

    // **************************** //
    // *          Events          * //
    // **************************** //

    /** @dev Indicate that a party has to pay a fee or would otherwise be considered as losing.
     *  @param _transactionID The index of the transaction.
     *  @param _party The party who has to pay.
     */
    event HasToPayFee(uint indexed _transactionID, Party _party);

    event GoodClaimed(bytes32 indexed goodID, address indexed finder, uint claimID);

    // **************************** //
    // *    Contract functions    * //
    // *    Modifying the state   * //
    // **************************** //

    /** @dev Constructor.
     *  @param _arbitrator The arbitrator of the contract.
     *  @param _arbitratorExtraData Extra data for the arbitrator.
     *  @param _feeTimeout Arbitration fee timeout for the parties.
     */
    constructor (
        Arbitrator _arbitrator,
        bytes memory _arbitratorExtraData,
        uint _feeTimeout
    ) public {
        arbitrator = Arbitrator(_arbitrator);
        arbitratorExtraData = _arbitratorExtraData;
        feeTimeout = _feeTimeout;
        claims.length++; // To avoid to have a claim with 0 as index.
    }

    /** @dev Add good.
     *  @param _goodID The index of the good.
     *  @param _addressForEncryption Link to the meta-evidence.
     *  @param _descriptionEncryptedLink Time after which a party can automatically execute the arbitrable transaction.
     *  @param _rewardAmount The recipient of the transaction.
     *  @param _timeoutLocked Timeout after which the finder can call the function `executePayment`.
     */
    function addGood(
        bytes32 _goodID,
        address _addressForEncryption,
        string memory _descriptionEncryptedLink,
        uint _rewardAmount,
        uint _timeoutLocked
    ) public {
        require(goods[_goodID].exists == false, "The id must be not registered.");

        // Add the good in the collection.
        goods[_goodID] = Good({
            owner: msg.sender, // The owner of the good.
            rewardAmount: _rewardAmount, // The reward to find the good.
            addressForEncryption: _addressForEncryption, // Address used to encrypt the link descritpion.
            descriptionEncryptedLink: _descriptionEncryptedLink, // Description encrypted link to chat/find the owner of the good.
            claimIDs: new uint[](0), // Empty array. There is no claims at this moment.
            amountLocked: 0, // Amount locked is 0. This variable is setting when there an accepting claim.
            timeoutLocked: _timeoutLocked, // If the a claim is accepted, time while the amount is locked.
            ownerFee: 0,
            exists: true // The good exists now.
        });

        // Add the good in the owner good collection.
        owners[msg.sender].goodIDs.push(_goodID);

        // Store the encrypted link in the meta-evidence.
        emit MetaEvidence(uint(_goodID), _descriptionEncryptedLink);
    }

    /** @dev Change the address used to encrypt the description link and the description.
     *  @param _goodID The index of the good.
     *  @param _addressForEncryption Time after which a party can automatically execute the arbitrable transaction.
     *  @param _descriptionEncryptedLink The recipient of the transaction.
     */
    function changeAddressAndDescriptionEncrypted(
        bytes32 _goodID,
        address _addressForEncryption,
        string memory _descriptionEncryptedLink
    ) public {
        Good storage good = goods[_goodID];

        require(msg.sender == good.owner, "Must be the owner of the good.");

        good.addressForEncryption = _addressForEncryption;
        good.descriptionEncryptedLink = _descriptionEncryptedLink;
    }

    /** @dev Change the reward amount of the good.
     *  @param _goodID The index of the good.
     *  @param _rewardAmount The amount of the reward for the good.
     */
    function changeRewardAmount(bytes32 _goodID, uint _rewardAmount) public {
        Good storage good = goods[_goodID];

        require(msg.sender == good.owner, "Must be the owner of the good.");

        good.rewardAmount = _rewardAmount;
    }

    /** @dev Change the reward amount of the good.
     *  @param _goodID The index of the good.
     *  @param _timeoutLocked Timeout after which the finder can call the function `executePayment`.
     */
    function changeTimeoutLocked(bytes32 _goodID, uint _timeoutLocked) public {
        Good storage good = goods[_goodID];

        require(msg.sender == good.owner, "Must be the owner of the good.");

        good.timeoutLocked = _timeoutLocked;
    }

    /** @dev Reset claims for a good.
     *  @param _goodID The ID of the good.
     */
    function resetClaims(bytes32 _goodID) public {
        Good storage good = goods[_goodID];

        require(msg.sender == good.owner, "Must be the owner of the good.");
        require(0 == good.amountLocked, "Must have no accepted claim ongoing.");

        good.claimIDs = new uint[](0);
    }

    /** @dev Claim a good.
     *  @param _goodID The index of the good.
     *  @param _finder The address of the finder.
     *  @param _descriptionLink The link to the description of the good (optionnal).
     */
    function claim(
        bytes32 _goodID,
        address _finder,
        string memory _descriptionLink
    ) public {
        _claim(msg.sender, _goodID, _finder, _descriptionLink);
    }

    function _claim (
        address claimerAddress,
        bytes32 _goodID,
        address _finder,
        string memory _descriptionLink
    ) private {
        Good storage good = goods[_goodID];

        require(
            claimerAddress == good.addressForEncryption,
            "Must be the same sender of the transaction than the address used to encrypt the message."
        );

        claims.push(Claim({
            goodID: _goodID,
            finder: _finder,
            descriptionLink: _descriptionLink,
            lastInteraction: now,
            finderFee: 0,
            disputeID: 0,
            status: Status.NoDispute
        }));

        uint claimID = claims.length - 1;
        good.claimIDs[good.claimIDs.length++] = claimID; // Adds the claim in the collection of the claim ids for this good.

        emit GoodClaimed(_goodID, _finder, claimID);
    }

    /** @dev Submimt a claim meta transaction
     */
    function claimMetaTransaction(
        bytes32 _goodID,
        address _finder,
        string memory _descriptionLink,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        Good storage good = goods[_goodID];

        string memory errorReason = validateClaimMetaTransaction(
            _goodID,
            _finder,
            _descriptionLink,
            v,
            r,
            s
        );

        if (bytes(errorReason).length > 0) {
            revert(errorReason);
        }

        _claim(
            good.addressForEncryption,
            _goodID,
            _finder,
            _descriptionLink
        );
    }

    /** @dev Accept a claim a good.
     *  @param _goodID The index of the good.
     *  @param _claimID The index of the claim.
     */
    function acceptClaim(bytes32 _goodID, uint _claimID) payable public {
        Good storage good = goods[_goodID];

        require(good.owner == msg.sender, "The sender of the transaction must be the owner of the good.");
        require(good.rewardAmount <= msg.value, "The ETH amount must be equal or higher than the reward");

        good.amountLocked += msg.value; // Locked the fund in this contract.
        goodIDtoClaimAcceptedID[_goodID] = _claimID; // Adds the claim in the claim accepted collection.
    }

    /** @dev Accept a claim a good.
     *  @param _goodID The index of the good.
     *  @param _claimID The index of the claim .
     */
    function removeClaim(bytes32 _goodID, uint _claimID) public {
        Good storage good = goods[_goodID];

        require(good.owner == msg.sender, "The sender of the transaction must be the owner of the good.");
        require(claims[_claimID].goodID == _goodID, "The claim of the good must matched with the good.");
        require(
            0 == goodIDtoClaimAcceptedID[_goodID],
            "The claim must not be accepted"
        );

        delete good.claimIDs[_claimID]; // Removes this claim in the claim collection for this good.
    }

    /** @dev Pay finder. To be called if the good has been returned.
     *  @param _goodID The index of the good.
     *  @param _amount Amount to pay in wei.
     */
    function pay(bytes32 _goodID, uint _amount) public {
        Good storage good = goods[_goodID];
        Claim storage goodClaim = claims[goodIDtoClaimAcceptedID[_goodID]];

        require(good.owner == msg.sender, "The caller must be the owner of the good.");
        require(goodClaim.status == Status.NoDispute, "The transaction of the good can't be disputed.");
        require(
            _amount <= good.amountLocked,
            "The amount paid has to be less than or equal to the amount locked."
        );

        // Checks-Effects-Interactions to avoid reentrancy.
        address finder = goodClaim.finder; // Address of the finder.

        finder.transfer(_amount); // Transfer the fund to the finder.
        good.amountLocked -= _amount;
        /*if (good.amountLocked == 0) {
            delete good.claimIDs[goodIDtoClaimAcceptedID[_goodID]];
            delete claims[goodIDtoClaimAcceptedID[_goodID]];
        }*/
        // NOTE: We keep the others claims because maybe the owner lost several goods with the same `goodID`.
    }

    /** @dev Reimburse owner of the good. To be called if the good can't be fully returned.
     *  @param _goodID The index of the good.
     *  @param _amountReimbursed Amount to reimburse in wei.
     */
    function reimburse(bytes32 _goodID, uint _amountReimbursed) public {
        Good storage good = goods[_goodID];
        Claim storage goodClaim = claims[goodIDtoClaimAcceptedID[_goodID]];

        require(goodClaim.finder == msg.sender, "The caller must be the finder of the good.");
        require(goodClaim.status == Status.NoDispute, "The transaction good can't be disputed.");
        require(
            _amountReimbursed <= good.amountLocked,
            "The amount paid has to be less than or equal to the amount locked."
        );

        address owner = good.owner; // Address of the owner.

        owner.transfer(_amountReimbursed);

        good.amountLocked -= _amountReimbursed;
    }

    /** @dev Transfer the transaction's amount to the finder if the timeout has passed.
     *  @param _goodID The index of the good.
     */
    function executeTransaction(bytes32 _goodID) public {
        Good storage good = goods[_goodID];
        Claim storage goodClaim = claims[goodIDtoClaimAcceptedID[_goodID]];

        require(goodClaim.goodID == _goodID, "The claim of the good must matched with the good.");
        require(now - goodClaim.lastInteraction >= good.timeoutLocked, "The timeout has not passed yet.");
        require(goodClaim.status == Status.NoDispute, "The transaction of the claim good can't be disputed.");

        goodClaim.finder.transfer(good.amountLocked);
        good.amountLocked = 0;

        goodClaim.status = Status.Resolved;
    }


    /* Section of Negociation or Dispute Resolution */

    /** @dev Pay the arbitration fee to raise a dispute. To be called by the owner. UNTRUSTED.
     *  Note that the arbitrator can have createDispute throw,
     *  which will make this function throw and therefore lead to a party being timed-out.
     *  This is not a vulnerability as the arbitrator can rule in favor of one party anyway.
     *  @param _goodID The index of the transaction.
     */
    function payArbitrationFeeByOwner(bytes32 _goodID) public payable {
        Good storage good = goods[_goodID];
        Claim storage goodClaim = claims[goodIDtoClaimAcceptedID[_goodID]];

        uint arbitrationCost = arbitrator.arbitrationCost(arbitratorExtraData);

        require(
            goodClaim.status < Status.DisputeCreated,
            "Dispute has already been created or because the transaction of the good has been executed."
        );
        require(goodClaim.goodID == _goodID, "The claim of the good must matched with the good.");
        require(good.owner == msg.sender, "The caller must be the owner of the good.");
        require(0 != goodIDtoClaimAcceptedID[_goodID], "The claim of the good must be accepted.");

        good.ownerFee += msg.value;
        // Require that the total paid to be at least the arbitration cost.
        require(good.ownerFee >= arbitrationCost, "The owner fee must cover arbitration costs.");

        goodClaim.lastInteraction = now;
        // The finder still has to pay. This can also happen if he has paid, but arbitrationCost has increased.
        if (goodClaim.finderFee < arbitrationCost) {
            goodClaim.status = Status.WaitingFinder;
            emit HasToPayFee(uint(_goodID), Party.Finder);
        } else { // The finder has also paid the fee. We create the dispute
            raiseDispute(_goodID, arbitrationCost);
        }
    }

    /** @dev Pay the arbitration fee to raise a dispute. To be called by the finder. UNTRUSTED.
     *  Note that this function mirrors payArbitrationFeeByFinder.
     *  @param _goodID The index of the good.
     */
    function payArbitrationFeeByFinder(bytes32 _goodID) public payable {
        Good storage good = goods[_goodID];
        Claim storage goodClaim = claims[goodIDtoClaimAcceptedID[_goodID]];
        uint arbitrationCost = arbitrator.arbitrationCost(arbitratorExtraData);

        require(
            goodClaim.status < Status.DisputeCreated,
            "Dispute has already been created or because the transaction has been executed."
        );
        require(goodClaim.goodID == _goodID, "The claim of the good must matched with the good.");
        require(goodClaim.finder == msg.sender, "The caller must be the sender.");
        require(0 != goodIDtoClaimAcceptedID[_goodID], "The claim of the good must be accepted.");

        goodClaim.finderFee += msg.value;
        // Require that the total pay at least the arbitration cost.
        require(goodClaim.finderFee >= arbitrationCost, "The finder fee must cover arbitration costs.");

        goodClaim.lastInteraction = now;

        // The owner still has to pay. This can also happen if he has paid, but arbitrationCost has increased.
        if (good.ownerFee < arbitrationCost) {
            goodClaim.status = Status.WaitingOwner;
            emit HasToPayFee(uint(_goodID), Party.Owner);
        } else { // The owner has also paid the fee. We create the dispute
            raiseDispute(_goodID, arbitrationCost);
        }
    }

    /** @dev Reimburse owner of the good if the finder fails to pay the fee.
     *  @param _goodID The index of the good.
     */
    function timeOutByOwner(bytes32 _goodID) public {
        Good storage good = goods[_goodID];
        Claim storage goodClaim = claims[goodIDtoClaimAcceptedID[_goodID]];

        require(
            goodClaim.status == Status.WaitingFinder,
            "The transaction of the good must waiting on the finder."
        );
        require(now - goodClaim.lastInteraction >= feeTimeout, "Timeout time has not passed yet.");

        executeRuling(goodIDtoClaimAcceptedID[_goodID], uint(RulingOptions.OwnerWins));
    }

    /** @dev Pay finder if owner of the good fails to pay the fee.
     *  @param _goodID The index of the good.
     */
    function timeOutByFinder(bytes32 _goodID) public {
        Good storage good = goods[_goodID];
        Claim storage goodClaim = claims[goodIDtoClaimAcceptedID[_goodID]];

        require(
            goodClaim.status == Status.WaitingOwner,
            "The transaction of the good must waiting on the owner of the good."
        );
        require(now - goodClaim.lastInteraction >= feeTimeout, "Timeout time has not passed yet.");

        executeRuling(goodIDtoClaimAcceptedID[_goodID], uint(RulingOptions.FinderWins));
    }

    /** @dev Create a dispute. UNTRUSTED.
     *  @param _goodID The index of the good.
     *  @param _arbitrationCost Amount to pay the arbitrator.
     */
    function raiseDispute(bytes32 _goodID, uint _arbitrationCost) internal {
        Good storage good = goods[_goodID];
        Claim storage goodClaim = claims[goodIDtoClaimAcceptedID[_goodID]];

        goodClaim.status = Status.DisputeCreated;
        uint disputeID = arbitrator.createDispute.value(_arbitrationCost)(AMOUNT_OF_CHOICES, arbitratorExtraData);
        disputeIDtoClaimAcceptedID[disputeID] = goodIDtoClaimAcceptedID[_goodID];
        emit Dispute(arbitrator, goodClaim.disputeID, uint(_goodID), uint(_goodID));

        // Refund finder if it overpaid.
        if (goodClaim.finderFee > _arbitrationCost) {
            uint extraFeeFinder = goodClaim.finderFee - _arbitrationCost;
            goodClaim.finderFee = _arbitrationCost;
            goodClaim.finder.send(extraFeeFinder);
        }

        // Refund owner if it overpaid.
        if (good.ownerFee > _arbitrationCost) {
            uint extraFeeOwner = good.ownerFee - _arbitrationCost;
            good.ownerFee = _arbitrationCost;
            good.owner.send(extraFeeOwner);
        }
    }

    /** @dev Submit a reference to evidence. EVENT.
     *  @param _goodID The index of the good.
     *  @param _evidence A link to an evidence using its URI.
     */
    function submitEvidence(bytes32 _goodID, string memory _evidence) public {
        Good storage good = goods[_goodID];
        Claim storage goodClaim = claims[goodIDtoClaimAcceptedID[_goodID]];

        require(
            msg.sender == good.owner || msg.sender == goodClaim.finder,
            "The caller must be the owner of the good or the finder."
        );

        require(goodClaim.status >= Status.DisputeCreated, "The dispute has not been created yet.");
        emit Evidence(arbitrator, uint(_goodID), msg.sender, _evidence);
    }

    /** @dev Appeal an appealable ruling.
     *  Transfer the funds to the arbitrator.
     *  Note that no checks are required as the checks are done by the arbitrator.
     *  @param _goodID The index of the good.
     */
    function appeal(bytes32 _goodID) public payable {
        Claim storage goodClaim = claims[goodIDtoClaimAcceptedID[_goodID]];

        require(
            msg.sender == goods[goodClaim.goodID].owner || msg.sender == goodClaim.finder,
            "The caller must be the owner of the good or the finder."
        );

        arbitrator.appeal.value(msg.value)(goodClaim.disputeID, arbitratorExtraData);
    }

    /** @dev Give a ruling for a dispute. Must be called by the arbitrator.
     *  The purpose of this function is to ensure that the address calling it has the right to rule on the contract.
     *  @param _disputeID ID of the dispute in the Arbitrator contract.
     *  @param _ruling Ruling given by the arbitrator. Note that 0 is reserved for "Not able/wanting to make a decision".
     */
    function rule(uint _disputeID, uint _ruling) public {
        require(msg.sender == address(arbitrator), "The sender of the transaction must be the arbitrator.");

        Claim storage goodClaim = claims[disputeIDtoClaimAcceptedID[_disputeID]]; // Get the claim by the dispute id.

        require(Status.DisputeCreated == goodClaim.status, "The dispute has already been resolved.");

        emit Ruling(Arbitrator(msg.sender), _disputeID, _ruling);

        executeRuling(disputeIDtoClaimAcceptedID[_disputeID], _ruling);
    }

    /** @dev Execute a ruling of a dispute. It reimburses the fee to the winning party.
     *  @param _claimID The index of the claim.
     *  @param _ruling Ruling given by the arbitrator. 1 : Reimburse the owner of the good. 2 : Pay the finder.
     */
    function executeRuling(uint _claimID, uint _ruling) internal {
        require(_ruling <= AMOUNT_OF_CHOICES, "Invalid ruling.");
        Claim storage goodClaim = claims[disputeIDtoClaimAcceptedID[_claimID]];
        Good storage good = goods[goodClaim.goodID];

        // Give the arbitration fee back.
        // Note that we use send to prevent a party from blocking the execution.
        if (_ruling == uint(RulingOptions.OwnerWins)) {
            good.owner.send(good.ownerFee + good.amountLocked);
        } else if (_ruling == uint(RulingOptions.FinderWins)) {
            goodClaim.finder.send(goodClaim.finderFee + good.amountLocked);
        } else {
            uint split_amount = (good.ownerFee + good.amountLocked) / 2;
            good.owner.send(split_amount);
            goodClaim.finder.send(split_amount);
        }

        delete good.claimIDs[disputeIDtoClaimAcceptedID[_claimID]];
        good.amountLocked = 0;
        good.ownerFee = 0;
        goodClaim.finderFee = 0;
        goodClaim.status = Status.Resolved;
    }

    // **************************** //
    // *     View functions       * //
    // **************************** //

    function isGoodExist(bytes32 _goodID) public view returns (bool) {
        return goods[_goodID].exists;
    }

    function getClaimsByGoodID(bytes32 _goodID) public view returns(uint[]) {
        return  goods[_goodID].claimIDs;
    }

    function validateClaimMetaTransaction(
        bytes32 _goodID,
        address _finder,
        string memory _descriptionLink,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public view returns (string memory errorReason) {
        Good storage good = goods[_goodID];

        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes32 msgHash = keccak256(abi.encode(_goodID, _finder, _descriptionLink));
        bytes32 prefixedHash = keccak256(abi.encodePacked(prefix, msgHash));

        if (ecrecover(prefixedHash, v, r, s) != good.addressForEncryption)
            return "Invalid signature";

        return "";
    }
}
