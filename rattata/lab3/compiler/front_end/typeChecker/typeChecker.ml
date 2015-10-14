(* L2 Compiler
 * TypeChecker
 * Authors: Ben Plaut, William Tong
 * Handles undefined variables in unreachable code, significant simplifications
 *)

open Ast
module A = Ast
open Datatypesv1
module M = Core.Std.Map
open String

let isValidVarDecl (identifier : ident) = 
  if sub identifier 0 1 = "\\" 
  then true 
  else false

let rec tc_expression env (expression : A.untypedPostElabExpr) =
  match expression with
    A.UntypedPostElabConstExpr (constant, typee) -> 
      (match typee with
             INT -> A.IntExpr(IntConst(constant))
           | BOOL -> A.BoolExpr(BoolConst(constant)))
  | A.UntypedPostElabIdentExpr id -> 
      (match M.find env id with (* is it declared? *)
                   Some(typee, isInitialized) -> (if isInitialized (* declared and initialized, all good *)
                                                 then (match typee with
                                                       INT -> A.IntExpr(IntIdent(id))
                                                     | BOOL -> A.BoolExpr(BoolIdent(id)))
                                                 else (ErrorMsg.error None ("uninitialized variable " ^ id ^ "\n");
                                                       raise ErrorMsg.Error))
                 | None -> (ErrorMsg.error None ("undeclared variable " ^ id ^ "\n");
                            raise ErrorMsg.Error))
  | A.UntypedPostElabBinop (e1, op, e2) -> 
      let tcExpr1 = tc_expression env e1 in
      let tcExpr2 = tc_expression env e2 in
      (match op with
             GT -> (match (tcExpr1, tcExpr2) with
                          (IntExpr(exp1), IntExpr(exp2)) -> BoolExpr(GreaterThan(exp1, exp2))
                        | _ -> ErrorMsg.error None ("greater than expression didn't typecheck \n");
                               raise ErrorMsg.Error)
           | LT -> (match (tcExpr1, tcExpr2) with
                          (IntExpr(exp1), IntExpr(exp2)) -> BoolExpr(LessThan(exp1, exp2))
                        | _ -> ErrorMsg.error None ("greater than expression didn't typecheck \n");
                               raise ErrorMsg.Error)
           | DOUBLE_EQ -> 
               (match (tcExpr1, tcExpr2) with
                      (IntExpr(exp1), IntExpr(exp2)) -> BoolExpr(IntEquals(exp1, exp2))
                    | (BoolExpr(exp1), BoolExpr(exp2)) -> BoolExpr(BoolEquals(exp1, exp2))
                    | _ -> ErrorMsg.error None ("double equals expressions didn't typecheck \n");
                           raise ErrorMsg.Error)
           | LOG_AND -> (match (tcExpr1, tcExpr2) with
                               (BoolExpr(exp1), BoolExpr(exp2)) -> BoolExpr(LogAnd(exp1, exp2))
                             | _ -> ErrorMsg.error None ("logical and expressions didn't typecheck \n");
                                    raise ErrorMsg.Error)
           | IntBinop(intOp) -> (match (tcExpr1, tcExpr2) with
                          (IntExpr(exp1), IntExpr(exp2)) -> IntExpr(ASTBinop(exp1, intOp, exp2))
                        | _ -> ErrorMsg.error None ("int binop expressions didn't typecheck \n");
                               raise ErrorMsg.Error))
  | A.UntypedPostElabNot e' -> 
      let tcExpr = tc_expression env e' in
      (match tcExpr with
             BoolExpr(exp1) -> BoolExpr(LogNot(exp1))
           | _ -> ErrorMsg.error None ("not expression didn't typecheck \n");
                  raise ErrorMsg.Error)
  | A.UntypedPostElabTernary(e1, e2, e3) ->
      let tcExpr1 = tc_expression env e1 in
      let tcExpr2 = tc_expression env e2 in
      let tcExpr3 = tc_expression env e3 in
      (match (tcExpr1, tcExpr2, tcExpr3) with
             (BoolExpr(exp1), IntExpr(exp2), IntExpr(exp3)) -> IntExpr(IntTernary(exp1, exp2, exp3))
           | (BoolExpr(exp1), BoolExpr(exp2), BoolExpr(exp3)) -> BoolExpr(BoolTernary(exp1, exp2, exp3))
           | _ -> (ErrorMsg.error None ("ternary expression didn't typecheck \n");
                  raise ErrorMsg.Error))

let rec tc_statements env (untypedAST : untypedPostElabAST) (ret : bool) (typedAST : typedPostElabAST) =
  match untypedAST with
    [] -> (ret, env, typedAST)
  | A.UntypedPostElabBlock(blockStmts)::stmts ->
      let (blockRet, blockEnv, blockAst) = tc_statements env blockStmts ret [] in
      let newRet = ret || blockRet in
      (* We have returned if we return otherwise, or if the block returns *)
      (* Declarations from the block don't count, but initializations do,
         similar to if/else *)
      let newenv = M.mapi env (fun ~key:id -> (fun ~data:value ->
            (match M.find blockEnv id with
                Some (typee, isInit) -> (typee, isInit)
              | None -> assert(false) (* everything in env should be in blockEnv *)))) in
      tc_statements newenv stmts newRet (blockAst @ typedAST)
  | A.UntypedPostElabDecl(id, typee)::stms ->
      (match M.find env id with
                   Some _ -> (ErrorMsg.error None ("redeclared variable " ^ id ^ "\n");
                              raise ErrorMsg.Error)
                 | None -> (let newMap = M.add env id (typee, false) in 
                    tc_statements newMap stms ret ((TypedPostElabDecl(id, typee)) :: typedAST)))
  | A.UntypedPostElabAssignStmt(id, e)::stms ->
       (let tcExpr = tc_expression env e in
          (match M.find env id with (* it's declared, good *)
                 Some(typee, _) -> 
                   (match (tcExpr, typee) with
                          (IntExpr(_), INT) -> 
                            let newMap = M.add env id (typee, true) in  
                            tc_statements newMap stms ret ((TypedPostElabAssignStmt(id, tcExpr)) :: typedAST)
                        | (BoolExpr(_), BOOL) -> 
                            let newMap = M.add env id (typee, true) in              
                            tc_statements newMap stms ret ((TypedPostElabAssignStmt(id, tcExpr)) :: typedAST)
                        | _ -> (ErrorMsg.error None ("assignment expression didn't typecheck \n");
                               raise ErrorMsg.Error))
               | None -> (if ((isValidVarDecl id))
                          then (let newMap = M.add env id (INT, true) in              
                                tc_statements newMap stms ret ((TypedPostElabAssignStmt(id, tcExpr)) :: typedAST))
                          else (ErrorMsg.error None ("undeclared test variable " ^ id ^ "\n");
                                raise ErrorMsg.Error))))
  | A.UntypedPostElabIf(e, ast1, ast2)::stms -> 
      let tcExpr = tc_expression env e in
      (match tcExpr with
             BoolExpr(exp1) -> 
               let (ret1, env1, newast1) = tc_statements env ast1 ret [] in
               let (ret2, env2, newast2) = tc_statements env ast2 ret [] in
               let newret = if ret then ret else (ret1 && ret2) in
               let newenv = M.mapi env (fun ~key:id -> (fun ~data:value ->
                                             (match (M.find env1 id, M.find env2 id) with
                                                    (Some (typee1, isInit1), Some (typee2, isInit2)) -> 
                                                                (typee1, isInit1 && isInit2)
                                                  | (_, _) -> value))) in
               tc_statements newenv stms newret ((TypedPostElabIf(exp1, List.rev newast1, List.rev newast2)) :: typedAST)
           | _ -> ErrorMsg.error None ("if expression didn't typecheck\n");
                  raise ErrorMsg.Error)
  | A.UntypedPostElabWhile(e, ast1, untypedInitAst)::stms -> 
      let (_, newenv2, newast2) = tc_statements env untypedInitAst ret [] in
      let tcExpr = tc_expression newenv2 e in
      (match tcExpr with
             BoolExpr(exp1) ->                
               (* let (_, newenv2, newast2) = tc_statements env untypedInitAst false [] in *)
               let (_, _, newast1) = tc_statements newenv2 ast1 ret [] in
               tc_statements env stms ret ((TypedPostElabWhile(exp1, List.rev newast1)) :: (newast2 @ typedAST))
           | _ -> ErrorMsg.error None ("while expression didn't typecheck\n");
                  raise ErrorMsg.Error)
  | A.UntypedPostElabReturn(e)::stms -> 
      let tcExpr = tc_expression env e in
      (* apparently all variables defined before the first return
         get to be treated as initialized...although those declared
         after don't *)
      let newMap = M.map env (fun (typee, _) -> (typee, true)) in
      (match tcExpr with
             IntExpr(exp1) -> tc_statements newMap stms true ((TypedPostElabReturn(exp1)) :: typedAST)
           | _ -> ErrorMsg.error None ("return expression didn't typecheck\n");
                  raise ErrorMsg.Error)
             (* there was something else here related to the previous comment that I don't quite understand *)
        
and typecheck prog =
  let environment = Core.Std.String.Map.empty in
  let (ret, finalenv, typedast) = tc_statements environment prog false [] in
  if ret then (List.rev typedast) else (ErrorMsg.error None "main does not return\n"; raise ErrorMsg.Error)