// A simple table of numbers contract that I used to let me compare the costs in Tez for different
// update mechanisms. With this contract you can do the following
//
// * Add_direct - lets you update the big map in the contract's storage directly
// * Add_lambda - lets you update the big map using a function stored in storage not in the contract directly
// * Add_indirect - lets you call the add_direct method of the contract nominated as a replacement
// * Add_follow_list - lets you follow a chain of replacements until the last contract in the chain
//
// There is also a set/clear replacement address pair of entrypoints.

type update_function = ((nat * nat * (nat, nat) big_map) -> (nat, nat) big_map)

type storage = {
	update_f: update_function;
	table: (nat, nat) big_map;
	replacement: address option;
}

let update_table: update_function =
		fun (index, update, table: nat * nat * (nat, nat) big_map): (nat, nat) big_map ->
	let new_val: nat =
		let opt_val: nat option =
			Big_map.find_opt index table
		in
			match opt_val with
				| None -> update
				| Some x -> x + update
	in
		Big_map.update index (Some new_val) table

let initial_storage: storage = {
	update_f = update_table;
	table = (Big_map.empty : (nat, nat) big_map) ;
	replacement = None;
}

type result = (operation list) * storage

type update_parameters = {
	index: nat;
	update: nat;
}

type entrypoint =
| Add_direct of update_parameters
| Add_lambda of update_parameters
| Set_replacement of address
| Clear_replacement of unit
| Add_indirect of update_parameters
| Add_follow_list of update_parameters


let add_direct(param : update_parameters) (storage : storage) : result =
	let new_val: nat =
		let opt_val: nat option =
			Big_map.find_opt param.index storage.table
		in
			match opt_val with
				| None -> param.update
				| Some x -> x + param.update
	in
		([] : operation list),
		{ storage with table = Big_map.update param.index (Some new_val) storage.table; }


let add_lambda(param : update_parameters) (storage : storage) : result =
	let uf: update_function = storage.update_f in
	let update = uf (param.index, param.update, storage.table) in
	([] : operation list),
	{ storage with table = update; }


let set_replacement(param : address) (storage: storage) : result =
	([] : operation list),
	{ storage with replacement = Some param; }


let clear_replacement(_param : unit) (storage: storage) : result =
	([] : operation list),
	{ storage with replacement = None; }


let add_indirect(param: update_parameters) (storage: storage) : result =
	let upstream_op =
		let upstream_addr = match storage.replacement with
			| None -> (failwith 42n)
			| Some addr -> addr
		in
			let entrypoint_add_direct =
				match (Tezos.get_entrypoint_opt "%add_direct" upstream_addr : update_parameters contract option) with
				| None -> (failwith 43n)
				| Some c -> c
			in
				Tezos.transaction param 0tez entrypoint_add_direct
	in
		([upstream_op;] : operation list), storage


let upstream_list_op (upstream_addr: address) (param: update_parameters): operation =
	let entrypoint_add_follow_list =
		match (Tezos.get_entrypoint_opt "%add_follow_list" upstream_addr : update_parameters contract option) with
		| None -> (failwith 43n)
		| Some c -> c
	in
		Tezos.transaction param 0tez entrypoint_add_follow_list

let add_follow_list(param: update_parameters) (storage: storage) : result =
	let upstream_ops =
		match storage.replacement with
			| None -> ([] : operation list)
			| Some addr -> [ upstream_list_op addr param; ]
	in
	let updated_storage: storage =
		match storage.replacement with
			| None -> { storage with table = update_table (param.index, param.update, storage.table); }
			| Some _ -> storage
	in
		upstream_ops, updated_storage



let rec main ((entrypoint, storage) : entrypoint * storage) : result =
	match entrypoint with
	| Add_direct param -> add_direct param storage
	| Add_lambda param -> add_lambda param storage
	| Set_replacement param -> set_replacement param storage
	| Clear_replacement param -> clear_replacement param storage
	| Add_indirect param -> add_indirect param storage
	| Add_follow_list param -> add_follow_list param storage