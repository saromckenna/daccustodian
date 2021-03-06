require 'rspec_command'
require "json"
require_relative './accounts_helper'


# 1. A recent version of Ruby is required
# 2. Ensure the required gems are installed with `gem install rspec json rspec-command`
# 3. Run this from the command line with rspec test.rb

# Optionally output the test results with -f [p|d|h] for required views of the test results.

RSpec.configure do |config|
  config.include RSpecCommand
end

CONTRACT_OWNER_PRIVATE_KEY = '5K8eYgacDDNqPJBz7a3EV6yusLg7tTwf4i96wBs3Y2ZqwFrXPGF'
CONTRACT_OWNER_PUBLIC_KEY = 'EOS6u2zxhs6VPRU9j1XFKs65GJjf5qYsC2Ufcc9dNVBefXC4f7b4e'

CONTRACT_ACTIVE_PRIVATE_KEY = '5Jh2w4XH8jQg3XJxV1YPFH5pAqDgKR9iMwmFuePCTr7pcD8RQ5z'
CONTRACT_ACTIVE_PUBLIC_KEY = 'EOS8T3yTxnZD4fyCGR7hwzLFemgp2no2eAXZgKFzhjZhCESRrygri'


TEST_OWNER_PRIVATE_KEY = '5KdoDLgLc8shajQhT1czpVQ33pdE5bvQfLxzHSLgQKKsozgxxBb'
TEST_OWNER_PUBLIC_KEY = 'EOS6ZCSAJKqmYDxFnPTL9Srfn2Z76AFPJtfWuUFJ77YB9BfQpEmp9'

TEST_ACTIVE_PRIVATE_KEY = '5HvBdkhsNKdyHZaqTRMmEuxJWSA4ez2amL6atnGoVPRWbo9KPYz'
TEST_ACTIVE_PUBLIC_KEY = 'EOS8SPGwVZX35xVvk8TwkXzAnosHLz4ULPsXQvJj2cTf48AZjSiXr'

CONTRACT_NAME = 'daccustodian'
ACCOUNT_NAME = 'daccustodian'


beforescript = <<~SHELL
  set -x
  kill -INT `pgrep nodeos`
  rm -rf ~/Library/Application\\ Support/eosio/nodeos/data/
  if [[ $? != 0 ]] 
    then 
      echo " failed to clear out the old blocks"
      exit 1
    fi
  nodeos &>/dev/null &
  sleep 2
  cleos wallet import #{CONTRACT_ACTIVE_PRIVATE_KEY}
  cleos wallet import #{TEST_ACTIVE_PRIVATE_KEY}
  cleos create account eosio #{ACCOUNT_NAME} #{CONTRACT_OWNER_PUBLIC_KEY} #{CONTRACT_ACTIVE_PUBLIC_KEY}
  cleos create account eosio eosdactoken #{CONTRACT_OWNER_PUBLIC_KEY} #{CONTRACT_ACTIVE_PUBLIC_KEY}
  if [[ $? != 0 ]] 
    then 
      echo "Failed to create contract account" 
      exit 1
    fi
  eosiocpp -g #{CONTRACT_NAME}.abi #{CONTRACT_NAME}.cpp
  eosiocpp -o #{CONTRACT_NAME}.wast *.cpp
  if [[ $? != 0 ]] 
    then 
      echo "failed to compile contract" 
      exit 1
    fi
  cd ..
  cleos set contract #{ACCOUNT_NAME} #{CONTRACT_NAME} -p #{ACCOUNT_NAME}
  echo `pwd`

  cd eosdactoken/
  cleos set contract eosdactoken eosdactoken -p eosdactoken
  cd ../#{CONTRACT_NAME}

SHELL


describe "eosdacelect" do
  before(:all) do
    `#{beforescript}`
    fail() unless $? == 0
  end

  describe "test before all" do
    it {expect(true)}
  end

  describe "regcandidate" do
    before(:all) do
      # configure accounts for eosdactoken
      `cleos push action eosdactoken create '{ "issuer": "eosdactoken", "maximum_supply": "100000.0000 ABC", "transfer_locked": false}' -p eosdactoken`
      `cleos push action eosdactoken issue '{ "to": "eosdactoken", "quantity": "1000.0000 ABC", "memo": "Initial amount of tokens for you."}' -p eosdactoken`
      #create users
      `cleos create account eosio testreguser1 #{TEST_OWNER_PUBLIC_KEY} #{TEST_ACTIVE_PUBLIC_KEY}`
      `cleos create account eosio testreguser2 #{TEST_OWNER_PUBLIC_KEY} #{TEST_ACTIVE_PUBLIC_KEY}`
      `cleos create account eosio testreguser3 #{TEST_OWNER_PUBLIC_KEY} #{TEST_ACTIVE_PUBLIC_KEY}`
      `cleos create account eosio testreguser4 #{TEST_OWNER_PUBLIC_KEY} #{TEST_ACTIVE_PUBLIC_KEY}`
      # `cleos create account eosio testreguser5 #{TEST_OWNER_PUBLIC_KEY} #{TEST_ACTIVE_PUBLIC_KEY}`
      # Issue tokens to the first accounts in the token contract
      `cleos push action eosdactoken issue '{ "to": "testreguser1", "quantity": "100.0000 ABC", "memo": "Initial amount."}' -p eosdactoken`
      `cleos push action eosdactoken issue '{ "to": "testreguser2", "quantity": "100.0000 ABC", "memo": "Initial amount."}' -p eosdactoken`
      `cleos push action eosdactoken issue '{ "to": "testreguser3", "quantity": "100.0000 ABC", "memo": "Initial amount."}' -p eosdactoken`
      `cleos push action eosdactoken issue '{ "to": "testreguser4", "quantity": "100.0000 ABC", "memo": "Initial amount."}' -p eosdactoken`
      # `cleos push action eosdactoken issue '{ "to": "testreguser5", "quantity": "100.0000 ABC", "memo": "Initial amount."}' -p eosdactoken`
      # Add the founders to the memberreg table
      `cleos push action eosdactoken memberreg '{ "sender": "testreguser1", "agreedterms": "initaltermsagreedbyuser"}' -p testreguser1`
      # `cleos push action eosdactoken memberreg '{ "sender": "testreguser2", "agreedterms": "initaltermsagreedbyuser"}' -p testreguser2` # not registered
      `cleos push action eosdactoken memberreg '{ "sender": "testreguser3", "agreedterms": ""}' -p testreguser3` # empty terms
      `cleos push action eosdactoken memberreg '{ "sender": "testreguser4", "agreedterms": "oldterms"}' -p testreguser4`
      # `cleos push action eosdactoken memberreg '{ "sender": "testreguser5", "agreedterms": "initaltermsagreedbyuser"}' -p testreguser5`
    end

    context "with valid and member registered user" do
      command %(cleos push action daccustodian regcandidate '{ "cand": "testreguser1", "bio": "any bio", "requestedpay": "11.5000 ABC"}' -p testreguser1), allow_error: true
      its(:stdout) {is_expected.to include('daccustodian::regcandidate')}
      # its(:stderr) {is_expected.to include('no error')}
    end

    context "with unregistered user" do
      command %(cleos push action daccustodian regcandidate '{ "cand": "testreguser2", "bio": "any bio", "requestedpay": "10.0000 ABC"}' -p testreguser2), allow_error: true
      # its(:stdout) {is_expected.to include('daccustodian::regcandidate')}
      its(:stderr) {is_expected.to include('Account is not registered with members')}
    end

    context "with user with empty agree terms" do
      command %(cleos push action daccustodian regcandidate '{ "cand": "testreguser3", "bio": "any bio", "requestedpay": "10.0000 ABC"}' -p testreguser3), allow_error: true
      # its(:stdout) {is_expected.to include('daccustodian::regcandidate')}
      its(:stderr) {is_expected.to include('Account has not agreed any to terms')}
    end

    context "with user with old agreed terms" do
      command %(cleos push action daccustodian regcandidate '{ "cand": "testreguser4", "bio": "any bio", "requestedpay": "10.0000 ABC"}' -p testreguser4), allow_error: true
      # its(:stdout) {is_expected.to include('daccustodian::regcandidate')}
      its(:stderr) {is_expected.to include('Account has not agreed to current terms')}
    end

    context "with user is already registered" do
      command %(cleos push action daccustodian regcandidate '{ "cand": "testreguser1", "bio": "any bio", "requestedpay": "10.0000 ABC"}' -p testreguser1), allow_error: true
      # its(:stdout) {is_expected.to include('daccustodian::regcandidate')}
      its(:stderr) {is_expected.to include('Candidate is already registered.')}
    end

    context "Read the candidates table after" do
      command %(cleos get table daccustodian daccustodian candidates), allow_error: true
      it do
        expect(JSON.parse(subject.stdout)).to eq JSON.parse <<~JSON
{
  "rows": [{
      "candidate_name": "testreguser1",
      "bio": "any bio",
      "requestedpay": "11.5000 ABC",
      "pendreqpay": "0.0000 SYS",
      "is_custodian": 0,
      "locked_tokens": "10.0000 ABC",
      "total_votes": 0,
      "proxyfrom": []
    }
  ],
  "more": false
}
        JSON
      end
    end
  end

  describe "updateconfig" do
    context "with invalid auth" do
      command %(cleos push action daccustodian updateconfig '{ "lockupasset": "13.0000 ABC", "maxvotes": 4, "latestterms": "New Latest terms"}' -p testreguser1), allow_error: true
      # its(:stdout) {is_expected.to include('daccustodian::regcandidate')}
      its(:stderr) {is_expected.to include('missing required authority')}
    end

    context "with valid auth" do
      command %(cleos push action daccustodian updateconfig '{ "lockupasset": "13.0000 ABC", "maxvotes": 4, "latestterms": "New Latest terms"}' -p daccustodian), allow_error: true
      # its(:stdout) {is_expected.to include('daccustodian::regcandidate')}
      its(:stdout) {is_expected.to include('daccustodian::updateconfig')}
    end
  end

  describe "unregcand" do
    before(:all) do
      # configure accounts for eosdactoken
      `cleos push action eosdactoken create '{ "issuer": "eosdactoken", "maximum_supply": "100000.0000 ABD", "transfer_locked": false}' -p eosdactoken`
      `cleos push action eosdactoken issue '{ "to": "eosdactoken", "quantity": "1000.0000 ABD", "memo": "Initial amount of tokens for you."}' -p eosdactoken`
      #create users
      `cleos create account eosio unreguser1 #{TEST_OWNER_PUBLIC_KEY} #{TEST_ACTIVE_PUBLIC_KEY}`
      `cleos create account eosio unreguser2 #{TEST_OWNER_PUBLIC_KEY} #{TEST_ACTIVE_PUBLIC_KEY}`

      # Issue tokens to the first accounts in the token contract
      `cleos push action eosdactoken issue '{ "to": "unreguser1", "quantity": "100.0000 ABD", "memo": "Initial amount."}' -p eosdactoken`
      `cleos push action eosdactoken issue '{ "to": "unreguser2", "quantity": "100.0000 ABD", "memo": "Initial amount."}' -p eosdactoken`

      # Add the founders to the memberreg table
      `cleos push action eosdactoken memberreg '{ "sender": "unreguser1", "agreedterms": "New Latest terms"}' -p unreguser1`
      `cleos push action eosdactoken memberreg '{ "sender": "unreguser2", "agreedterms": "New Latest terms"}' -p unreguser2`

      `cleos push action daccustodian regcandidate '{ "cand": "unreguser2", "bio": "any bio", "requestedpay": "11.5000 ABC"}' -p unreguser2`
    end

    context "with invalid auth" do
      command %(cleos push action daccustodian unregcand '{ "cand": "unreguser3"}' -p testreguser3), allow_error: true
      # its(:stdout) {is_expected.to include('daccustodian::regcandidate')}
      its(:stderr) {is_expected.to include('missing required authority')}
    end

    context "with valid auth but not registered" do
      command %(cleos push action daccustodian unregcand '{ "cand": "unreguser1"}' -p unreguser1), allow_error: true
      its(:stderr) {is_expected.to include('Candidate is not already registered.')}
      # its(:stdout) {is_expected.to include('daccustodian::updateconfig')}
    end

    context "with valid auth" do
      command %(cleos push action daccustodian unregcand '{ "cand": "unreguser2"}' -p unreguser2), allow_error: true
      its(:stdout) {is_expected.to include('daccustodian::unregcand')}
      # its(:stderr) {is_expected.to include('daccustodian:: error occurred')}
    end
  end

  describe "update bio" do
    before(:all) do
      # configure accounts for eosdactoken
      `cleos push action eosdactoken create '{ "issuer": "eosdactoken", "maximum_supply": "100000.0000 ABC", "transfer_locked": false}' -p eosdactoken`
      `cleos push action eosdactoken issue '{ "to": "eosdactoken", "quantity": "1000.0000 ABC", "memo": "Initial amount of tokens for you."}' -p eosdactoken`
      #create users
      `cleos create account eosio updatebio1 #{TEST_OWNER_PUBLIC_KEY} #{TEST_ACTIVE_PUBLIC_KEY}`
      `cleos create account eosio updatebio2 #{TEST_OWNER_PUBLIC_KEY} #{TEST_ACTIVE_PUBLIC_KEY}`

      # Issue tokens to the first accounts in the token contract
      `cleos push action eosdactoken issue '{ "to": "updatebio1", "quantity": "100.0000 ABC", "memo": "Initial amount."}' -p eosdactoken`
      `cleos push action eosdactoken issue '{ "to": "updatebio2", "quantity": "100.0000 ABC", "memo": "Initial amount."}' -p eosdactoken`

      # Add the founders to the memberreg table
      `cleos push action eosdactoken memberreg '{ "sender": "updatebio1", "agreedterms": "New Latest terms"}' -p updatebio1`
      `cleos push action eosdactoken memberreg '{ "sender": "updatebio2", "agreedterms": "New Latest terms"}' -p updatebio2`

      `cleos push action daccustodian regcandidate '{ "cand": "updatebio2", "bio": "any bio", "requestedpay": "11.5000 ABC"}' -p updatebio2`
    end

    context "with invalid auth" do
      command %(cleos push action daccustodian updatebio '{ "cand": "updatebio1", "bio": "new bio"}' -p testreguser3), allow_error: true
      # its(:stdout) {is_expected.to include('daccustodian::regcandidate')}
      its(:stderr) {is_expected.to include('missing required authority')}
    end

    context "with valid auth but not registered" do
      command %(cleos push action daccustodian updatebio '{ "cand": "updatebio1", "bio": "new bio"}' -p updatebio1), allow_error: true
      its(:stderr) {is_expected.to include('Candidate is not already registered.')}
      # its(:stdout) {is_expected.to include('daccustodian::updateconfig')}
    end

    context "with valid auth" do
      command %(cleos push action daccustodian updatebio '{ "cand": "updatebio2", "bio": "new bio"}' -p updatebio2), allow_error: true
      its(:stdout) {is_expected.to include('daccustodian::updatebio')}
      # its(:stdout) {is_expected.to include('daccustodian::updateconfig')}
    end
  end

  describe "updatereqpay" do
    before(:all) do
      # configure accounts for eosdactoken
      `cleos push action eosdactoken create '{ "issuer": "eosdactoken", "maximum_supply": "100000.0000 ABP", "transfer_locked": false}' -p eosdactoken`
      `cleos push action eosdactoken issue '{ "to": "eosdactoken", "quantity": "1000.0000 ABP", "memo": "Initial amount of tokens for you."}' -p eosdactoken`
      #create users
      `cleos create account eosio updatepay1 #{TEST_OWNER_PUBLIC_KEY} #{TEST_ACTIVE_PUBLIC_KEY}`
      `cleos create account eosio updatepay2 #{TEST_OWNER_PUBLIC_KEY} #{TEST_ACTIVE_PUBLIC_KEY}`

      # Issue tokens to the first accounts in the token contract
      `cleos push action eosdactoken issue '{ "to": "updatepay1", "quantity": "100.0000 ABP", "memo": "Initial amount."}' -p eosdactoken`
      `cleos push action eosdactoken issue '{ "to": "updatepay2", "quantity": "100.0000 ABP", "memo": "Initial amount."}' -p eosdactoken`

      # Add the founders to the memberreg table
      `cleos push action eosdactoken memberreg '{ "sender": "updatepay1", "agreedterms": "New Latest terms"}' -p updatepay1`
      `cleos push action eosdactoken memberreg '{ "sender": "updatepay2", "agreedterms": "New Latest terms"}' -p updatepay2`

      `cleos push action daccustodian regcandidate '{ "cand": "updatepay2", "bio": "any bio", "requestedpay": "21.5000 ABP"}' -p updatepay2`
    end

    context "with invalid auth" do
      command %(cleos push action daccustodian updatereqpay '{ "cand": "updatepay1", "requestedpay": "11.5000 ABP"}' -p testreguser3), allow_error: true
      # its(:stdout) {is_expected.to include('daccustodian::regcandidate')}
      its(:stderr) {is_expected.to include('missing required authority')}
    end

    context "with valid auth but not registered" do
      command %(cleos push action daccustodian updatereqpay '{ "cand": "updatepay1", "requestedpay": "31.5000 ABP"}' -p updatepay1), allow_error: true
      its(:stderr) {is_expected.to include('Candidate is not already registered.')}
      # its(:stdout) {is_expected.to include('daccustodian::updateconfig')}
    end

    context "with valid auth" do
      command %(cleos push action daccustodian updatereqpay '{ "cand": "updatepay2", "requestedpay": "41.5000 ABP"}' -p updatepay2), allow_error: true
      its(:stdout) {is_expected.to include('daccustodian::updatereqpay')}
      # its(:stdout) {is_expected.to include('daccustodian::updateconfig')}
    end
  end

  context "Read the candidates table after change reqpay" do
    command %(cleos get table daccustodian daccustodian candidates), allow_error: true
    it do
      expect(JSON.parse(subject.stdout)).to eq JSON.parse <<~JSON
{
  "rows": [{
      "candidate_name": "testreguser1",
      "bio": "any bio",
      "requestedpay": "11.5000 ABC",
      "pendreqpay": "0.0000 SYS",
      "is_custodian": 0,
      "locked_tokens": "10.0000 ABC",
      "total_votes": 0,
      "proxyfrom": []
    },{
      "candidate_name": "updatebio2",
      "bio": "new bio",
      "requestedpay": "11.5000 ABC",
      "pendreqpay": "0.0000 SYS",
      "is_custodian": 0,
      "locked_tokens": "13.0000 ABC",
      "total_votes": 0,
      "proxyfrom": []
    },{
      "candidate_name": "updatepay2",
      "bio": "any bio",
      "requestedpay": "21.5000 ABP",
      "pendreqpay": "41.5000 ABP",
      "is_custodian": 0,
      "locked_tokens": "13.0000 ABC",
      "total_votes": 0,
      "proxyfrom": []
    }
  ],
  "more": false
}
      JSON
    end
  end

  describe "votecust" do
    before(:all) do
      # configure accounts for eosdactoken
      `cleos push action eosdactoken create '{ "issuer": "eosdactoken", "maximum_supply": "100000.0000 ABV", "transfer_locked": false}' -p eosdactoken`
      `cleos push action eosdactoken issue '{ "to": "eosdactoken", "quantity": "1000.0000 ABV", "memo": "Initial amount of tokens for you."}' -p eosdactoken`
      #create users
      `cleos create account eosio votecust1 #{TEST_OWNER_PUBLIC_KEY} #{TEST_ACTIVE_PUBLIC_KEY}`
      `cleos create account eosio votecust2 #{TEST_OWNER_PUBLIC_KEY} #{TEST_ACTIVE_PUBLIC_KEY}`
      `cleos create account eosio votecust3 #{TEST_OWNER_PUBLIC_KEY} #{TEST_ACTIVE_PUBLIC_KEY}`
      `cleos create account eosio votecust4 #{TEST_OWNER_PUBLIC_KEY} #{TEST_ACTIVE_PUBLIC_KEY}`
      `cleos create account eosio votecust5 #{TEST_OWNER_PUBLIC_KEY} #{TEST_ACTIVE_PUBLIC_KEY}`
      `cleos create account eosio votecust11 #{TEST_OWNER_PUBLIC_KEY} #{TEST_ACTIVE_PUBLIC_KEY}`
      `cleos create account eosio unrvotecust1 #{TEST_OWNER_PUBLIC_KEY} #{TEST_ACTIVE_PUBLIC_KEY}`
      `cleos create account eosio voter1 #{TEST_OWNER_PUBLIC_KEY} #{TEST_ACTIVE_PUBLIC_KEY}`
      `cleos create account eosio unregvoter #{TEST_OWNER_PUBLIC_KEY} #{TEST_ACTIVE_PUBLIC_KEY}`

      # Issue tokens to the first accounts in the token contract
      `cleos push action eosdactoken issue '{ "to": "votecust1", "quantity": "100.0000 ABV", "memo": "Initial amount."}' -p eosdactoken`
      `cleos push action eosdactoken issue '{ "to": "votecust2", "quantity": "100.0000 ABV", "memo": "Initial amount."}' -p eosdactoken`
      `cleos push action eosdactoken issue '{ "to": "votecust3", "quantity": "100.0000 ABV", "memo": "Initial amount."}' -p eosdactoken`
      `cleos push action eosdactoken issue '{ "to": "votecust4", "quantity": "100.0000 ABV", "memo": "Initial amount."}' -p eosdactoken`
      `cleos push action eosdactoken issue '{ "to": "votecust5", "quantity": "100.0000 ABV", "memo": "Initial amount."}' -p eosdactoken`
      `cleos push action eosdactoken issue '{ "to": "votecust11", "quantity": "100.0000 ABV", "memo": "Initial amount."}' -p eosdactoken`
      `cleos push action eosdactoken issue '{ "to": "unrvotecust1", "quantity": "100.0000 ABV", "memo": "Initial amount."}' -p eosdactoken`
      `cleos push action eosdactoken issue '{ "to": "voter1", "quantity": "100.0000 ABV", "memo": "Initial amount."}' -p eosdactoken`
      `cleos push action eosdactoken issue '{ "to": "unregvoter", "quantity": "100.0000 ABV", "memo": "Initial amount."}' -p eosdactoken`

      # Add the founders to the memberreg table
      `cleos push action eosdactoken memberreg '{ "sender": "votecust1", "agreedterms": "New Latest terms"}' -p votecust1`
      `cleos push action eosdactoken memberreg '{ "sender": "votecust2", "agreedterms": "New Latest terms"}' -p votecust2`
      `cleos push action eosdactoken memberreg '{ "sender": "votecust3", "agreedterms": "New Latest terms"}' -p votecust3`
      `cleos push action eosdactoken memberreg '{ "sender": "votecust4", "agreedterms": "New Latest terms"}' -p votecust4`
      `cleos push action eosdactoken memberreg '{ "sender": "votecust5", "agreedterms": "New Latest terms"}' -p votecust5`
      `cleos push action eosdactoken memberreg '{ "sender": "votecust11", "agreedterms": "New Latest terms"}' -p votecust11`
      # `cleos push action eosdactoken memberreg '{ "sender": "unrvotecust1", "agreedterms": "New Latest terms"}' -p unrvotecust1`
      `cleos push action eosdactoken memberreg '{ "sender": "voter1", "agreedterms": "New Latest terms"}' -p voter1`
      # `cleos push action eosdactoken memberreg '{ "sender": "unregvoter", "agreedterms": "New Latest terms"}' -p unregvoter`

      `cleos push action daccustodian regcandidate '{ "cand": "votecust1", "bio": "any bio", "requestedpay": "21.5000 ABV"}' -p votecust1`
      `cleos push action daccustodian regcandidate '{ "cand": "votecust2", "bio": "any bio", "requestedpay": "21.5000 ABV"}' -p votecust2`
      `cleos push action daccustodian regcandidate '{ "cand": "votecust3", "bio": "any bio", "requestedpay": "21.5000 ABV"}' -p votecust3`
      `cleos push action daccustodian regcandidate '{ "cand": "votecust4", "bio": "any bio", "requestedpay": "21.5000 ABV"}' -p votecust4`
      `cleos push action daccustodian regcandidate '{ "cand": "votecust5", "bio": "any bio", "requestedpay": "21.5000 ABV"}' -p votecust5`
      `cleos push action daccustodian regcandidate '{ "cand": "votecust11", "bio": "any bio", "requestedpay": "21.5000 ABV"}' -p votecust11`
      # `cleos push action daccustodian regcandidate '{ "cand": "unrvotecust1", "bio": "any bio", "requestedpay": "21.5000 ABV"}' -p unrvotecust1`
      `cleos push action daccustodian regcandidate '{ "cand": "voter1", "bio": "any bio", "requestedpay": "21.5000 ABV"}' -p voter1`
      # `cleos push action daccustodian regcandidate '{ "cand": "unregvoter", "bio": "any bio", "requestedpay": "21.5000 ABV"}' -p unregvoter`
    end

    context "with invalid auth" do
      command %(cleos push action daccustodian votecust '{ "voter": "voter1", "newvotes": ["votecust1","votecust2","votecust3","votecust4","votecust5"]}' -p testreguser3), allow_error: true
      # its(:stdout) {is_expected.to include('daccustodian::regcandidate')}
      its(:stderr) {is_expected.to include('missing required authority')}
    end

    context "not registered" do
      command %(cleos push action daccustodian votecust '{ "voter": "unregvoter", "newvotes": ["votecust1","votecust2","votecust3","votecust4","votecust5"]}' -p unregvoter), allow_error: true
      its(:stderr) {is_expected.to include('Account is not registered with members')}
      # its(:stdout) {is_expected.to include('daccustodian::updateconfig')}
    end

    context "voting for self" do
      command %(cleos push action daccustodian votecust '{ "voter": "voter1", "newvotes": ["voter1","votecust2","votecust3"]}' -p voter1), allow_error: true
      its(:stderr) {is_expected.to include('Member cannot vote for themselves.')}
      # its(:stdout) {is_expected.to include('daccustodian::updateconfig')}
    end

    context "exceeded allowed number of votes" do
      command %(cleos push action daccustodian votecust '{ "voter": "voter1", "newvotes": ["voter1","votecust2","votecust3","votecust4","votecust5", "votecust11"]}' -p voter1), allow_error: true
      its(:stderr) {is_expected.to include('Number of allowed votes was exceeded.')}
      # its(:stdout) {is_expected.to include('daccustodian::updateconfig')}
    end

    context "with valid auth" do
      command %(cleos push action daccustodian votecust '{ "voter": "voter1", "newvotes": ["votecust1","votecust2","votecust3","votecust4"]}' -p voter1), allow_error: true
      its(:stdout) {is_expected.to include('daccustodian::votecust')}
      # its(:stdout) {is_expected.to include('daccustodian::updateconfig')}
    end
  end

  context "Read the candidates table after votes" do
    command %(cleos get table daccustodian daccustodian votes), allow_error: true
    it do
      expect(JSON.parse(subject.stdout)).to eq JSON.parse <<~JSON
{
  "rows": [{
      "voter": "voter1",
      "proxy": "",
      "stake": "1398362884 ",
      "candidates": [
        "votecust1",
        "votecust2",
        "votecust3",
        "votecust4"
      ]
    }
  ],
  "more": false
}
      JSON
    end
  end
end
