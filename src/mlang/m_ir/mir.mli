(* Copyright (C) 2019-2021 Inria, contributors: Denis Merigoux
   <denis.merigoux@inria.fr> Raphaël Monat <raphael.monat@lip6.fr>

   This program is free software: you can redistribute it and/or modify it under
   the terms of the GNU General Public License as published by the Free Software
   Foundation, either version 3 of the License, or (at your option) any later
   version.

   This program is distributed in the hope that it will be useful, but WITHOUT
   ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
   FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
   details.

   You should have received a copy of the GNU General Public License along with
   this program. If not, see <https://www.gnu.org/licenses/>. *)

type execution_number = {
  rule_number : int;
      (** Written in the name of the rule or verification condition *)
  seq_number : int;  (** Index in the sequence of the definitions in the rule *)
  pos : Pos.t;
}

type cat_computed = Base | GivenBack

module CatCompSet : SetExt.T with type elt = cat_computed

type cat_variable = CatInput of StrSet.t | CatComputed of CatCompSet.t

val pp_cat_variable : Format.formatter -> cat_variable -> unit

val compare_cat_variable : cat_variable -> cat_variable -> int

module CatVarSet : SetExt.T with type elt = cat_variable

module CatVarMap : MapExt.T with type key = cat_variable

type variable_id = int
(** Each variable has an unique ID *)

type variable = {
  name : string Pos.marked;  (** The position is the variable declaration *)
  execution_number : execution_number;
      (** The number associated with the rule of verification condition in which
          the variable is defined *)
  alias : string option;  (** Input variable have an alias *)
  id : variable_id;
  descr : string Pos.marked;
      (** Description taken from the variable declaration *)
  attributes : Mast.variable_attribute list;
  origin : variable option;
      (** If the variable is an SSA duplication, refers to the original
          (declared) variable *)
  cats : CatVarSet.t;
  is_table : int option;
}

type local_variable = { id : int }

(** Type of MIR values *)
type typ = Real

type literal = Float of float | Undefined

(** MIR only supports a restricted set of functions *)
type func =
  | SumFunc  (** Sums the arguments *)
  | AbsFunc  (** Absolute value *)
  | MinFunc  (** Minimum of a list of values *)
  | MaxFunc  (** Maximum of a list of values *)
  | GtzFunc  (** Greater than zero (strict) ? *)
  | GtezFunc  (** Greater or equal than zero ? *)
  | NullFunc  (** Equal to zero ? *)
  | ArrFunc  (** Round to nearest integer *)
  | InfFunc  (** Truncate to integer *)
  | PresentFunc  (** Different than zero ? *)
  | Multimax  (** ??? *)
  | Supzero  (** ??? *)

(** MIR expressions are simpler than M; there are no loops or syntaxtic sugars.
    Because M lets you define conditional without an else branch although it is
    an expression-based language, we include an [Error] constructor to which the
    missing else branch is translated to.

    Because translating to MIR requires a lot of unrolling and expansion, we
    introduce a [LocalLet] construct to avoid code duplication. *)

type 'variable expression_ =
  | Unop of (Mast.unop[@opaque]) * 'variable expression_ Pos.marked
  | Comparison of
      (Mast.comp_op[@opaque]) Pos.marked
      * 'variable expression_ Pos.marked
      * 'variable expression_ Pos.marked
  | Binop of
      (Mast.binop[@opaque]) Pos.marked
      * 'variable expression_ Pos.marked
      * 'variable expression_ Pos.marked
  | Index of 'variable Pos.marked * 'variable expression_ Pos.marked
  | Conditional of
      'variable expression_ Pos.marked
      * 'variable expression_ Pos.marked
      * 'variable expression_ Pos.marked
  | FunctionCall of (func[@opaque]) * 'variable expression_ Pos.marked list
  | Literal of (literal[@opaque])
  | Var of 'variable
  | LocalVar of local_variable
  | Error
  | LocalLet of
      local_variable
      * 'variable expression_ Pos.marked
      * 'variable expression_ Pos.marked

type expression = variable expression_

module VariableMap : MapExt.T with type key = variable
(** MIR programs are just mapping from variables to their definitions, and make
    a massive use of [VariableMap]. *)

module VariableDict : Dict.S with type key = variable_id and type elt = variable

module VariableSet : SetExt.T with type elt = variable

module LocalVariableMap : sig
  include MapExt.T with type key = local_variable
end

module IndexMap : IntMap.T

type 'variable index_def =
  | IndexTable of
      ('variable expression_ Pos.marked IndexMap.t[@name "index_map"])
  | IndexGeneric of 'variable * 'variable expression_ Pos.marked

type 'variable variable_def_ =
  | SimpleVar of 'variable expression_ Pos.marked
  | TableVar of int * 'variable index_def
  | InputVar

type variable_def = variable variable_def_

type io = Input | Output | Regular

type 'variable variable_data_ = {
  var_definition : 'variable variable_def_;
  var_typ : typ option;
      (** The typing info here comes from the variable declaration in the source
          program *)
  var_io : io;
}

type variable_data = variable variable_data_

type rov_id = RuleID of int | VerifID of int

module RuleMap : MapExt.T with type key = rov_id

type 'a domain = {
  dom_id : Mast.DomainId.t;
  dom_names : Mast.DomainIdSet.t;
  dom_by_default : bool;
  dom_min : Mast.DomainIdSet.t;
  dom_max : Mast.DomainIdSet.t;
  dom_data : 'a;
}

type rule_domain_data = { rdom_computable : bool }

type rule_domain = rule_domain_data domain

type rule_data = {
  rule_domain : rule_domain;
  rule_chain : (string * rule_domain) option;
  rule_vars : (variable_id * variable_data) list;
  rule_number : rov_id Pos.marked;
}

type error_descr = {
  kind : string Pos.marked;
  major_code : string Pos.marked;
  minor_code : string Pos.marked;
  description : string Pos.marked;
  isisf : string Pos.marked;
}
(** Errors are first-class objects *)

type error = {
  name : string Pos.marked;  (** The position is the variable declaration *)
  id : int;  (** Each variable has an unique ID *)
  descr : error_descr;  (** Description taken from the variable declaration *)
  typ : Mast.error_typ;
}

type verif_domain_data = { vdom_auth : CatVarSet.t }

type verif_domain = verif_domain_data domain

type 'variable condition_data_ = {
  cond_seq_id : int;
  cond_number : rov_id Pos.marked;
  cond_domain : verif_domain;
  cond_expr : 'variable expression_ Pos.marked;
  cond_error : error * 'variable option;
  cond_cats : int CatVarMap.t;
}

type condition_data = variable condition_data_

type idmap = variable list Pos.VarNameToID.t
(** We translate string variables into first-class unique {!type: Mir.variable},
    so we need to keep a mapping between the two. A name is mapped to a list of
    variables because variables can be redefined in different rules *)

type exec_pass = { exec_pass_set_variables : literal Pos.marked VariableMap.t }

type program = {
  program_var_categories : Pos.t StrMap.t Pos.marked CatVarMap.t;
  program_rule_domains : rule_domain Mast.DomainIdMap.t;
  program_verif_domains : verif_domain Mast.DomainIdMap.t;
  program_chainings : rule_domain Mast.ChainingMap.t;
  program_vars : VariableDict.t;
      (** A static register of all variables that can be used during a
          calculation *)
  program_rules : rule_data RuleMap.t;
      (** Definitions of variables, some may be removed during optimization
          passes *)
  program_conds : condition_data RuleMap.t;
      (** Conditions are affected to dummy variables containing informations
          about actual variables in the conditions *)
  program_idmap : idmap;
  program_exec_passes : exec_pass list;
}

module Variable : sig
  type id = variable_id

  type t = variable = {
    name : string Pos.marked;  (** The position is the variable declaration *)
    execution_number : execution_number;
        (** The number associated with the rule of verification condition in
            which the variable is defined *)
    alias : string option;  (** Input variable have an alias *)
    id : variable_id;
    descr : string Pos.marked;
        (** Description taken from the variable declaration *)
    attributes : Mast.variable_attribute list;
    origin : variable option;
        (** If the variable is an SSA duplication, refers to the original
            (declared) variable *)
    cats : CatVarSet.t;
    is_table : int option;
  }

  val fresh_id : unit -> id

  val new_var :
    string Pos.marked ->
    string option ->
    string Pos.marked ->
    execution_number ->
    attributes:Mast.variable_attribute list ->
    origin:variable option ->
    cats:CatVarSet.t ->
    is_table:int option ->
    variable

  val compare : t -> t -> int
end

(** Local variables don't appear in the M source program but can be introduced
    by let bindings when translating to MIR. They should be De Bruijn indices
    but instead are unique globals identifiers out of laziness. *)
module LocalVariable : sig
  type t = local_variable = { id : int }

  val new_var : unit -> t

  val compare : t -> t -> int
end

module Error : sig
  type descr = error_descr = {
    kind : string Pos.marked;
    major_code : string Pos.marked;
    minor_code : string Pos.marked;
    description : string Pos.marked;
    isisf : string Pos.marked;
  }

  type t = error = {
    name : string Pos.marked;  (** The position is the variable declaration *)
    id : int;  (** Each variable has an unique ID *)
    descr : error_descr;  (** Description taken from the variable declaration *)
    typ : Mast.error_typ;
  }

  val new_error : string Pos.marked -> Mast.error_ -> Mast.error_typ -> error

  val err_descr_string : t -> string Pos.marked

  val compare : t -> t -> int
end

val false_literal : literal

val true_literal : literal

val num_of_rule_or_verif_id : rov_id -> int

val same_execution_number : execution_number -> execution_number -> bool

val find_var_name_by_alias : program -> string Pos.marked -> string

val map_expr_var : ('v -> 'v2) -> 'v expression_ -> 'v2 expression_

val fold_expr_var : ('a -> 'v -> 'a) -> 'a -> 'v expression_ -> 'a

val map_var_def_var : ('v -> 'v2) -> 'v variable_def_ -> 'v2 variable_def_

val map_cond_data_var : ('v -> 'v2) -> 'v condition_data_ -> 'v2 condition_data_

val cond_cats_to_set : int CatVarMap.t -> CatVarSet.t

val fold_vars : (variable -> variable_data -> 'a -> 'a) -> program -> 'a -> 'a

val map_vars :
  (variable -> variable_data -> variable_data) -> program -> program

val compare_execution_number : execution_number -> execution_number -> int

val find_var_definition : program -> variable -> rule_data * variable_data

val is_candidate_valid : execution_number -> execution_number -> bool -> bool

val sort_by_lowest_exec_number : Variable.t -> Variable.t -> int

val get_max_var_sorted_by_execution_number :
  (Variable.t -> Variable.t -> int) ->
  string ->
  Variable.t list Pos.VarNameToID.t ->
  Variable.t

val fresh_rule_num : unit -> int

val initial_undef_rule_id : rov_id

val find_var_by_name : program -> string Pos.marked -> variable
(** Get a variable for a given name or alias, because of SSA multiple variables
    share a name or alias. If an alias is provided, the variable returned is
    that with the lowest execution number. When a name is provided, then the
    variable with the highest execution number is returned. *)

val is_dummy_variable : Variable.t -> bool

val find_vars_by_io : program -> io -> VariableDict.t
(** Returns a VariableDict.t containing all the variables that have a given io
    type, only one variable per name is entered in the VariableDict.t, this
    function chooses the one with the highest execution number*)

val mast_to_catvars :
  'a CatVarMap.t -> string Pos.marked list Pos.marked -> CatVarSet.t

val mast_to_catvar :
  'a CatVarMap.t -> string Pos.marked list Pos.marked -> cat_variable
