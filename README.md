# Simple Tezos contract for upgrade strategy overhead testing

This Tezos contract is designed to let you compare the various overheads/costs of different mechanisms in upgrade strategies for smart contracts - notably contract chaining and using lambda functions. You can read the full writeup of these costs [on my blog here](https://digitalflapjack.com/blog/tezos-contract-upgrades/).

The contract itself is quite simple: it just contains a big table that can be updated via a number of contract entry points:

* Add_direct - just updates the bigmap directly in the contract you call
* Add_indirect - will call Add_direct on the nominated replacement contract, or will fail
* Add_follow_list - used to have a chain of upgrades. Will either call Add_follow_list on the replacement contract or if no replacement nominated it will update the current contracts bigmap.
* Add_lambda - same as Add_direct, however uses a function stored in the contract to do the updating rather than the contract's code directly.
* Set_replacement - nominate another contract as the replacement of this one
* Clear_replacement - sets the replacement to nil

## Security note

Note that this is just a script to let me and colleagues test things on ghostnet, so there is no security placed on who can modify the contract! If you plan to do long lived tests you probably want to add an oracle/owner field to the storage and check that before allowing calls to set/clear replacement. If not, you could  for instance easily be attacked by someone swapping your replacement to a very long chain that burns all your funds in forward calls.

## Usage

The contract is written in the CameLIGO variation of [ligo](https://ligolang.org/), and as such you will need the ligo toolchain to build the contract. You will also need some way to interact with the Tezos blockchain, and so for that I just use the tezos-client tool.

The contract contains a lambda function for the Add_labmda call, so you need to provide the michelson code when instantiating that.

To compile the basic contract you do:

```
$ ligo compile contract upgrade_strategy_test.mligo > upgrade_strategy_test.tz
```

You'll then need to compile the initial storage, which will include the michelson for the lambda function as defined in `update_table`:

```
$ ligo compile contract upgrade_strategy_test.mligo initial_storage > storage.tz
$ cat storage.tz
(Pair (Pair None {})
  { UNPAIR ;
	UNPAIR ;
	DUP 3 ;
	DUP 2 ;
	GET ;
	IF_NONE { SWAP } { DIG 2 ; ADD } ;
	DIG 2 ;
	SWAP ;
	SOME ;
	DIG 2 ;
	UPDATE })
```

You can then instantiate an instance of the upgrade contract like thus:

```
$ octez-client originate contract stage1 transferring 0 from mywallet running upgrade_.tz --init "`cat storage.tz`"
```

(In bash, you may need to do different tricks to work around the fact that the initial storage value must be a literal string depending on your shell).

I usually stand up a series of the same contract, named stage1 through to stageN (as many as you'll want in the linked list), and then I go through and link them together. To do this you'll need to know the addresses of the contracts you've instantiated:

```
$ octez-client list known contracts
stage5: KT1RGJ9Br7zRhukobkEpAVceS5DEnbbrfpzp
stage4: KT1LsmFNoapqTDmLDXwLrhja1x4sJnbGoRpa
stage3: KT19dbcrisyNy12WHsznW1fsmvzxVN6qHJsH
stage2: KT1SCMwS39apCS8odGkdg9gnGXRJUVQLuBAz
stage1: KT1BpZhLc4c5fgMxNXGbAmYdKADufhcgoeAT
mywallet: tz1WpvXwv65bFznFb2sSdw5EhPcfAnDeQ65Q
```

And then I'll link stage1 to stage2 thus:

```
$ octez-client transfer 0 from mywallet to stage1 --entrypoint set_replacement --arg '"KT1SCMwS39apCS8odGkdg9gnGXRJUVQLuBAz"' --burn-cap 1
$ octez-client transfer 0 from mywallet to stage2 --entrypoint set_replacement --arg '"KT19dbcrisyNy12WHsznW1fsmvzxVN6qHJsH"' --burn-cap 1
$ octez-client transfer 0 from mywallet to stage3 --entrypoint set_replacement --arg '"KT1LsmFNoapqTDmLDXwLrhja1x4sJnbGoRpa"' --burn-cap 1
$ octez-client transfer 0 from mywallet to stage4 --entrypoint set_replacement --arg '"KT1RGJ9Br7zRhukobkEpAVceS5DEnbbrfpzp"' --burn-cap 1
```