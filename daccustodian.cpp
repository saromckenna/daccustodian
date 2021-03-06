#include <eosiolib/eosio.hpp>
#include <eosiolib/multi_index.hpp>
#include <eosiolib/singleton.hpp>
#include <eosiolib/asset.hpp>
#include "daccustodian.hpp"
#include <typeinfo>

#include <string>

using namespace eosio;
using namespace std;

struct contract_config {
    asset lockupasset = asset(100000, S(4, ABC));
    uint8_t maxvotes = 5;
    string latestterms = "initaltermsagreedbyuser";

    EOSLIB_SERIALIZE(contract_config, (lockupasset)(maxvotes)(latestterms))
};

// @abi table candidates
struct candidate {
    name candidate_name;
    string bio;
    asset requestedpay; // Active requested pay used for payment calculations.
    asset pendreqpay; // requested pay that would be pending until the new period begins. Then it should be moved to requestedpay.
    uint8_t is_custodian; // bool
    asset locked_tokens;
    uint32_t total_votes;
    vector<name> proxyfrom;

    name primary_key() const { return candidate_name; }

    EOSLIB_SERIALIZE(candidate, (candidate_name)(bio)(requestedpay)(pendreqpay)(is_custodian)(locked_tokens)(total_votes)(proxyfrom))
};

// @abi table votes
struct vote {
    name voter;
    name proxy;
    asset stake;
    vector<name> candidates;

    account_name primary_key()const { return voter; }
    account_name by_proxy() const { return static_cast<uint64_t>(proxy); }

    EOSLIB_SERIALIZE(vote, (voter)(stake)(proxy)(candidates))
};

typedef multi_index<N(candidates), candidate> candidates_table;

typedef eosio::multi_index<N(votes), vote,
indexed_by< N(byproxy), const_mem_fun<vote, account_name, &vote::by_proxy> >
> votes_table;

typedef singleton<N(config), contract_config> configscontainer;

class daccustodian : public contract {

private:
    configscontainer config_singleton;
    candidates_table registered_candidates;
    votes_table votes_cast_by_members;

public:

    daccustodian(account_name self)
    : contract(self),
    registered_candidates(_self, _self),
    votes_cast_by_members(_self, _self),
    config_singleton(_self, _self) {

//        configs = config_singleton.get_or_create(_self);
    }

    contract_config configs() {
        contract_config conf = config_singleton.exists() ? config_singleton.get() : contract_config();
        config_singleton.set(conf, _self);
        return conf;
    }

    void updateconfig(asset lockupasset, uint8_t maxvotes, string latestterms) {
        require_auth(_self);
        contract_config newconfig{lockupasset,maxvotes,latestterms};
        config_singleton.set(newconfig, _self);
    }

    void assert_valid_membership(name member) {
        regmembers reg_members(N(eosdactoken), N(eosdactoken));
        const auto &regmem = reg_members.get(member, "Account is not registered with members");
        eosio_assert(!regmem.agreedterms.empty(), "Account has not agreed any to terms");
        eosio_assert(regmem.agreedterms == configs().latestterms, "Account has not agreed to current terms");
    }

    void regcandidate(name cand, string bio, asset requestedpay) {
        /* From Tech Doc vvvv
         * 1. Check the message has the permission of the account registering, and that account has agreed to the membership agreement
         * 2. Query the candidate table to see if the account is already registered.
         * 3. If the candidate is already registered then check if new_config is present
         * 4. Insert the candidate record into the database, making sure to set elected to 0
         * 5. Check that the message has permission to transfer tokens, assert if not
         * 6. Transfer the configurable number of tokens which need to be locked to the contract account and assert if this fails
         * From Tech doc ^^^^
         */
        print("regcandidate...");
        require_auth(cand);
        assert_valid_membership(cand);
        account_name tokencontract = N(eosdactoken);

        auto reg_candidate = registered_candidates.find(cand);
        eosio_assert(reg_candidate == registered_candidates.end(), "Candidate is already registered.");

//        action(
//                {permission_level{cand, N(active)}},
//                N(eosdactoken), N(transfer),
//                std::make_tuple(cand, _self, configs().lockupasset, "Candidate lockup amount")
//        ).send();

        registered_candidates.emplace(_self, [&](candidate &c) {
            c.candidate_name = cand;
            c.bio = bio;
            c.requestedpay = requestedpay;
            c.is_custodian = false;
            c.locked_tokens = configs().lockupasset;
            c.total_votes = 0;
        });
    }

    void unregcand(name cand) {
        print("unregcand...");

        require_auth(cand);
        const auto &reg_candidate = registered_candidates.get(cand, "Candidate is not already registered.");

        //TODO: In order to return staked funds I think the following will need to be owner driven, multisig (with the owner)
        // or a transaction that will go into a pending buffer of transactions to be drained periodically by the contract owner.
//        action(
//               permission_level{N(eosdactoken), N(active)},
//               N(eosdactoken), N(transfer),
//               std::make_tuple(_self, cand, reg_candidate.locked_tokens, "Returning candidate lockup amount")
//               ).send();
        registered_candidates.erase(reg_candidate);
    }

    void updatebio(name cand, string bio) {
        print("updatebio...");

        require_auth(cand);
        const auto &reg_candidate = registered_candidates.get(cand, "Candidate is not already registered.");

        registered_candidates.modify(reg_candidate, 0, [&](candidate &c) {
            c.bio = bio;
        });
    }

    void updatereqpay(name cand, asset requestedpay) {
        print("updateconfig...");

        require_auth(cand);
        const auto &reg_candidate = registered_candidates.get(cand, "Candidate is not already registered.");

        //TODO: If this should only reset on the next period then this should get saved on
        // a "pendreqpay" until the next period. Then move to requestedPay in order to save both states.
        registered_candidates.modify(reg_candidate, 0, [&](candidate &c) {
            c.pendreqpay = requestedpay;
        });
    }

    void claimpay(name cand) {
        print("claimpay...");
        require_auth(cand);
        /*
         * Feels like this should be in the custodian rewards contract.
         * Also in order to send pay this will need permission of contract owner so should probably be `sendpay` instead.
         * Otherwise could follow a similar pattern suggested in unreg with a pending transaction buffer.
         * Copied from tech doc VVVVV
         1. Check the message has permission of the account
         2. Check if there is a record in the CustodianReward table, if there is not then assert
         3. If the account has an outstanding balance then send it to the account, otherwise assert
         4. Remove the record in the CustodianReward table
         * Copied from tech doc ^^^^^

         */
    }

    int64_t acquired_vote_weight(vote existing_vote) {
        auto proxyIndex = votes_cast_by_members.get_index<N(byproxy)>();
        auto proxied_to_voter = proxyIndex.find(existing_vote.voter);

        int64_t vote_added_weight = existing_vote.stake.amount;
        while (proxied_to_voter != proxyIndex.end() && proxied_to_voter->voter == existing_vote.voter) {
            vote_added_weight += proxied_to_voter->stake.amount;
        }
        return vote_added_weight;
    }

    void votecust(name voter, vector<name> newvotes) {
        /*
         * From Tech doc vvvv
         1. Check that the message has voting permission of account
         2. For each of the votes_cast_by_members, check that the account names are registered as custodian candidates.  Assert if any of the accounts are not registered as candidates
         3. Save the votes in the CandidateVotes table, update if the voting account already has a record
         * From Tech doc ^^^^
         */
        print("votecust...");
        require_auth(voter);
        assert_valid_membership(voter);
        eosio_assert(newvotes.size() <= configs().maxvotes, "Number of allowed votes was exceeded.");
        /*
         * The deltaVotes approach aims to find a minimal change set of votes as a map<name,int_8>.
         * If a new votee is added it will have a +1
         * If a votee is removed it will have -1
         * If the vote is unchanged then it will be removed in preparation for the next step.
         */
        map<name, int> deltaVotes;

        for (const auto &newVote : newvotes) {
            eosio_assert(voter != newVote, "Member cannot vote for themselves.");
            // Add vote with +1
            deltaVotes.insert(make_pair(newVote, 1));
        }

        // Find a vote that has been cast by this voter previously.
        auto existingVote = votes_cast_by_members.find(voter);
        if (existingVote != votes_cast_by_members.end()) {
            for (const auto &currentVotedCandidate : existingVote->candidates) {
                // If vote is no longer present decrement vote count on currentVotedCandidate.
                if (deltaVotes.find(currentVotedCandidate) == deltaVotes.end()) {
                    deltaVotes.insert(make_pair(currentVotedCandidate, -1));
                } else {
                    // remove vote from delta if no change to avoid uneeded action below.
                    deltaVotes.erase(currentVotedCandidate);
                }
            }

            int64_t vote_added_weight = acquired_vote_weight(*existingVote);

            for (auto &voteChange : deltaVotes) {
                auto candidate = registered_candidates.get(voteChange.first, "Candidate is not registered for voting");
                registered_candidates.modify(candidate, 0, [&](auto &c) {
                    c.total_votes += voteChange.second * vote_added_weight;
                });
            }

            votes_cast_by_members.modify(existingVote, _self, [&](vote &v) {
                v.candidates = newvotes;
                v.proxy = name();
            });
        } else {
            votes_cast_by_members.emplace(_self, [&](vote &v) {
                v.voter = voter;
                v.candidates = newvotes;
            });
        }
    }

    void voteproxy(name voter, name proxy) {
        /*
         1. Check that the message has voting permission of account
         2. If proxy is not null then set that account as a proxy for all votes_cast_by_members from account
         */
        print("voteproxy...");
        require_auth(voter);

        auto existingVote = votes_cast_by_members.find(voter);

        int64_t vote_added_weight = acquired_vote_weight(*existingVote);

        if (existingVote != votes_cast_by_members.end()) {
            for (const auto &currentVotedCandidate : existingVote->candidates) {

                auto candidate = registered_candidates.get(currentVotedCandidate, "Candidate is not registered for voting");

                registered_candidates.modify(candidate, 0, [&](auto &c) {
                    c.total_votes -= vote_added_weight;
                });
            }
            votes_cast_by_members.modify(existingVote, _self, [&](vote &v) {
                v.candidates.clear();
                v.proxy = proxy;
            });
        } else {
            votes_cast_by_members.emplace(_self, [&](vote &v) {
                v.voter = voter;
                v.proxy = proxy;
            });
        }
    }

    void newperiod(string message) {
        print("newperiod...");
        /* Copied from the Tech Doc vvvvv
         // 1. Distribute custodian pay based on the median of requested pay for all currently elected candidates

         // 2. Tally the current votes_cast_by_members and prepare a list of the winning custodians
         // 3. Assigns the custodians, this may include updating a multi-sig wallet which controls the funds in the DAC as well as updating DAC contract code
         * Copied from the Tech Doc ^^^^^
         */
    }

    //    asset getMedianPay() {
    //        //TODO: Add index to candidates to sort by requestedPay. Then find the middle record from the collection.
    ////        candidates.find()
    ////        return asset{};
    //    }
};

EOSIO_ABI(daccustodian, (updateconfig)(regcandidate)(unregcand)(updatebio)(updatereqpay)(claimpay)(votecust)(voteproxy)(newperiod))
