(*
Copyright Inria, contributor: Denis Merigoux <denis.merigoux@inria.fr> (2019)

This software is a computer program whose purpose is to compile and analyze
programs written in the M langage, created by the DGFiP.

This software is governed by the CeCILL-C license under French law and
abiding by the rules of distribution of free software.  You can  use,
modify and/ or redistribute the software under the terms of the CeCILL-C
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
knowledge of the CeCILL-C license and that you accept its terms.
*)

(**
   Partial evaluation mostly relies on the {!module: Verifisc.Interpreter} module ; however it also
   include peehole optimizations that must be checked for compatibility with M's semantics.
*)

open Mvg

type partial_expr =
  | PartialLiteral of literal
  | PartialVar of Variable.t

let partial_to_expr (e: partial_expr) : expression = match e with
  | PartialLiteral l -> Literal l
  | PartialVar v -> Var v

let expr_to_partial (e: expression) : partial_expr = match e with
  | Literal l  -> PartialLiteral l
  | Var v -> PartialVar v
  | _ -> assert false (* should not happen *)

type var_literal =
  | SimpleVar of partial_expr
  | TableVar of int * partial_expr array

type ctx = {
  ctx_local_vars: partial_expr LocalVariableMap.t;
  ctx_inside_var: Variable.t;
  ctx_inside_table_index: int option;
}

let empty_ctx (var: Variable.t) (idx: int option) = {
  ctx_local_vars = LocalVariableMap.empty;
  ctx_inside_var = var;
  ctx_inside_table_index = idx;
}

let rec partial_evaluation (ctx: ctx) (p: program) (e: expression Ast.marked) : expression Ast.marked =
  match Ast.unmark e with
  | Comparison (op, e1, e2) ->
    let new_e1 = partial_evaluation ctx p e1 in
    let new_e2 = partial_evaluation ctx p e2 in
    Ast.same_pos_as begin match (Ast.unmark new_e1, Ast.unmark new_e2) with
      | (Literal Undefined, _) | (_, Literal Undefined) ->
        Literal Undefined
      | (Literal _, Literal _) ->
        Mvg.Literal (Interpreter.evaluate_expr Interpreter.empty_ctx p
                       (Ast.same_pos_as (Comparison (op,new_e1, new_e2)) e)
                    )
      | _ -> Comparison (op, new_e1, new_e2)
    end e
  | Binop (op, e1, e2) ->
    let new_e1 = partial_evaluation ctx p e1 in
    let new_e2 = partial_evaluation ctx p e2 in
    Ast.same_pos_as begin match (Ast.unmark op, Ast.unmark new_e1, Ast.unmark new_e2) with
      | (Ast.And, Literal Undefined, _) | (Ast.And, _, Literal Undefined)
      | (Ast.Or, Literal Undefined, _) | (Ast.Or, _, Literal Undefined)
      | (Ast.Div, _, Literal Undefined)
        -> Literal Undefined
      | (Ast.Or, Literal (Bool true), _)
      | (Ast.Or, _, Literal (Bool true))
        -> Literal (Bool true)
      | (Ast.And, Literal (Bool false), _)
      | (Ast.And, _, Literal (Bool false))
        -> Literal (Bool false)
      | (Ast.And, Literal (Bool true), e')
      | (Ast.And, e', Literal (Bool true))
      | (Ast.Or, Literal (Bool false), e')
      | (Ast.Or, e', Literal (Bool false))
      | (Ast.Add, Literal ((Int 0) | Float 0. | Bool false | Undefined), e')
      | (Ast.Add, e', Literal ((Int 0) | Float 0. | Bool false | Undefined))
      | (Ast.Mul, Literal ((Int 1) | Float 1. | Bool true), e')
      | (Ast.Mul, e', Literal ((Int 1) | Float 1. | Bool true ))
      | (Ast.Div, e', Literal ((Int 1) | Float 1. | Bool true ))
      | (Ast.Sub, e', Literal ((Int 0) | Float 0. | Bool false | Undefined))
        -> e'
      | (Ast.Sub, Literal ((Int 0) | Float 0. | Bool false | Undefined), e') ->
        Unop (Minus, Ast.same_pos_as e' e)
      | (Ast.Mul, Literal ((Int 0) | Float 0. | Bool false | Undefined), _)
      | (Ast.Mul, _, Literal ((Int 0) | Float 0. | Bool false | Undefined))
      | (Ast.Div, Literal ((Int 0) | Float 0. | Bool false | Undefined), _)
        ->
        Mvg.Literal (Mvg.Bool false)
      | (_, Literal _, Literal _) ->
        (Mvg.Literal
           (Interpreter.evaluate_expr Interpreter.empty_ctx p
              (Ast.same_pos_as (Binop (op,new_e1, new_e2)) e1)
           ))
      | (Ast.Add, _, Literal (Float f)) when f < 0. ->
        Binop (Ast.same_pos_as Ast.Sub op, e1, Ast.same_pos_as (Literal (Float (-. f))) e2)
      | (Ast.Add, _, Literal (Int i)) when i < 0 ->
        Binop (Ast.same_pos_as Ast.Sub op, e1, Ast.same_pos_as (Literal (Int (- i))) e2)
      | (Ast.Add, _, Unop (Minus, e2')) ->
        Binop (Ast.same_pos_as Ast.Sub op, e1, e2')
      | _ -> Binop (op, new_e1, new_e2)
    end e
  | Unop (op, e1) ->
    let new_e1 = partial_evaluation ctx p e1 in
    Ast.same_pos_as begin match (Ast.unmark new_e1) with
      | Literal _ ->
        Mvg.Literal (Interpreter.evaluate_expr
                       Interpreter.empty_ctx
                       p
                       (Ast.same_pos_as (Unop(op, new_e1)) e1)
                    )
      | _ -> Unop (op, new_e1)
    end e
  | Conditional (e1, e2, e3) ->
    let new_e1 = partial_evaluation ctx p e1 in
    let new_e2 = partial_evaluation ctx p e2 in
    let new_e3 = partial_evaluation ctx p e3 in
    begin match Ast.unmark new_e1 with
      | Literal (Bool true) -> new_e2
      | Literal (Bool false) -> new_e3
      | Literal Undefined ->Ast.same_pos_as (Literal Undefined) e
      | _ -> Ast.same_pos_as (Conditional (new_e1, new_e2, new_e3)) e
    end
  | Index (var, e1) ->
    let new_e1 = partial_evaluation ctx p e1 in
    begin match Ast.unmark new_e1 with
      | Literal Undefined -> Ast.same_pos_as (Literal Undefined) e
      | Literal l ->
        let idx =  match l with
          | Bool b -> Interpreter.int_of_bool b
          | Int i -> i
          | Undefined  -> assert false (* should not happen *)
          | Float f ->
            if let (fraction, _) = modf f in fraction = 0. then
              int_of_float f
            else
              raise (Interpreter.RuntimeError (
                  Interpreter.FloatIndex (
                    Printf.sprintf "%s" (Format_ast.format_position (Ast.get_position e1))
                  ), Interpreter.empty_ctx
                ))
        in
        begin match (VariableMap.find (Ast.unmark var) p.program_vars).var_definition with
          | SimpleVar _ | InputVar -> assert false (* should not happen *)
          | TableVar (size, IndexGeneric e') ->
            if idx >= size || idx < 0 then
              Ast.same_pos_as (Literal Undefined) e
            else begin match Ast.unmark e' with
              | Literal _ | Var _ -> e'
              | _ ->  Ast.same_pos_as (Index(var, new_e1)) e
            end
          | TableVar (size, IndexTable es') ->
            if idx >= size || idx < 0 then
              Ast.same_pos_as (Literal Undefined) e
            else match Ast.unmark (IndexMap.find idx es') with
              | Literal _  | Var _ -> IndexMap.find idx es'
              | Index (inner_var, (Literal (Int inner_idx), _))
                when Ast.unmark inner_var = ctx.ctx_inside_var && ctx.ctx_inside_table_index = Some inner_idx
                ->
                (** TODO: fix this hack for circularly defined variables *)
                Ast.same_pos_as (Literal Undefined) (IndexMap.find idx es')
              | _ ->  Ast.same_pos_as (Index(var, new_e1)) e
        end
      | _ ->  Ast.same_pos_as (Index(var, new_e1)) e
    end
  | Literal _ -> e
  | Var var when var = ctx.ctx_inside_var ->
    Ast.same_pos_as (Literal Undefined) e
  | Var var when
      (VariableMap.find var p.program_vars).var_is_defined_circularly &&
      begin try (VariableMap.find ctx.ctx_inside_var p.program_vars).var_is_defined_circularly with
        | Not_found -> false end
    -> Ast.same_pos_as (Literal Undefined) e
  | Var var -> begin match begin try (VariableMap.find var p.program_vars).var_definition with
      | Not_found -> assert false (* should not happen *)
    end with
    | SimpleVar e'  -> begin match Ast.unmark e' with
        | Var _ | Literal _ ->  e'
        | _ -> e
      end
    | TableVar _ | InputVar -> e
    end
  | LocalVar lvar -> begin try Ast.same_pos_as (
      (partial_to_expr (LocalVariableMap.find lvar ctx.ctx_local_vars))
    ) e with
    | Not_found -> e
    end
  | GenericTableIndex -> e
  | Error -> e
  | LocalLet (lvar, e1, e2) ->
    let new_e1 = partial_evaluation ctx p e1 in
    begin match Ast.unmark new_e1 with
      | Literal _ | Var _ ->
        let new_ctx =
          { ctx with
            ctx_local_vars =
              LocalVariableMap.add lvar (expr_to_partial (Ast.unmark new_e1))
                ctx.ctx_local_vars
          }
        in
        let new_e2 = partial_evaluation new_ctx p e2 in
        new_e2
      | _ ->
        let new_e2 = partial_evaluation ctx p e2 in
        match Ast.unmark new_e2 with
        | Literal _ | Var _ -> new_e2
        | _ ->
          Ast.same_pos_as (LocalLet(lvar, new_e1, new_e2)) e
    end
  | FunctionCall (((ArrFunc | InfFunc | PresentFunc | NullFunc) as f), [arg]) ->
    let new_arg = partial_evaluation ctx p arg in
    begin match Ast.unmark new_arg with
      | Literal _ ->
        Ast.same_pos_as
          (Mvg.Literal
             (Interpreter.evaluate_expr
                Interpreter.empty_ctx
                p
                (Ast.same_pos_as (FunctionCall (f, [new_arg])) e)
             )
          ) e
      | _ -> Ast.same_pos_as (FunctionCall (f, [new_arg])) e
    end
  | FunctionCall (func, args) ->
    Ast.same_pos_as
      (FunctionCall
         (func,
          List.map
            (fun arg -> partial_evaluation ctx p arg)
            args))
      e

let partially_evaluate (p: program) : program =
  let dep_graph = Dependency.create_dependency_graph p in
  (* TODO: Topological traversal should take into account circularly defined variables *)
  Dependency.TopologicalOrder.fold (fun var p ->
      try
        let def = VariableMap.find var p.program_vars in
        let new_def = match def.var_definition with
          | InputVar -> InputVar
          | SimpleVar e ->
            SimpleVar (partial_evaluation (empty_ctx var None) p e)
          | TableVar (size, def) -> begin match def with
              | IndexGeneric e ->
                TableVar(
                  size,
                  IndexGeneric
                    (partial_evaluation (empty_ctx var None) p e))
              | IndexTable es ->
                TableVar(
                  size,
                  IndexTable
                    (IndexMap.mapi
                       (fun idx e ->
                          (partial_evaluation (empty_ctx var (Some idx)) p e)) es))
            end
        in
        { p with program_vars =
                   VariableMap.add var { def with var_definition = new_def } p.program_vars
        }
      with
      | Not_found ->
        let cond = VariableMap.find var p.program_conds in
        match (partial_evaluation (empty_ctx var None) p cond.cond_expr) with
        | (Literal (Bool false), _) | (Literal Undefined, _) ->
          { p with
            program_conds =
              VariableMap.remove
                var
                p.program_conds
          }
        | (Literal (Bool true) , _) ->   raise (Interpreter.RuntimeError (
            Interpreter.ConditionViolated (
              Printf.sprintf "%s. Errors thrown:\n%s\nViolated condition:\n%s"
                (Format_ast.format_position (Ast.get_position cond.cond_expr))
                (String.concat "\n" (List.map (fun err ->
                     Printf.sprintf "Error %s [%s]" (Ast.unmark err.Error.name) (Ast.unmark err.Error.descr)
                   ) cond.cond_errors))
                (Format_mvg.format_expression (Ast.unmark cond.cond_expr))
            ), Interpreter.empty_ctx
          ))
        | new_cond_expr ->
          { p with
            program_conds =
              VariableMap.add
                var
                { cond with cond_expr = new_cond_expr }
                p.program_conds
          }
    ) dep_graph p
