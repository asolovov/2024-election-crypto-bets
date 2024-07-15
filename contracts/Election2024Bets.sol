// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Uncomment this line to use console.log
// import "hardhat/console.sol";

contract Election2024Bets is Ownable, ERC2981 {
    using SafeERC20 for IERC20;

    /////////// Main contract configurations ///////////

    // Contract will be activated only if minBetsForContractActivation reached. If not reached no royalty will be
    // transferred to contract owner and users can only claim their bets back when the election will finish
    uint256 public minBetsForContractActivation  = 100;

    // If you want to bet for one candidate and other candidate has bet coefficient more than 15 bps you cannot place
    // a bet and should wait for bets for the other candidate to be placed
    uint96 public maxCoefficient = 150000; // 150000 bps == 15

    // Min bet is 20 USDT
    uint256 public minBet = 20 * 1 ether; // 20 USDT

    // Max bet is 5000 USDT
    uint256 public maxBet = 5000 * 1 ether; // 5000 USDT

    // USDT contract address
    address public allowedERC20Token = 0xdDC4e8e5923D55e1Be7b41980fDfb2f6c2aA80D4; // USDT

    // Bets cannot be placed after November 04, 2024 00:00:00 (am) in time zone America/New York (EST)
    uint256 public stopBetsTimestamp = 1730696400;

    /////////// Storage values ///////////

    enum Candidate {
        UNKNOWN, BIDEN, TRUMP
    }

    // Winner is unknown when contract is deployed
    Candidate public winner = Candidate.UNKNOWN;

    // Used to calculate total bets. Can be called as a view method
    uint256 public totalBets;

    // Used to calculate total bets value for each candidate. Can be called as a view method
    uint256 public BidenTotal;
    uint256 public TrumpTotal;

    // Used to store personal bets. You can place any bets for any candidate several times
    mapping(address => uint256) public BidenBets;
    mapping(address => uint256) public TrumpBets;

    // Used to store final coefficient after stopBetsTimestamp
    uint256 public BidenFinalCoefficient;
    uint256 public TrumpFinalCoefficient;

    // Used to store token value royalty from which can be claimed by contract owner after minBetsForContractActivation
    // is reached
    uint256 private _amountOfTokensAfterMinBetsReached;

    constructor() Ownable(msg.sender){
        // Set royalty to 5%
        _setDefaultRoyalty(msg.sender, 500); // 500 bps == 5%
    }

    /////////// User methods ///////////

    // Used to place a bet for Biden.
    //
    // tokenAmount - amount of USDT tokens to place with decimals 18. Contract should have approval
    //
    // - Max coefficient should not be reached
    // - Bet should be more than 20 USDT and less than 5000 USDT
    function placeBidenBet(uint256 tokenAmount) external {
        require(getTrumpCoefficient() <= maxCoefficient, "Election2024Bets: max coefficient reached");
        require(tokenAmount >= minBet && tokenAmount <= maxBet, "Election2024Bets: bet should be more than 20 and less than 5000");
        require(block.timestamp < stopBetsTimestamp, "Election2024Bets: bets cannot be placed");

        totalBets++;

        // Transfer tokens from user to contract
        IERC20(allowedERC20Token).safeTransferFrom(msg.sender, address(this), tokenAmount);

        // If minBetsForContractActivation reached store the token value to claim
        if (totalBets == minBetsForContractActivation) {
            _amountOfTokensAfterMinBetsReached = BidenTotal + TrumpTotal + tokenAmount;
        }

        // If total bets more than minBetsForContractActivation send royalty
        if (totalBets > minBetsForContractActivation) {
            address to;
            uint256 value;
            (to, value) = royaltyInfo(0, tokenAmount);

            IERC20(allowedERC20Token).safeTransfer(to, value);
        }

        BidenTotal += tokenAmount;
        BidenBets[msg.sender] += tokenAmount;
    }

    // Used to place a bet for Trump.
    //
    // tokenAmount - amount of USDT tokens to place with decimals 18. Contract should have approval
    //
    // - Max coefficient should not be reached
    // - Bet should be more than 20 USDT and less than 5000 USDT
    function placeTrumpBet(uint256 tokenAmount) external {
        require(getBidenCoefficient() <= maxCoefficient, "Election2024Bets: max coefficient reached");
        require(tokenAmount >= minBet && tokenAmount <= maxBet, "Election2024Bets: bet should be more than 20 and less than 5000");
        require(block.timestamp < stopBetsTimestamp, "Election2024Bets: bets cannot be placed");

        totalBets++;

        // Transfer tokens from user to contract
        IERC20(allowedERC20Token).safeTransferFrom(msg.sender, address(this), tokenAmount);

        // If minBetsForContractActivation reached store the token value to claim
        if (totalBets == minBetsForContractActivation) {
            _amountOfTokensAfterMinBetsReached = BidenTotal + TrumpTotal + tokenAmount;
        }

        // If total bets more than minBetsForContractActivation send royalty
        if (totalBets > minBetsForContractActivation) {
            address to;
            uint256 value;
            (to, value) = royaltyInfo(0, tokenAmount);

            IERC20(allowedERC20Token).safeTransfer(to, value);
        }

        TrumpTotal += tokenAmount;
        TrumpBets[msg.sender] += tokenAmount;
    }

    function claimRewardForBiden() external {
        require(winner == Candidate.BIDEN, "Election2024Bets: Biden lost");

        uint256 amount = BidenBets[msg.sender];

        require(amount > 0, "Election2024Bets: no rewards available");

        amount += (amount * BidenFinalCoefficient) / 10000;

        IERC20(allowedERC20Token).transfer(msg.sender, amount);
        BidenBets[msg.sender] = 0;
    }

    function claimRewardForTrump() external {
        require(winner == Candidate.TRUMP, "Election2024Bets: Trump lost");

        uint256 amount = TrumpBets[msg.sender];

        require(amount > 0, "Election2024Bets: no rewards available");

        amount += (amount * TrumpFinalCoefficient) / 10000;

        IERC20(allowedERC20Token).transfer(msg.sender, amount);
        TrumpBets[msg.sender] = 0;
    }

    function getBidenCoefficient() public view returns(uint96) {
        if (TrumpTotal == 0 || BidenTotal == 0) {
            return 0;
        }

        uint256 total = BidenTotal + TrumpTotal;
        return uint96((total * _feeDenominator()) / BidenTotal);
    }

    function getTrumpCoefficient() public view returns(uint96) {
        if (TrumpTotal == 0 || BidenTotal == 0) {
            return 0;
        }

        uint256 total = BidenTotal + TrumpTotal;
        return uint96((total * _feeDenominator()) / TrumpTotal);
    }

    function getCoefficients() public view returns(uint96, uint96) {
        if (TrumpTotal == 0 || BidenTotal == 0) {
            return (0, 0);
        }

        uint256 total = BidenTotal + TrumpTotal;

        uint256 biden = (total * _feeDenominator()) / BidenTotal;
        uint256 trump = (total * _feeDenominator()) / TrumpTotal;

        return (uint96(biden), uint96(trump));
    }

    /////////// Admin methods ///////////

    function setWinner(Candidate winner_) external onlyOwner {
        require(winner == Candidate.UNKNOWN, "Election2024Bets: winner already set");
        require(block.timestamp > stopBetsTimestamp, "Election2024Bets: cannot be set before stop bets timestamp");
        winner = winner_;

        BidenFinalCoefficient = getBidenCoefficient();
        TrumpFinalCoefficient = getTrumpCoefficient();
    }

    function claimRoyalty() external onlyOwner {
        require(totalBets >= minBetsForContractActivation, "Election2024Bets: cannot be claimed before total bets reached");

        address to;
        uint256 value;
        (to, value) = royaltyInfo(0, _amountOfTokensAfterMinBetsReached);

        IERC20(allowedERC20Token).safeTransfer(to, value);
    }

}
