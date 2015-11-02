open Datatypesv1
module A = Ast
module M = Core.Std.Map
module H = Hashtbl             
open Core.Std

(* Pretty much everything here is mutually recursive because of
   ternary operators *)

(* maps each function name to an array of the types of its params.
   We need this because we need to know the sizes of the args
   are so that we can use the correct-size mov. *)
let funParamsMap = H.create 10

(* General note: we have asnops now because we can't elaborate A[f(A)] +=1
   to A[f(A)] = A[f(A)] + 1 anymore :( *)

let getSizeForType = function
    INT -> BIT32
  | BOOL -> BIT32
  | Pointer _ -> BIT64
  | _ -> let () = print_string("I'm not sure if this case is valid or not,\
                                assert false for now") in assert(false)
let getSizeForExpr = function
    TmpIntExpr _ -> BIT32
  | TmpBoolExpr _ -> BIT32
  | TmpPtrExpr _ -> BIT64

let get_or_make_tmp id idToTmpMap = (match M.find idToTmpMap id with
              None -> Temp.create()
            | Some t -> t)

(* Note: there's a function in memStuffToInfAddr that is identical...
   I'm sorry, style gods *)
let addTypeToShared e = function
    INT -> TmpIntExpr (TmpIntSharedExpr e)
  | BOOL -> TmpBoolExpr (TmpBoolSharedExpr e)
  | Pointer _ -> TmpPtrExpr (TmpPtrSharedExpr e)
  | _ -> assert(false)                   

let addTypeToTmp t = function
    INT -> TmpIntExpr (TmpIntArg (TmpLoc (Tmp t)))
  | BOOL -> TmpBoolExpr (TmpBoolArg (TmpLoc (Tmp t)))
  | Pointer _ -> TmpPtrExpr (TmpPtrArg (TmpLoc (Tmp t)))
  | _ -> assert(false)                   

let rec handle_shift retTmp retLabel idToTmpMap (e1, op, e2) =
    let max_shift = A.IntConst 31 in
    let new_id = GenUnusedID.create () in
    let result_tmp = Temp.create() in
    let newMap = M.add idToTmpMap new_id result_tmp in
        (* whatever gets put in new_id should end up in result_tmp *)
      (* Now: we need one for the div-by-zero instr we're about to add *)
        (* NOTE: e2 not e1!! *)
    let baseCaseShiftOp = (match op with
                              LSHIFT -> A.ASTlshift
                            | RSHIFT -> A.ASTrshift
                            | _ -> assert(false)) in
    (* Here's the trick: we actually have to evaluate the left hand size
       (the thing being shifted) first, because of side effects. *)
    let lhs_id = GenUnusedID.create () in
    let evaluateLHS = A.TypedPostElabAssignStmt(lhs_id, A.EQ, A.IntExpr e1) in
    (* We also need to make sure to only evluate the RHS once, because
       of side effects. *)
    let rhs_id = GenUnusedID.create () in
    let evaluateRHS = A.TypedPostElabAssignStmt(rhs_id, A.EQ, A.IntExpr e2) in
    let isNonNegative = A.GreaterThan(A.IntSharedExpr (A.Ident rhs_id),
                                      A.IntConst (-1)) in
    let isSmallEnough = A.LogNot (A.GreaterThan(A.IntSharedExpr (A.Ident rhs_id),
                                                max_shift)) in
    let condition = A.LogAnd (isNonNegative, isSmallEnough) in
          (* If shift is too big, or is negative, div by zero.
             Else, do the shift *)
    let doTheShift = A.TypedPostElabAssignStmt(new_id, A.EQ, A.IntExpr
                 (A.BaseCaseShift(A.IntSharedExpr (A.Ident lhs_id), baseCaseShiftOp,
                                  A.IntSharedExpr (A.Ident rhs_id))))::[] in
    let divByZero = A.TypedPostElabAssignStmt(new_id, A.EQ, A.IntExpr
                 (A.ASTBinop(A.IntConst 666, FAKEDIV, A.IntConst 0)))::[] in
    let shiftCond = A.TypedPostElabIf(condition, doTheShift, divByZero) in
       (trans_stmts retTmp retLabel newMap
             (evaluateLHS::evaluateRHS::shiftCond::[]),
       TmpIntArg (TmpLoc (Tmp result_tmp)))

and trans_exp retTmp retLabel idToTmpMap = function
      A.IntExpr e -> let (instrs, e') = trans_int_exp retTmp retLabel idToTmpMap e
                     in (instrs, TmpIntExpr e')
    | A.BoolExpr e -> let (instrs, t) = trans_bool_exp retTmp retLabel
                          idToTmpMap e None in
                      (instrs, TmpBoolExpr (TmpBoolArg (TmpLoc t)))

(* Returns a list of tmpExprs, resulting from calling trans_exp on each of the args *)
and trans_fun_args retTmp retLabel fName idToTmpMap exp_list =
  (* Here's the deal: we have to make sure to evaluate the args from left to right.
     So we need to put them each into new tmps before we make the function call. *)
      let newTmps = Array.of_list(List.map exp_list
                                    (fun _ -> Tmp (Temp.create()))) in
      let instr_and_e_list = List.map exp_list (trans_exp retTmp retLabel
                                                  idToTmpMap) in
      let getSizeForArg = fun i -> getSizeForType (H.find funParamsMap fName).(i) in
      let instrs = List.concat (List.mapi instr_and_e_list
        (fun i -> fun (instrs, e) -> instrs @
                         [TmpInfAddrMov(getSizeForArg i, e,
                                        TmpVarLVal newTmps.(i))])) in
      let newTmpExprs = List.map (Array.to_list newTmps)
            (fun t -> TmpIntExpr (TmpIntArg (TmpLoc t))) in
      (instrs, newTmpExprs)

(* Returns a tuple (instrs, e) where e is the resulting expression,
   and instrs is any required instructions (which is empty for everything
   but ternary *)
and trans_int_exp retTmp retLabel idToTmpMap = function
       A.IntConst c -> ([], TmpIntArg (TmpConst c))
     | A.ASTBinop (e1, LSHIFT, e2) ->
         handle_shift retTmp retLabel idToTmpMap (e1, LSHIFT, e2)
     | A.ASTBinop (e1, RSHIFT, e2) ->
         handle_shift retTmp retLabel idToTmpMap (e1, RSHIFT, e2)
     | A.BaseCaseShift (e1, shiftOp, e2) ->
         let (instrs_for_exp1, tmp_exp1) =
          trans_int_exp retTmp retLabel idToTmpMap e1 in
         let (instrs_for_exp2, tmp_exp2) =
          trans_int_exp retTmp retLabel idToTmpMap e2 in
     
         let actualShiftOp = (match shiftOp with
                                     A.ASTrshift -> RSHIFT
                                   | A.ASTlshift -> LSHIFT) in
          (instrs_for_exp1 @ instrs_for_exp2,
           TmpInfAddrBinopExpr (actualShiftOp, tmp_exp1, tmp_exp2))
     | A.ASTBinop (e1, op, e2) ->
         let (instrs_for_exp1, tmp_exp1) =
             trans_int_exp retTmp retLabel idToTmpMap e1 in
         let (instrs_for_exp2, tmp_exp2) =
             trans_int_exp retTmp retLabel idToTmpMap e2 in
         (instrs_for_exp1 @ instrs_for_exp2,
          TmpInfAddrBinopExpr (op, tmp_exp1, tmp_exp2))
         
     | A.IntSharedExpr e ->
         let (instrs, TmpIntExpr eInfAddr) = trans_shared_expr retTmp retLabel INT
                                  idToTmpMap e in
         (instrs, eInfAddr)

and trans_shared_expr retTmp retLabel exprType idToTmpMap = function
    A.FunCall (fName, argList) ->
         let (instrs, argExps) = trans_fun_args retTmp retLabel fName
             idToTmpMap argList in
         (instrs, addTypeToShared (TmpInfAddrFunCall(fName, argExps)) exprType)
  | A.ArrayAccess (arrayExpr, idxExpr) ->
        (* evaluate the array first! *)
        let (arrayInstrs, TmpPtrExpr arrayFinalExpr) = 
            trans_exp retTmp retLabel idToTmpMap (A.PtrExpr arrayExpr) in
        let (idxInstrs, TmpIntExpr idxFinalExpr) = 
            trans_exp retTmp retLabel idToTmpMap (A.IntExpr idxExpr) in
        (arrayInstrs @ idxInstrs, addTypeToShared
           (TmpInfAddrArrayAccess (arrayFinalExpr, idxFinalExpr)) exprType)
  | A.FieldAccess (structName, structPtr, fieldName) ->
        let (ptrInstrs, TmpPtrExpr structPtrExpr) =
            trans_exp retTmp retLabel idToTmpMap (A.PtrExpr structPtr) in
        (ptrInstrs, addTypeToShared
         (TmpInfAddrFieldAccess (structName, structPtrExpr, fieldName)) exprType)
  | A.Deref ptr ->
        let (ptrInstrs, TmpPtrExpr ptrFinal) =
            trans_exp retTmp retLabel idToTmpMap (A.PtrExpr ptr) in
        (ptrInstrs, addTypeToShared (TmpInfAddrDeref ptrFinal) exprType)
  | A.Ident id ->
        (match M.find idToTmpMap id with
             None -> 
             (let () = print_string("Uninitialized: " ^ id ^ "\n") in
              assert(false))
           | Some t -> 
             ([], addTypeToTmp t exprType))
  | A.Ternary (c, e1, e2) ->
      (* We create a new variable and a new ast that puts e1
         into this variable is c is true, otherwise e2. Then
         we can just recurse on a new conditional, with that var as
         the condition *)
      let ternary_result_tmp = Temp.create() in
      let ternary_result_id = GenUnusedID.create() in
      let newMap = M.add idToTmpMap ternary_result_id ternary_result_tmp in
      let astForIf = [A.TypedPostElabAssignStmt (ternary_result_id,
                                               A.EQ, e1)] in
      let astForElse = [A.TypedPostElabAssignStmt (ternary_result_id,
                                                 A.EQ, e2)] in
      let ternary_instrs = trans_cond retTmp retLabel newMap
                           (c, astForIf, astForElse) in
      let result_exp = addTypeToTmp ternary_result_tmp exprType in
      (ternary_instrs, result_exp)
      
(* This returns a tmp t and a list of statements required to put
   e in t. What we do to handle short-circuit here is just say
   if (e) t = true; else t = false;
*)
and trans_bool_exp retTmp retLabel idToTmpMap e dest =
    let t = (match dest with
                 None -> Temp.create()
               | Some t' -> t') in
    match e with
        A.BoolConst c ->
            (TmpInfAddrMov(getSizeForType BOOL, TmpBoolExpr
                             (TmpBoolArg (TmpConst c)), (TmpVarLVal (Tmp t)))
            ::[], Tmp t)
      | _ ->
    (* Ok this is kind of hacky but here it is: the functions that
       take "if (e) t = true; else t = false;" to infAddr all take
       asts as input, but asts only take idents, not tmps. So we
       create an ident that is guaranteed to not already be an ident
       (GenUnusedID basically puts "\\" at the front of id's, which
       cannot be part of the input), and map it to t. *)
    let identForT = GenUnusedID.create() in
    let newMap = M.add idToTmpMap identForT t in
    let ifStmts = [A.TypedPostElabAssignStmt
                     (identForT, A.EQ, A.BoolExpr (A.BoolConst 1))] in
    let elseStmts = [A.TypedPostElabAssignStmt
                       (identForT, A.EQ, A.BoolExpr (A.BoolConst 0))] in
    (* Translating this if statement puts expression e in temp t.
       We also need to return the resulting location. *)
    (trans_stmts retTmp retLabel newMap [A.TypedPostElabIf (e, ifStmts, elseStmts)],
     Tmp t)

(* For a while loop, typically we jump back to the top if the
   if condition is true. This would be jumpToTopStatus =
   ifJumpsToStop. However, since we switch around if and else to
   deal with negation and such, the else might have to the jump
   back to the top. Of course, for a normal if statement,
   neither jumps to top. *)
and make_cond_instrs retTmp retLabel idToTmpMap priorInstr stmtsForIf stmtsForElse
    ifJumpType elseJumpType =
    let elseLabel = GenLabel.create() in
    let endLabel = GenLabel.create() in
    if stmtsForIf = [] then
          (priorInstr
          ::TmpInfAddrJump(ifJumpType, endLabel)
          ::trans_stmts retTmp retLabel idToTmpMap stmtsForElse
          @ TmpInfAddrLabel(endLabel) :: []) else
    if stmtsForElse = [] then
          (priorInstr
          ::TmpInfAddrJump(elseJumpType, endLabel)
          ::trans_stmts retTmp retLabel idToTmpMap stmtsForIf
          @ TmpInfAddrLabel(endLabel) :: [])
    else
          (priorInstr
          ::TmpInfAddrJump(elseJumpType, elseLabel)
          ::trans_stmts retTmp retLabel idToTmpMap stmtsForIf
          @ TmpInfAddrJump(JMP_UNCOND, endLabel)
          ::TmpInfAddrLabel(elseLabel)
          ::trans_stmts retTmp retLabel idToTmpMap stmtsForElse
          @ TmpInfAddrLabel(endLabel) :: [])


(* We use this function for both ifs and whiles. We pass in
   make_instrs_fn, which creates the structure which kind of
   wraps the statements in side the if/while. So for if, if will
   create if/else/end labels, and there will be an unconditional
   jump at the end of if and else. But for while, there will be
   a start label (and no else label), and there will be an
   unconditional jump to the start label after the if *)
and trans_cond retTmp retLabel idToTmpMap (condition, stmtsForIf, stmtsForElse) 
  : tmpInfAddrInstr list =
     match condition with
         A.LogNot negCondition ->
        (* In this case, just switch the statements for if and else,
           AND ALSO THE JUMPTOTOPSTATUS <--- I think I got rid of that *)
              trans_cond retTmp retLabel idToTmpMap (negCondition, stmtsForElse,
                                   stmtsForIf)
       | A.LogAnd (bool_exp1, bool_exp2) -> 
          (* For &&, we break it up into nested if statements, where each
             of them gets the "else" from the original. *)
           let innerIfAst = [A.TypedPostElabIf (bool_exp2, stmtsForIf,
                                                stmtsForElse)] in
            trans_cond retTmp retLabel idToTmpMap (bool_exp1, innerIfAst,
                                 stmtsForElse) 
              (* ONLY THE INNER ONE JUMPS TO TOP FIX THISSSSSSSSSSSSSS *)
       | A.BoolConst c -> (match c with
                              1 -> trans_stmts retTmp retLabel idToTmpMap stmtsForIf
                            | 0 -> trans_stmts retTmp retLabel idToTmpMap stmtsForElse
                            | _ -> assert(false))
       | A.GreaterThan (int_exp1, int_exp2) -> 
           (* NOTE THAT WE SWITCH THE ORDER BECAUSE CMP IS WEIRD *)
         (* MAKE SURE TO CHECK THIS. Pretty sure it's right though *)
            let (instrs_for_exp1, tmp_exp1) =
               trans_int_exp retTmp retLabel idToTmpMap int_exp1 in
            let (instrs_for_exp2, tmp_exp2) =
               trans_int_exp retTmp retLabel idToTmpMap int_exp2 in
            let priorInstr = TmpInfAddrBoolInstr
                 (TmpInfAddrCmp(getSizeForType INT, TmpIntExpr tmp_exp2,
                                TmpIntExpr tmp_exp1)) in
            instrs_for_exp1 @ instrs_for_exp2 @
              (make_cond_instrs retTmp retLabel idToTmpMap priorInstr stmtsForIf
                 stmtsForElse JG JLE )
       | A.LessThan (int_exp1, int_exp2) -> 
           (* NOTE THAT WE SWITCH THE ORDER BECAUSE CMP IS WEIRD *)
         (* MAKE SURE TO CHECK THIS. Pretty sure it's right though *)
            let (instrs_for_exp1, tmp_exp1) =
               trans_int_exp retTmp retLabel idToTmpMap int_exp1 in
            let (instrs_for_exp2, tmp_exp2) =
               trans_int_exp retTmp retLabel idToTmpMap int_exp2 in
            let priorInstr = TmpInfAddrBoolInstr
                 (TmpInfAddrCmp(getSizeForType INT, TmpIntExpr tmp_exp2,
                                TmpIntExpr tmp_exp1)) in
            instrs_for_exp1 @ instrs_for_exp2 @
              (make_cond_instrs retTmp retLabel idToTmpMap priorInstr stmtsForIf
                 stmtsForElse JL JGE )
       | A.IntEquals (int_exp1, int_exp2) ->
            let (instrs_for_exp1, tmp_exp1) =
               trans_int_exp retTmp retLabel idToTmpMap int_exp1 in
            let (instrs_for_exp2, tmp_exp2) =
               trans_int_exp retTmp retLabel idToTmpMap int_exp2 in
            let priorInstr = TmpInfAddrBoolInstr
            (TmpInfAddrCmp(getSizeForType INT, TmpIntExpr tmp_exp2,
                           TmpIntExpr tmp_exp1)) in
            instrs_for_exp1 @ instrs_for_exp2 @
              (make_cond_instrs retTmp retLabel idToTmpMap priorInstr stmtsForIf stmtsForElse
                 JE JNE )
       | A.BoolEquals (bool_exp1, bool_exp2) ->
            (* See description of trans_bool_exp *)
            let (instrs_for_exp1, tmp_exp1) =
               trans_bool_exp retTmp retLabel idToTmpMap bool_exp1 None in
            let (instrs_for_exp2, tmp_exp2) =
               trans_bool_exp retTmp retLabel idToTmpMap bool_exp2 None in
            let priorInstr = TmpInfAddrBoolInstr
                (TmpInfAddrCmp (getSizeForType BOOL,
                                TmpBoolExpr (TmpBoolArg (TmpLoc tmp_exp1)),
                                TmpBoolExpr (TmpBoolArg (TmpLoc tmp_exp2)))) in
            (* The order of instrs_for_exp1/2 shouldn't matter *)
            instrs_for_exp1 @ instrs_for_exp2 @
            (make_cond_instrs retTmp retLabel idToTmpMap priorInstr stmtsForIf
                 stmtsForElse JE JNE )
       | A.BoolSharedExpr e ->
          let (instrs, TmpBoolExpr eInfAddr) =
            trans_shared_expr retTmp retLabel BOOL idToTmpMap e in
          let priorInstr = TmpInfAddrBoolInstr
                 (TmpInfAddrTest (eInfAddr, TmpBoolArg (TmpConst 1))) in
          instrs @ make_cond_instrs retTmp retLabel idToTmpMap
            priorInstr stmtsForIf stmtsForElse JNE JE
       | A.PtrEquals _ -> failwith "Ben, do this!"

(* returns (newMap, infAddrLVal, instrs *)
(* pretty sure newMap is only different from the input map in the var
   case, because otherwise, the id should already have been initalized *)
and trans_lval retTmp retLabel idToTmpMap = function
     A.TypedPostElabVarLVal id -> let t = get_or_make_tmp id idToTmpMap in
                                  let newMap = M.add idToTmpMap id t in
                                  (newMap, TmpVarLVal (Tmp t), [])
   | A.TypedPostElabFieldLVal (structName, structPtrLVal, fieldName) ->
        let (newMap, structTmpLVal, instrs) =
           trans_lval retTmp retLabel idToTmpMap structPtrLVal in
        (newMap, TmpFieldAccessLVal(structName, structTmpLVal, fieldName), instrs)
   | A.TypedPostElabArrayAccessLVal (arrayLVal, idxExpr) ->
       (* Note: arrayLVal is evaluating first! This matters for things like
          a[1/0][f()] where f is function that asserts false *)
        let (newMap, arrayTmpLVal, instrsForArray) =
           trans_lval retTmp retLabel idToTmpMap arrayLVal in
        let (instrsForIdx, TmpIntExpr idxFinal) =
           trans_exp retTmp retLabel idToTmpMap idxExpr in
        (newMap, TmpArrayAccessLVal (arrayTmpLVal, idxFinal),
         instrsForArray @ instrsForIdx)
   | A.TypedPostElabDerefLVal (ptrLVal) ->
        let (newMap, ptrTmpLVal, instrs) =
          trans_lval retTmp retLabel idToTmpMap ptrLVal in
        (newMap, TmpDerefLVal ptrTmpLVal, instrs)

and trans_stmts retTmp retLabel idToTmpMap = function
     A.TypedPostElabDecl (id, idType)::stmts ->
      (* Just create a single temp per variable for now,
         instead of creating one each assignment *)
        let t = Temp.create() in
        let newMap = M.add idToTmpMap id t in
        trans_stmts retTmp retLabel newMap stmts
   | A.TypedPostElabAssignStmt (lval, asnop, e)::stmts ->
     (* Note: lval gets evaluated first! *)
     let (newMap, tmplval, instrsForLVal) =
         trans_lval retTmp retLabel idToTmpMap lval in
     let (instrs_for_e, eInfAddr) = trans_exp retTmp retLabel idToTmpMap e in
r          (* trans_exp gives us the instructions it generated, and also where it
             ended up putting the value. We then update the binding in idToTmpMap *)
        instrsForLVal @ instrs_for_e @
        TmpInfAddrMov (getSizeForExpr eInfAddr, eInfAddr, tmplval)
        ::trans_stmts retTmp retLabel newMap stmts
   | A.TypedPostElabIf (e, ifStmts, elseStmts) :: stmts ->
       trans_cond retTmp retLabel idToTmpMap (e, ifStmts, elseStmts) @
        trans_stmts retTmp retLabel idToTmpMap stmts
   | A.TypedPostElabWhile (e, whileStmts) :: stmts ->
        let topLabel = GenLabel.create() in
        let jumpToTopStmt = A.JumpUncond(topLabel) in
        (* Empty list because no else statements *)
        TmpInfAddrLabel topLabel::
        trans_cond retTmp retLabel idToTmpMap (e, whileStmts @ [jumpToTopStmt], []) @
        trans_stmts retTmp retLabel idToTmpMap stmts
   | A.JumpUncond target :: stmts ->
     (* This really shouldn't be an AST instruction
        but I need it for toInfAddr :( *)
        TmpInfAddrJump(JMP_UNCOND, target)::trans_stmts retTmp retLabel idToTmpMap stmts
   | A.TypedPostElabReturn e :: stmts ->
        let (instrs_for_e, eInfAddr) = trans_exp retTmp retLabel idToTmpMap e in
        (* Move our value to the ret tmp, then jump to the return *)
        instrs_for_e @
        TmpInfAddrMov(getSizeForExpr eInfAddr, eInfAddr, retTmp)::
        TmpInfAddrJump(JMP_UNCOND, retLabel) :: []
   | A.TypedPostElabAssert e :: stmts ->
     (* If e is true we proceed on, else we call the abort function, with
     no arguments *)
        let callAbortAst = A.TypedPostElabIf (e, stmts,
                                     [A.VoidFunCall("abort", [])])::[] in
        trans_stmts retTmp retLabel idToTmpMap callAbortAst
   | A.VoidFunCall (fName, argList)::stmts ->
        let (instrs, argExps) = trans_fun_args retTmp retLabel fName
                                idToTmpMap argList in
        instrs @ TmpInfAddrVoidFunCall(fName, argExps)::[]
        @ trans_stmts retTmp retLabel idToTmpMap stmts
   | A.TypedPostElabVoidReturn::stmts -> TmpInfAddrJump(JMP_UNCOND, retLabel)::[]
   | [] -> []

(* We assume that this is run after typechecking, so everything is
   declared initialized, etc *)

let initIdToTmpMap params =
  (* Create temps for each of the params, and init the idToTmpMap
     accordingly *)
    let params_with_tmps = List.map params (fun (_,id) -> (id, Temp.create())) in
    match String.Map.of_alist params_with_tmps with
         `Duplicate_key _ -> failwith "params must have unique names"
       | `Ok (result) -> result

let updateFunParamsMap fName params =
    let typesArray = Array.of_list (List.map params (fun (typee, _) -> typee)) in
    H.add funParamsMap fName typesArray
    

let trans_global_decl decl =
  (* Each function has a unique retTmp and retLabel *)
    let retLabel = GenLabel.create() in
    let retTmp = Tmp (Temp.create()) in
    match decl with
        A.TypedPostElabStructDef (structName, fields) ->
            TmpStructDef (structName, fields)
      | A.TypedPostElabFunDef (typee, fName, params, stmts) ->
            let idToTmpMap = initIdToTmpMap params in
            let param_tmp_list = List.map params (fun (_, id) ->
                   match M.find idToTmpMap id with
                       Some t -> Tmp t
                     | None -> assert(false)) in
            let infAddrStmts = trans_stmts retTmp retLabel idToTmpMap stmts in
            let finalStmts = infAddrStmts @ TmpInfAddrLabel retLabel ::
            let retSize = getSizeForType typee in 
            TmpInfAddrReturn (retSize, TmpIntExpr (TmpIntArg
                                                     (TmpLoc (retTmp))))::[] in
            TmpInfAddrFunDef (fName, param_tmp_list, finalStmts)

let toInfAddr (funDefList: A.typedPostElabAST) =
     (* We will have a simple return label that all returns jump to *)
     List.map funDefList trans_global_decl
