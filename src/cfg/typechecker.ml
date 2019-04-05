(*
Copyright Inria, contributor: Denis Merigoux <denis.merigoux@inria.fr> (2019)

This software is a computer program whose purpose is to compile and analyze
programs written in the M langage, created by thge DGFiP.

This software is governed by the CeCILL-B license under French law and
abiding by the rules of distribution of free software.  You can  use,
modify and/ or redistribute the software under the terms of the CeCILL-B
license as circulated by CEA, CNRS and INRIA at the following URL
http://www.cecill.info.

As a counterpart to the access to the source code and  rights to copy,
modify and redistribute granted by the license, users are provided only
with a limited warranty  and the software's author,  the holder of the
economic rights,  and the successive licensors  have only  limited
liability.

In this respect, the user's attention is drawn to the risks associated
with loading,  using,  modifying and/or developing or reproducing the
software by the user in light of its specific status of free software,
that may mean  that it is complicated to manipulate,  and  that  also
therefore means  that it is reserved for developers  and  experienced
professionals having in-depth computer knowledge. Users are therefore
encouraged to load and test the software's suitability as regards their
requirements in conditions enabling the security of their systems and/or
data to be ensured and,  more generally, to use and operate it in the
same conditions as regards security.

The fact that you are presently reading this means that you have had
knowledge of the CeCILL-B license and that you accept its terms.
*)

open Cfg

module Typ =
struct

  module UF = Union_find.Make(struct
      type t = typ option
      let equal t1 t2 = t1 = t2
    end)

  module UB = Union_find.Make(struct
      type t = bool option
      let equal t1 t2 = t1 = t2
    end)

  type t = {
    uf_typ: UF.t;
    uf_is_bool: UB.t;
  }

  let integer : t = { uf_typ = UF.create (Some Integer); uf_is_bool = UB.create None }
  let real : t = { uf_typ = UF.create (Some Real); uf_is_bool = UB.create None }
  let boolean : t = { uf_typ = UF.create (Some Boolean); uf_is_bool = UB.create None }
  let only_non_boolean : t = { uf_typ = UF.create None; uf_is_bool = UB.create (Some false) }
  let only_boolean : t = { uf_typ = UF.create None; uf_is_bool = UB.create (Some true) }

  let create_concrete (t: typ) : t =
    match t with
    | Integer -> integer
    | Real -> real
    | Boolean -> boolean

  let create_variable () : t = { uf_typ = UF.create None; uf_is_bool = UB.create None }

  let is_boolean (t: t) : bool =
    UF.find t.uf_typ = UF.find boolean.uf_typ

  let is_integer (t: t) : bool =
    UF.find t.uf_typ = UF.find integer.uf_typ

  let is_real (t:t) : bool =
    UF.find t.uf_typ = UF.find real.uf_typ

  exception UnificationError of string * string

  let format_unification_error_type (t: t) : string = match UF.get_elt t.uf_typ with
    | Some Integer ->  Format_cfg.format_typ Integer
    | Some Real -> Format_cfg.format_typ Real
    | Some Boolean -> Format_cfg.format_typ Boolean
    | None -> "uknwon"

  let unify (t1: t) (t2: t) : unit =
    UF.union t1.uf_typ t2.uf_typ;
    UB.union t1.uf_is_bool t2.uf_is_bool;
    if UF.find integer.uf_typ = UF.find real.uf_typ ||
       UF.find integer.uf_typ = UF.find boolean.uf_typ ||
       UF.find real.uf_typ = UF.find boolean.uf_typ ||
       UB.find only_non_boolean.uf_is_bool = UB.find only_boolean.uf_is_bool then
      raise (UnificationError (format_unification_error_type t1, format_unification_error_type t2))
    else
      ()

  let to_concrete (t: t) : typ =
    if UF.find t.uf_typ = UF.find real.uf_typ then
      Real
    else if UF.find t.uf_typ = UF.find boolean.uf_typ then
      Boolean
    else if UF.find real.uf_typ = UF.find integer.uf_typ then
      Integer
    else if UB.find t.uf_is_bool = UB.find only_non_boolean.uf_is_bool then
      Integer
    else
      Boolean

  let format_typ (t:t) =
    if UF.find t.uf_typ = UF.find real.uf_typ then
      Format_cfg.format_typ Real
    else if UF.find t.uf_typ = UF.find boolean.uf_typ then
      Format_cfg.format_typ Boolean
    else if UF.find t.uf_typ = UF.find integer.uf_typ then
      Format_cfg.format_typ Integer
    else if UB.find t.uf_is_bool = UB.find only_non_boolean.uf_is_bool then
      "integer or real"
    else
      "unknown ()"

end

type ctx = {
  ctx_program : program;
  ctx_var_typ: Typ.t VariableMap.t;
  ctx_local_var_typ: Typ.t LocalVariableMap.t;
}

let rec typecheck_top_down
    (ctx: ctx)
    (e: expression Ast.marked)
    (t: typ)
  : ctx =
  match (Ast.unmark e, t) with
  | (Comparison (op, e1, e2), Boolean) ->
    let (ctx, t1) = typecheck_bottom_up ctx e1 in
    let (ctx, t2) = typecheck_bottom_up ctx e2 in
    begin try Typ.unify t1 t2; ctx with
      | Typ.UnificationError _ ->
        raise (Errors.TypeError (
            Errors.Typing
              (Printf.sprintf "expression %s (%s) of type %s has not the same type than expression %s of type %s"
                 (Format_cfg.format_expression (Ast.unmark e1))
                 (Format_ast.format_position (Ast.get_position e1))
                 (Typ.format_typ t1)
                 (Format_ast.format_position (Ast.get_position e2))
                 (Typ.format_typ t2)
              )))
    end
  | (Binop (((Ast.And | Ast.Or), _), e1, e2), Boolean)
  | (Binop (((Ast.Add | Ast.Sub | Ast.Mul | Ast.Div), _), e1, e2), (Integer | Real)) ->
    let ctx = typecheck_top_down ctx e1 t in
    let ctx = typecheck_top_down ctx e2 t in
    ctx
  | (Unop (Ast.Not, e), Boolean)
  | (Unop (Ast.Minus, e), (Integer | Real))  ->
    let ctx = typecheck_top_down ctx e t in
    ctx
  | (Conditional (e1, e2, e3), t) ->
    let (ctx, t1) = typecheck_bottom_up ctx e1 in
    begin try
        Typ.unify t1 Typ.boolean;
        let (ctx, t2) = typecheck_bottom_up ctx e2 in
        let (ctx, t3) = typecheck_bottom_up ctx e3 in
        begin try
            Typ.unify t2 t3; Typ.unify t2 (Typ.create_concrete t); ctx
          with
          | Typ.UnificationError _ ->
            raise (Errors.TypeError (
                Errors.Typing
                  (Printf.sprintf "expression %s (%s) of type %s has not the same type than expression %s of type %s, and both should be of type %s"
                     (Format_cfg.format_expression (Ast.unmark e1))
                     (Format_ast.format_position (Ast.get_position e1))
                     (Typ.format_typ t1)
                     (Format_ast.format_position (Ast.get_position e2))
                     (Typ.format_typ t2)
                     (Format_cfg.format_typ t)
                  )))
        end
      with
      | Typ.UnificationError _ ->
        raise (Errors.TypeError (
            Errors.Typing
              (Printf.sprintf "expression %s (%s) of type %s should be of type boolean"
                 (Format_cfg.format_expression (Ast.unmark e1))
                 (Format_ast.format_position (Ast.get_position e1))
                 (Typ.format_typ t1)
              )))
    end
  | (FunctionCall (func, args), t) ->
    let typechecker = typecheck_func_args func (Ast.get_position e) in
    let (ctx, t') = typechecker ctx args in
    begin try Typ.unify t' (Typ.create_concrete t); ctx with
      | Typ.UnificationError _ ->
        raise (Errors.TypeError (
            Errors.Typing
              (Printf.sprintf "function call to %s (%s) return type is %s but should be %s"
                 (Format_cfg.format_func func)
                 (Format_ast.format_position (Ast.get_position e))
                 (Typ.format_typ t')
                 (Format_cfg.format_typ t)
              )))
    end
  | (Literal (Int _), Integer)
  | (Literal (Float _), Real)
  | (Literal (Bool _), Boolean) -> ctx
  | (Var var, t) ->
    begin try match (VariableMap.find var ctx.ctx_program).var_typ with
      | Some t' -> if t = t' then ctx else
          raise (Errors.TypeError (
              Errors.Typing
                (Printf.sprintf "variable %s used %s should be of type %s but has been declared of type %s"
                   (Ast.unmark var.Variable.name)
                   (Format_ast.format_position (Ast.get_position e))
                   (Format_cfg.format_typ t)
                   (Format_cfg.format_typ t')
                )))
      | None ->
        let (ctx, t') = typecheck_bottom_up ctx e in
        begin try Typ.unify t' (Typ.create_concrete t); ctx with
          | Typ.UnificationError (t_msg, _) ->
            raise (Errors.TypeError (
                Errors.Typing
                  (Printf.sprintf "variable %s %s is of type %s but should be %s"
                     (Ast.unmark var.Variable.name)
                     (Format_ast.format_position (Ast.get_position var.Variable.name))
                     t_msg
                     (Format_cfg.format_typ t)
                  )))
        end
      with
      | Not_found -> assert false (* should not happen *)
    end
  | (LocalLet (local_var, e1, e2), t) ->
    let (ctx, t1) = typecheck_bottom_up ctx e1 in
    let ctx = { ctx with ctx_local_var_typ = LocalVariableMap.add local_var t1 ctx.ctx_local_var_typ } in
    let (ctx, t2) = typecheck_bottom_up ctx e2 in
    begin try Typ.unify t2 (Typ.create_concrete t); ctx with
      | Typ.UnificationError (t2_msg, _) ->
        raise (Errors.TypeError (
            Errors.Typing
              (Printf.sprintf "expression %s has type %s but should be %s"
                 (Format_ast.format_position (Ast.get_position e))
                 t2_msg
                 (Format_cfg.format_typ t)
              )))
    end
  | (Error, t) ->
    ctx
  | (LocalVar local_var, t) ->
    let t' = try LocalVariableMap.find local_var ctx.ctx_local_var_typ with
      | Not_found -> assert false (* should not happen *)
    in
    begin try Typ.unify t' (Typ.create_concrete t); ctx with
      | Typ.UnificationError (t_msg, _) ->
        raise (Errors.TypeError (
            Errors.Typing
              (Printf.sprintf "expression %s has type %s but should be %s"
                 (Format_ast.format_position (Ast.get_position e))
                 t_msg
                 (Format_cfg.format_typ t)
              )))
    end
  | (GenericTableIndex, Integer) -> ctx
  | _ -> raise (Errors.TypeError (
      Errors.Typing
        (Printf.sprintf "expression %s (%s) should be of type %s, but is of type %s"
           (Format_cfg.format_expression (Ast.unmark e))
           (Format_ast.format_position (Ast.get_position e))
           (Format_cfg.format_typ t)
           (
             let (_, t') =  typecheck_bottom_up ctx e in
             Typ.format_typ t'
           )
        )))

and typecheck_func_args (f: func) (pos: Ast.position) :
  (ctx -> Cfg.expression Ast.marked list -> ctx * Typ.t) =
  match f with
  | SumFunc | MinFunc | MaxFunc -> fun ctx args ->
    if List.length args = 0 then
      raise (Errors.TypeError
               (Errors.Typing
                  (Printf.sprintf "sum function must be called %s with at least one argument"
                     (Format_ast.format_position pos)
                  )))
    else
      let (ctx, t1) = typecheck_bottom_up ctx (List.hd args) in
      let ctx = List.fold_left (fun ctx arg ->
          let (ctx, t_arg) = typecheck_bottom_up ctx arg in
          begin try Typ.unify t_arg t1; Typ.unify t_arg Typ.only_non_boolean; ctx with
            | Typ.UnificationError (t_arg_msg,t2_msg) ->
              raise (Errors.TypeError
                       (Errors.Typing
                          (Printf.sprintf "function argument %s (%s) has type %s but should have type %s"
                             (Format_cfg.format_expression (Ast.unmark arg))
                             (Format_ast.format_position (Ast.get_position arg))
                             t_arg_msg
                             t2_msg
                          )))
          end
        ) ctx args
      in
      (ctx, t1)
  | AbsFunc ->
    fun ctx args ->
      begin match args with
        | [arg] ->
          let (ctx, t_arg) = typecheck_bottom_up ctx arg in
          begin try Typ.unify t_arg Typ.only_non_boolean; (ctx, t_arg) with
            | Typ.UnificationError (t_arg_msg,t2_msg) ->
              raise (Errors.TypeError
                       (Errors.Typing
                          (Printf.sprintf "function argument %s (%s) has type %s but should have type %s"
                             (Format_cfg.format_expression (Ast.unmark arg))
                             (Format_ast.format_position (Ast.get_position arg))
                             t_arg_msg
                             t2_msg
                          )))
          end
        | _ -> raise (Errors.TypeError
                        (Errors.Typing
                           (Printf.sprintf "function abs %s should have only one arguemnt"
                              (Format_ast.format_position pos)
                           )))
      end
  | PresentFunc | NullFunc | GtzFunc | GtezFunc ->
    fun ctx args ->
      begin match args with
        | [arg] ->
          let (ctx, t_arg) = typecheck_bottom_up ctx arg in
          begin try Typ.unify t_arg Typ.only_non_boolean; (ctx, Typ.boolean) with
            | Typ.UnificationError (t_arg_msg,t2_msg) ->
              raise (Errors.TypeError
                       (Errors.Typing
                          (Printf.sprintf "function argument %s (%s) has type %s but should have type %s"
                             (Format_cfg.format_expression (Ast.unmark arg))
                             (Format_ast.format_position (Ast.get_position arg))
                             t_arg_msg
                             t2_msg
                          )))
          end
        | _ -> raise (Errors.TypeError
                        (Errors.Typing
                           (Printf.sprintf "function abs %s should have only one arguemnt"
                              (Format_ast.format_position pos)
                           )))
      end
  | _ -> assert false (* unimplemented, do other functions *)

and typecheck_bottom_up (ctx: ctx) (e: expression Ast.marked) : (ctx * Typ.t) =
  match Ast.unmark e with
  | Var var ->
    begin try (ctx, VariableMap.find var ctx.ctx_var_typ) with
      | Not_found ->
        let t = Typ.create_variable () in
        let ctx = { ctx with ctx_var_typ = VariableMap.add var t ctx.ctx_var_typ } in
        (ctx, t)
    end
  | Literal (Int _) -> (ctx, Typ.integer)
  | Literal (Float _) -> (ctx, Typ.real)
  | Literal (Bool _) -> (ctx, Typ.boolean)
  | Binop ((Ast.And, _ | Ast.Or, _), e1, e2) ->
    let ctx = typecheck_top_down ctx e1 Boolean in
    let ctx = typecheck_top_down ctx e2 Boolean in
    (ctx, Typ.boolean)
  | Binop ((Ast.Add, _ | Ast.Sub, _ | Ast.Mul, _ | Ast.Div, _) as op, e1, e2) ->
    let (ctx, t1) = typecheck_bottom_up ctx e1 in
    let (ctx, t2) = typecheck_bottom_up ctx e2 in
    begin try Typ.unify t1 t2; Typ.unify t1 Typ.only_non_boolean; (ctx, t1) with
      | Typ.UnificationError (t1_msg, t2_msg) ->
        raise (Errors.TypeError
                 (Errors.Typing
                    (Printf.sprintf "arguments of operator (%s) %s have to be of the same type but instead are of type %s and %s"
                       (Format_ast.format_binop (Ast.unmark op))
                       (Format_ast.format_position (Ast.get_position op))
                       t1_msg
                       t2_msg
                    )))
    end
  | Comparison (op, e1, e2) ->
    let (ctx, t1) = typecheck_bottom_up ctx e1 in
    let (ctx, t2) = typecheck_bottom_up ctx e2 in
    begin try Typ.unify t1 t2; (ctx, Typ.boolean) with
      | Typ.UnificationError _ ->
        raise (Errors.TypeError (
            Errors.Typing
              (Printf.sprintf "expression %s (%s) of type %s has not the same type than expression %s of type %s"
                 (Format_cfg.format_expression (Ast.unmark e1))
                 (Format_ast.format_position (Ast.get_position e1))
                 (Typ.format_typ t1)
                 (Format_ast.format_position (Ast.get_position e2))
                 (Typ.format_typ t2)
              )))
    end
  | Unop (Ast.Not, e) ->
    let ctx = typecheck_top_down ctx e Boolean in
    (ctx, Typ.boolean)
  | Unop (Ast.Minus, e') ->
    let (ctx, t) = typecheck_bottom_up ctx e' in
    begin try Typ.unify t Typ.only_non_boolean; (ctx, t) with
      | Typ.UnificationError (t1_msg, t2_msg) ->
        raise (Errors.TypeError
                 (Errors.Typing
                    (Printf.sprintf "arguments of operator (%s) %s has type %s but should be of type %s"
                       (Format_ast.format_unop (Ast.Minus))
                       (Format_ast.format_position (Ast.get_position e))
                       t1_msg
                       t2_msg
                    )))
    end
  | GenericTableIndex -> (ctx, Typ.integer)
  | Index ((var, var_pos), e') ->
    let ctx = typecheck_top_down ctx e' Integer in
    let var_data = VariableMap.find var ctx.ctx_program in
    begin match var_data.Cfg.var_definition with
      | SimpleVar _ | InputVar ->
        raise (Errors.TypeError
                 (Errors.Typing
                    (Printf.sprintf "variable %s is accessed %s as a table but it is not defined as one %s"
                       (Ast.unmark var.Variable.name)
                       (Format_ast.format_position var_pos)
                       (Format_ast.format_position (Ast.get_position var.Variable.name))
                    )))
      | TableVar _ ->
        begin try (ctx, VariableMap.find var ctx.ctx_var_typ) with
          | Not_found ->
            let t = Typ.create_variable () in
            let ctx = { ctx with ctx_var_typ = VariableMap.add var t ctx.ctx_var_typ } in
            (ctx, t)
        end
    end
  | Conditional (e1, e2, e3) ->
    let (ctx, t1) = typecheck_bottom_up ctx e1 in
    begin try
        Typ.unify t1 Typ.boolean;
        let (ctx, t2) = typecheck_bottom_up ctx e2 in
        let (ctx, t3) = typecheck_bottom_up ctx e3 in
        begin try
            Typ.unify t2 t3; (ctx, t2)
          with
          | Typ.UnificationError _ ->
            raise (Errors.TypeError (
                Errors.Typing
                  (Printf.sprintf "expression %s (%s) of type %s has not the same type than expression %s of type %s"
                     (Format_cfg.format_expression (Ast.unmark e1))
                     (Format_ast.format_position (Ast.get_position e1))
                     (Typ.format_typ t1)
                     (Format_ast.format_position (Ast.get_position e2))
                     (Typ.format_typ t2)
                  )))
        end
      with
      | Typ.UnificationError _ ->
        raise (Errors.TypeError (
            Errors.Typing
              (Printf.sprintf "expression %s (%s) of type %s should be of type boolean"
                 (Format_cfg.format_expression (Ast.unmark e1))
                 (Format_ast.format_position (Ast.get_position e1))
                 (Typ.format_typ t1)
              )))
    end
  | FunctionCall(func, args) ->
    let typechecker = typecheck_func_args func (Ast.get_position e) in
    let (ctx, t') = typechecker ctx args in
    (ctx, t')
  | Error -> (ctx, Typ.create_variable ())
  | LocalVar local_var ->
    begin try (ctx, LocalVariableMap.find local_var ctx.ctx_local_var_typ) with
      | Not_found -> assert false (* should not happen *)
    end
  | LocalLet (local_var, e1, e2) ->
    let (ctx, t1) = typecheck_bottom_up ctx e1 in
    let ctx = { ctx with ctx_local_var_typ = LocalVariableMap.add local_var t1 ctx.ctx_local_var_typ } in
    let (ctx, t2) = typecheck_bottom_up ctx e2 in
    (ctx, t2)

let determine_def_complete_cover (size: int) (defs: int list) : bool =
  let defs_array = Array.make size false in
  List.iter (fun def ->
      defs_array.(def) <- true
    ) defs;
  Array.for_all (fun def -> def) defs_array

let typecheck (p: program) : typ VariableMap.t =
  let (types, _) = Cfg.VariableMap.fold (fun var def (acc, ctx) ->
      match def.var_typ with
      | Some t -> begin match def.var_definition with
          | SimpleVar e ->
            let new_ctx = typecheck_top_down ctx e t in
            (VariableMap.add var (Typ.create_concrete t) acc, new_ctx)
          | TableVar (size, defs) -> begin match defs with
              | IndexGeneric e ->
                let new_ctx = typecheck_top_down ctx e t in
                (VariableMap.add var (Typ.create_concrete t) acc, new_ctx)
              | IndexTable es ->
                let new_ctx = IndexMap.fold (fun _ e ctx ->
                    let new_ctx = typecheck_top_down ctx e t in
                    new_ctx
                  ) es ctx in
                if determine_def_complete_cover size
                    (List.map (fun (x,_) -> x) (IndexMap.bindings es))
                then
                  (VariableMap.add var (Typ.create_concrete t) acc, new_ctx)
                else
                  raise (Errors.TypeError (
                      Errors.Variable
                        (Printf.sprintf "the definitions of table %s declared %s do not cover all of its indexes"
                           (Ast.unmark var.Variable.name)
                           (Format_ast.format_position (Ast.get_position var.Variable.name))
                        )))
            end
          | InputVar ->
            (VariableMap.add var (Typ.create_concrete t) acc, ctx)
        end
      | None -> begin match def.var_definition with
          | SimpleVar e ->
            let (new_ctx, t) = typecheck_bottom_up ctx e in
            (VariableMap.add var t acc, new_ctx)
          | TableVar (size, defs) -> begin match defs with
              | IndexGeneric e ->
                let (new_ctx, t) = typecheck_bottom_up ctx e in
                (VariableMap.add var t acc, new_ctx)
              | IndexTable es ->
                let (new_ctx, t) = IndexMap.fold (fun _ e (ctx, old_t) ->
                    let (new_ctx, t) = typecheck_bottom_up ctx e in
                    begin try Typ.unify t old_t; (new_ctx, t) with
                      | Typ.UnificationError (t1_msg, t2_msg) ->
                        raise (Errors.TypeError (
                            Errors.Typing
                              (Printf.sprintf "different definitions of specific index of table variable %s declared %s have different indexes: %s and %s"
                                 (Ast.unmark var.Variable.name)
                                 (Format_ast.format_position (Ast.get_position var.Variable.name))
                                 t1_msg
                                 t2_msg
                              )))
                    end
                  ) es (ctx, Typ.create_variable ()) in
                if determine_def_complete_cover size
                    (List.map (fun (x,_) -> x) (IndexMap.bindings es))
                then
                  (VariableMap.add var t acc, new_ctx)
                else
                  raise (Errors.TypeError (
                      Errors.Variable
                        (Printf.sprintf "the definitions of table %s declared %s do not cover all its indexes"
                           (Ast.unmark var.Variable.name)
                           (Format_ast.format_position (Ast.get_position var.Variable.name))
                        )))
            end
          | InputVar ->
            if VariableMap.mem var acc then
              (acc, ctx)
            else
              (VariableMap.add var (Typ.create_variable ()) acc, ctx)
        end
    ) p (Cfg.VariableMap.empty,
         { ctx_program = p;
           ctx_var_typ = VariableMap.merge (fun _ _ def ->
               match def with
               | None -> assert false (* should not happen *)
               | Some def -> begin match def.var_typ with
                   | Some t -> Some (Typ.create_concrete t)
                   | None -> None
                 end
             ) VariableMap.empty p;
           ctx_local_var_typ = LocalVariableMap.empty;
         })
  in
  VariableMap.map (fun t -> Typ.to_concrete t) types