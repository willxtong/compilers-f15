(* L3 Compiler
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

let rec argsMatch (arguments : typedPostElabExpr list) (paramTypes : c0type list) =
  match (arguments, paramTypes) with
        ([], []) -> true
      | ([], p :: ps) -> false
      | (arg :: args, []) -> false
      | (arg :: args, p :: ps) ->
          (match (arg, p) with
                 (IntExpr(_), INT) -> argsMatch args ps
               | (BoolExpr(_), BOOL) -> argsMatch args ps
               | _ -> false)

let rec matchParamListTypes (paramTypes : c0type list) (params : param list) =
  match (paramTypes, params) with
        ([], []) -> true
      | ([], p :: ps) -> false
      | (p :: ps, []) -> false
      | (p :: ps, (typee, _) :: remainingParams) -> 
          if ((p = INT && typee = INT) || (p = BOOL && typee = BOOL))
          then matchParamListTypes ps remainingParams else false

let matchFuncTypes funcType1 funcType2 =
  match (funcType1, funcType2) with
        (INT, INT) -> true
      | (BOOL, BOOL) -> true
      | (VOID, VOID) -> true
      | _ -> false

let lowestTypedefType (typedefType : c0type) tbl =
  match typedefType with
        TypedefType(identifier) -> 
          (match M.find tbl identifier with
                 Some(anotherType) -> anotherType
               | None -> (ErrorMsg.error ("undefined typedef \n");
                         raise ErrorMsg.Error))
      | _ -> typedefType

let rec tc_expression funcEnv typedefEnv varEnv (expression : untypedPostElabExpr) =
  match expression with
    UntypedPostElabConstExpr (constant, typee) -> 
      (match typee with
             INT -> IntExpr(IntConst(constant))
           | BOOL -> BoolExpr(BoolConst(constant)))
  | UntypedPostElabIdentExpr id -> 
      (match M.find varEnv id with (* is it declared? *)
                   Some(typee, isInitialized) -> 
                     (if isInitialized (* declared and initialized, all good *)
                      then (match typee with
                                  INT -> IntExpr(IntIdent(id))
                                | BOOL -> BoolExpr(BoolIdent(id)))
                      else (ErrorMsg.error ("uninitialized variable " ^ id ^ "\n");
                            raise ErrorMsg.Error))
                 | None -> (ErrorMsg.error ("undeclared variable " ^ id ^ "\n");
                            raise ErrorMsg.Error))
  | UntypedPostElabBinop (e1, op, e2) -> 
      let tcExpr1 = tc_expression funcEnv typedefEnv varEnv e1 in
      let tcExpr2 = tc_expression funcEnv typedefEnv varEnv e2 in
      (match op with
             GT -> (match (tcExpr1, tcExpr2) with
                          (IntExpr(exp1), IntExpr(exp2)) -> BoolExpr(GreaterThan(exp1, exp2))
                        | _ -> (ErrorMsg.error ("greater than expression didn't typecheck \n");
                               raise ErrorMsg.Error))
           | LT -> (match (tcExpr1, tcExpr2) with
                          (IntExpr(exp1), IntExpr(exp2)) -> BoolExpr(LessThan(exp1, exp2))
                        | _ -> (ErrorMsg.error ("less than expression didn't typecheck \n");
                               raise ErrorMsg.Error))
           | DOUBLE_EQ -> 
               (match (tcExpr1, tcExpr2) with
                      (IntExpr(exp1), IntExpr(exp2)) -> BoolExpr(IntEquals(exp1, exp2))
                    | (BoolExpr(exp1), BoolExpr(exp2)) -> BoolExpr(BoolEquals(exp1, exp2))
                    | _ -> (ErrorMsg.error ("double equals expressions didn't typecheck \n");
                           raise ErrorMsg.Error))
           | LOG_AND -> (match (tcExpr1, tcExpr2) with
                               (BoolExpr(exp1), BoolExpr(exp2)) -> BoolExpr(LogAnd(exp1, exp2))
                             | _ -> (ErrorMsg.error ("logical and expressions didn't typecheck \n");
                                    raise ErrorMsg.Error))
           | IntBinop(intOp) -> (match (tcExpr1, tcExpr2) with
                          (IntExpr(exp1), IntExpr(exp2)) -> IntExpr(ASTBinop(exp1, intOp, exp2))
                        | _ -> (ErrorMsg.error ("int binop expressions didn't typecheck \n");
                               raise ErrorMsg.Error)))
  | UntypedPostElabNot e' -> 
      let tcExpr = tc_expression funcEnv typedefEnv varEnv e' in
      (match tcExpr with
             BoolExpr(exp1) -> BoolExpr(LogNot(exp1))
           | _ -> ErrorMsg.error ("not expression didn't typecheck \n");
                  raise ErrorMsg.Error)
  | UntypedPostElabTernary(e1, e2, e3) ->
      let tcExpr1 = tc_expression funcEnv typedefEnv varEnv e1 in
      let tcExpr2 = tc_expression funcEnv typedefEnv varEnv e2 in
      let tcExpr3 = tc_expression funcEnv typedefEnv varEnv e3 in
      (match (tcExpr1, tcExpr2, tcExpr3) with
             (BoolExpr(exp1), IntExpr(exp2), IntExpr(exp3)) -> IntExpr(IntTernary(exp1, exp2, exp3))
           | (BoolExpr(exp1), BoolExpr(exp2), BoolExpr(exp3)) -> BoolExpr(BoolTernary(exp1, exp2, exp3))
           | _ -> (ErrorMsg.error ("ternary expression didn't typecheck \n");
                  raise ErrorMsg.Error))
  | UntypedPostElabFunCall(i, argList) -> 
      (match M.find funcEnv i with
             Some(funcType, funcParams, _, isExternal) -> 
               let typedArgs = List.map (tc_expression funcEnv typedefEnv varEnv) argList in
               let newFuncName = if isExternal then i else "_c0_" ^ i in
               (* internal functions must be called with prefix _c0_ *)
               if (argsMatch typedArgs funcParams) then 
               (match funcType with
                      INT -> IntExpr(IntFunCall(newFuncName, typedArgs))
                    | BOOL -> BoolExpr(BoolFunCall(newFuncName, typedArgs))
                    | VOID -> VoidExpr(VoidFunCall(newFuncName, typedArgs))
                    | TypedefType(_) -> 
                        (ErrorMsg.error ("shouldn't get here; 
                                          functions should have lowest typedef type \n");
                         raise ErrorMsg.Error))
               else (ErrorMsg.error ("parameters don't typecheck \n");
                     raise ErrorMsg.Error)
           | _ -> (ErrorMsg.error ("function doesn't exist \n");
                  raise ErrorMsg.Error))

(* funcName -> (funcType, list of types of funcParams, isDefined, isExternal) *)
let rec tc_header headerFuncMap headerTypedefMap (header : untypedPostElabAST) = 
  match header with
        [] -> ()
      | fdecl :: fdecls -> 
          (match fdecl with
                 UntypedPostElabTypedef(t, i) ->
                   (match (M.find headerTypedefMap i, M.find headerFuncMap i) with
                          (None, None) -> 
                            let newHeaderTypedefMap = M.add headerTypedefMap i 
                                        (lowestTypedefType t headerTypedefMap) in
                            tc_header headerFuncMap newHeaderTypedefMap fdecls
                        | _ -> (ErrorMsg.error ("cannot shadow previously declared typedef/func names \n");
                                raise ErrorMsg.Error))
               | UntypedPostElabFunDecl(funcType, funcName, funcParams) -> 
                   (match (M.find headerTypedefMap funcName, M.find headerFuncMap funcName) with
                          (Some _, _) -> 
                            (ErrorMsg.error ("trying to shadow used name\n");
                             raise ErrorMsg.Error)
                        | (None, Some (fType, paramTypes, isDefined, isExternal)) ->
                            if not ((matchFuncTypes fType funcType) && (matchParamListTypes paramTypes funcParams))
                            then (ErrorMsg.error ("trying to redeclare func with wrong func type/param types \n");
                                  raise ErrorMsg.Error)
                            else
                              tc_header headerFuncMap headerTypedefMap fdecls
                        | (None, None) -> 
                            (let newHeaderFuncMap = M.add headerFuncMap funcName 
                             (lowestTypedefType funcType headerTypedefMap, 
                             (List.map (fun (c, i) -> c) funcParams), false, true) in
                             tc_header newHeaderFuncMap headerTypedefMap fdecls))
               | _ -> (ErrorMsg.error ("function def'n in header file \n");
                       raise ErrorMsg.Error))

let rec init_func_env = function
    [] -> Core.Std.String.Map.empty
  | (typee, id)::ps ->  M.add (init_func_env ps) id (typee, true)

let rec tc_prog funcMap typedefMap (prog : untypedPostElabAST) (typedAST : typedPostElabAST) =
  match prog with
        [] -> typedAST
      | gdecl :: gdecls ->
          (match gdecl with
                 UntypedPostElabFunDecl(funcType, funcName, funcParams) -> 
                   (match (M.find typedefMap funcName, M.find funcMap funcName) with
                          (Some _, _) -> 
                            (ErrorMsg.error ("trying to shadow used name\n");
                             raise ErrorMsg.Error)
                        | (None, Some (fType, paramTypes, isDefined, isExternal)) ->
                            (if isExternal
                            then (ErrorMsg.error ("trying to redeclare func that was declared in header \n");
                                 raise ErrorMsg.Error)
                            else
                              if not ((matchFuncTypes fType funcType) && (matchParamListTypes paramTypes funcParams))
                              then (ErrorMsg.error ("trying to redeclare func with wrong func type/param types \n");
                                   raise ErrorMsg.Error)
                              else
                                tc_prog funcMap typedefMap gdecls typedAST)
                        | (None, None) -> 
                            let newFuncMap = M.add funcMap funcName 
                            (lowestTypedefType funcType typedefMap, (List.map (fun (c, i) -> c) funcParams), false, false) in
                            tc_prog newFuncMap typedefMap gdecls typedAST)
               | UntypedPostElabFunDef(funcType, funcName, funcParams, funcBody) ->
                   (match (M.find typedefMap funcName, M.find funcMap funcName) with
                          (Some _, _) -> (ErrorMsg.error ("trying to shadow used name \n");
                                          raise ErrorMsg.Error)
                        | (None, Some (fType, paramTypes, isDefined, isExternal)) ->
                            (if (isDefined || isExternal)
                            then (ErrorMsg.error ("trying to define predefined/ external function \n");
                                 raise ErrorMsg.Error)
                            else
                              if not ((matchFuncTypes fType funcType) && (matchParamListTypes paramTypes funcParams))
                              then (ErrorMsg.error ("trying to define func with wrong func type/param types \n");
                                   raise ErrorMsg.Error)
                              else
                                let newFuncMap = M.add funcMap funcName 
                                  (fType, paramTypes, true, false) in
                                let funcVarMap = init_func_env funcParams in
                                let (_, _, typeCheckedBlock) = tc_statements newFuncMap typedefMap funcVarMap 
                                                       funcBody fType false [] in
                                let newFuncName = "_c0_" ^ funcName in
                                (* We're supposed to call internal functions with the prefix _c0_. I'm doing it
                                   here because we know exactly which are internal/external at this point *)
                                  tc_prog newFuncMap typedefMap gdecls (TypedPostElabFunDef(funcType, newFuncName, 
                                  funcParams, List.rev typeCheckedBlock)::typedAST))
                         | (None, None) -> 
                             (if funcName = "main" && 
                                 ((List.length funcParams > 0) || lowestTypedefType funcType typedefMap != INT)
                              then (ErrorMsg.error ("trying to illegally define main \n");
                                    raise ErrorMsg.Error)
                              else
                                (let newFuncMap = M.add funcMap funcName 
                                  (lowestTypedefType funcType typedefMap, 
                                  (List.map (fun (c, i) -> c) funcParams), true, false) in
                                 let funcVarMap = init_func_env funcParams in
                                 let (_, _, typeCheckedFuncBody) = 
                                   tc_statements newFuncMap typedefMap funcVarMap 
                                   funcBody funcType false [] in
                                let newFuncName = "_c0_" ^ funcName in
                                 tc_prog newFuncMap typedefMap gdecls (TypedPostElabFunDef(funcType, newFuncName, 
                                 funcParams, List.rev typeCheckedFuncBody)::typedAST))))
               | UntypedPostElabTypedef(typeDefType, typeDefName) -> 
                   (match (M.find typedefMap typeDefName, M.find funcMap typeDefName) with
                          (None, None) -> 
                            let newTypedefMap = M.add typedefMap typeDefName 
                                        (lowestTypedefType typeDefType typedefMap) in
                            tc_prog funcMap newTypedefMap gdecls typedAST
                        | _ -> (ErrorMsg.error ("cannot shadow previously declared typedef/func names \n");
                                raise ErrorMsg.Error)))

(* varMap is the map of variables within the function body *) 
(* funcRetType is the return type of the function *)         
and tc_statements funcMap typedefMap varMap (untypedBlock : untypedPostElabBlock) (funcRetType : c0type)
                          (ret : bool) (typedBlock : typedPostElabBlock) =
  match untypedBlock with
    [] -> (ret, varMap, typedBlock)
  | A.UntypedPostElabBlock(blockStmts)::stmts ->
      let (blockRet, blockVarMap, blockBlock) = tc_statements funcMap typedefMap varMap blockStmts funcRetType ret [] in
      let newRet = (ret || blockRet) in
      (* We have returned if we return otherwise, or if the block returns *)
      (* Declarations from the block don't count, but initializations do,
         similar to if/else *)
      let newVarMap = M.mapi varMap (fun ~key:id -> (fun ~data:value ->
            (match M.find blockVarMap id with
                Some (typee, isInit) -> (typee, isInit)
              | None -> assert(false) (* everything in varMap should be in blockVarMap *)))) in
      tc_statements funcMap typedefMap newVarMap stmts funcRetType newRet (blockBlock @ typedBlock)
  | A.UntypedPostElabDecl(id, typee)::stms ->
      (match (M.find funcMap id, M.find typedefMap id, M.find varMap id) with
             (None, None, None) -> 
               (let newVarMap = M.add varMap id (typee, false) in 
                tc_statements funcMap typedefMap newVarMap 
                stms funcRetType ret ((TypedPostElabDecl(id, typee)) :: typedBlock))
           | _ -> (ErrorMsg.error ("var names can't shadow func/typedef/declared var names\n");
                   raise ErrorMsg.Error))
  | A.UntypedPostElabAssignStmt(id, e)::stms ->
       (let tcExpr = tc_expression funcMap typedefMap varMap e in
          (match M.find varMap id with (* it's declared, good *)
                 Some(typee, _) -> 
                   (match (tcExpr, typee) with
                          (IntExpr(_), INT) -> 
                            let newVarMap = M.add varMap id (typee, true) in  
                            tc_statements funcMap typedefMap newVarMap 
                            stms funcRetType ret ((TypedPostElabAssignStmt(id, tcExpr)) :: typedBlock)
                        | (BoolExpr(_), BOOL) -> 
                            let newVarMap = M.add varMap id (typee, true) in              
                            tc_statements funcMap typedefMap newVarMap 
                            stms funcRetType ret ((TypedPostElabAssignStmt(id, tcExpr)) :: typedBlock)
                        | _ -> (ErrorMsg.error ("assignment expression didn't typecheck \n");
                               raise ErrorMsg.Error))
               | None -> (if ((isValidVarDecl id))
                          then (let newVarMap = M.add varMap id (INT, true) in              
                                tc_statements funcMap typedefMap newVarMap 
                                stms funcRetType ret ((TypedPostElabAssignStmt(id, tcExpr)) :: typedBlock))
                          else (ErrorMsg.error ("undeclared test variable " ^ id ^ "\n");
                                raise ErrorMsg.Error))))
  | A.UntypedPostElabIf(e, block1, block2)::stms -> 
      let tcExpr = tc_expression funcMap typedefMap varMap e in
      (match tcExpr with
             BoolExpr(exp1) -> 
               let (ret1, varMap1, tcBlock1) = tc_statements funcMap typedefMap varMap block1 funcRetType ret [] in
               let (ret2, varMap2, tcBlock2) = tc_statements funcMap typedefMap varMap block2 funcRetType ret [] in
               let newret = if ret then ret else (ret1 && ret2) in
               let newVarMap = M.mapi varMap (fun ~key:id -> (fun ~data:value ->
                                             (match (M.find varMap1 id, M.find varMap2 id) with
                                                    (Some (typee1, isInit1), Some (typee2, isInit2)) -> 
                                                                (typee1, isInit1 && isInit2)
                                                  | (_, _) -> value))) in
               tc_statements funcMap typedefMap newVarMap stms funcRetType newret 
               ((TypedPostElabIf(exp1, List.rev tcBlock1, List.rev tcBlock2)) :: typedBlock)
           | _ -> ErrorMsg.error ("if expression didn't typecheck\n");
                  raise ErrorMsg.Error)
  | A.UntypedPostElabWhile(e, block1, untypedInitBlock)::stms -> 
      let (_, newVarMap2, tcBlock2) = tc_statements funcMap typedefMap varMap untypedInitBlock funcRetType ret [] in
      let tcExpr = tc_expression funcMap typedefMap newVarMap2 e in
      (match tcExpr with
             BoolExpr(exp1) ->                
               let (_, _, tcBlock1) = tc_statements funcMap typedefMap newVarMap2 block1 funcRetType ret [] in
               tc_statements funcMap typedefMap varMap stms funcRetType ret 
               ((TypedPostElabWhile(exp1, List.rev tcBlock1)) :: (tcBlock2 @ typedBlock))
           | _ -> ErrorMsg.error ("while expression didn't typecheck\n");
                  raise ErrorMsg.Error)
  | A.UntypedPostElabReturn(e)::stms ->
      let tcExpr = tc_expression funcMap typedefMap varMap e in
      (* apparently all variables defined before the first return
         get to be treated as initialized...although those declared
         after don't *)
      let newMap = M.map varMap (fun (typee, _) -> (typee, true)) in
      (match tcExpr with
             IntExpr(exp1) -> 
               (match funcRetType with
                      INT -> tc_statements funcMap typedefMap newMap 
                             stms funcRetType true ((TypedPostElabReturn(IntExpr exp1)) :: typedBlock)
                    | _ -> (ErrorMsg.error ("return expression didn't typecheck\n");
                           raise ErrorMsg.Error))
           | BoolExpr(exp1) -> 
               (match funcRetType with
                      BOOL -> tc_statements funcMap typedefMap newMap 
                              stms funcRetType true ((TypedPostElabReturn(BoolExpr exp1)) :: typedBlock)
                    | _ -> (ErrorMsg.error ("return expression didn't typecheck\n");
                           raise ErrorMsg.Error))
           | VoidExpr(exp1) -> (ErrorMsg.error ("can't return void \n");
                           raise ErrorMsg.Error))
      
  | A.UntypedPostElabVoidReturn::stms -> 
      (match funcRetType with
             VOID -> tc_statements funcMap typedefMap varMap 
                     stms funcRetType true (TypedPostElabVoidReturn :: typedBlock)
           | _ -> ErrorMsg.error ("non-void function must return non-void value \n");
                  raise ErrorMsg.Error)
  | A.UntypedPostElabAssert(e)::stms ->
      let tcExpr = tc_expression funcMap typedefMap varMap e in
      (match tcExpr with
             BoolExpr(expr1) -> tc_statements funcMap typedefMap varMap 
                                stms funcRetType ret (TypedPostElabAssert(expr1) :: typedBlock)
           | _ -> (ErrorMsg.error ("assert must have boolean expression \n");
                  raise ErrorMsg.Error))
  | A.UntypedPostElabExprStmt(e)::stms ->
      let tcExpr = tc_expression funcMap typedefMap varMap e in
      (match tcExpr with
             VoidExpr(stmt) -> tc_statements funcMap typedefMap varMap 
                               stms funcRetType ret (stmt :: typedBlock)
           | _ -> tc_statements funcMap typedefMap varMap 
                  stms funcRetType ret (TypedPostElabAssignStmt(GenUnusedID.create(), tcExpr) :: typedBlock))
       
and typecheck ((untypedProgAST, untypedHeaderAST) : untypedPostElabOverallAST) =
  let funcMap = Core.Std.String.Map.empty in
  let typedefMap = Core.Std.String.Map.empty in
  let () = tc_header funcMap typedefMap untypedHeaderAST in
  let typedProgAST = tc_prog funcMap typedefMap untypedProgAST [] in
  List.rev typedProgAST

(* BUGS:
basic typedef: typedef int poop, poop x = 0 (also shouldn't be able to use function names as types
used functions must be defined
non-void functions must return
cannot use id's as types until typedef'd
local vars can shadow function names (f is a function, int f is allowed)
   
*)
