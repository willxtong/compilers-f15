open Datatypesv1
module H = Hashtbl
(* For an array of size n, we allocate n + 8 bytes, store the
   length of the array in the address (a-8), where a is the
   pointer that we use for this array in the rest of the program *)

(* This maps each struct type name to (m, size), where size is the total
   size of the struct and m is
   another map: one that maps each field name to the offset
   from the base pointer to the struct *)
let structDefsMap = H.create 100 

let smallFieldSize = 4
let ptrFieldSize = 8
let ptrAlignment = 8  

let rec makeStructInnerMap fields offset map =
      match fields with
         [] -> offset
       | (fieldType, fieldName)::rest ->
           let fieldSize = (match fieldType with
                               INT -> smallFieldSize
                             | BOOL -> smallFieldSize
                             | Pointer _ -> ptrFieldSize
                             | Array _ -> ptrFieldSize
                             | _ -> assert(false)) in
           let currFieldOffset =
        (* If it's an int or a bool, it's always fine, since
           all addresses with be mod 4. If it's a pointer, buffer it
           so that it is correctly aligned *)
              (if fieldSize = smallFieldSize then offset
              else if offset mod ptrAlignment = 0 then offset
              else offset + (ptrAlignment - (offset mod ptrAlignment))) in
           let nextFieldOffset = currFieldOffset + fieldSize in
           let () = H.add map fieldName currFieldOffset in
           makeStructInnerMap rest nextFieldOffset map
                
let updateStructDefsMap structTypeName fields =
   (* First create the inner map. Assuming the base pointer of the
      struct is 8-byte aligned, this ensures that ints/bools are
      4-byte aligned, and pointers are 8-byte aligned *)
      let initialOffset = 0 in
      let innerMap = H.create (List.length fields) in
      let structTotalSize = makeStructInnerMap fields initialOffset innerMap in
      H.add structDefsMap structTypeName (innerMap, structTotalSize)

let getSizeForType = function
     INT -> smallFieldSize
   | BOOL -> smallFieldSize
   | Pointer _ -> ptrFieldSize
   | Array _ -> ptrFieldSize
   | Struct structTypeName ->
        (try let (_, structSize) = H.find structDefsMap structTypeName in
            structSize
        with Not_found -> (let () = print_string("struct " ^ structTypeName
                             ^ "not defined before alloc\n") in
                           assert(false)))
   | VOID -> assert(false)
   | TypedefType _ -> assert(false)

let sharedExprToTypedExpr exprType sharedExpr =
     match exprType with
         INT -> TmpIntExpr (TmpIntSharedExpr sharedExpr)
       | BOOL -> TmpBoolExpr (TmpBoolSharedExpr sharedExpr)
       | Pointer _ -> TmpPtrExpr (TmpPtrSharedExpr sharedExpr)
       | _ -> assert(false)

(* we need the type in order to calculate array offsets *)
let rec handleSharedExpr exprType = function
     TmpInfAddrFunCall (fName, args) ->
        (sharedExprToTypedExpr exprType (TmpInfAddrFunCall(fName, args)), [])
   | TmpInfAddrDeref (ptrExp) ->
       let (TmpPtrExpr e_result, instrs) = handleMemForExpr (TmpPtrExpr ptrExp) in
       (sharedExprToTypedExpr exprType (TmpInfAddrDeref e_result), instrs)
   | TmpInfAddrFieldAccess(structTypeName, structPtr, fieldName) -> assert(false)
       (* try let (fieldOffsets, _) = H.find structDefsMap structTypeName in *)
       (* with Not_found -> (let () = print_string("struct " ^ structTypeName *)
       (*                                        ^ "not defined before alloc\n") in *)
       (*                  assert(false)) *)
   | TmpInfAddrArrayAccess (ptrExp, indexExpr) ->
       handleArrayAccess exprType ptrExp indexExpr

(* returns (e, instrs) pair *)
and handleMemForExpr = function
      TmpBoolExpr (TmpBoolArg arg) -> (TmpBoolExpr (TmpBoolArg arg), [])
    | TmpPtrExpr (TmpPtrArg arg) -> (TmpPtrExpr (TmpPtrArg arg), [])
    | TmpIntExpr (TmpIntArg arg) -> (TmpIntExpr (TmpIntArg arg), [])
    | TmpIntExpr (TmpInfAddrBinopExpr (op, e1, e2)) ->
        let (TmpIntExpr e1_result, instrs1) = handleMemForExpr (TmpIntExpr e1) in
        let (TmpIntExpr e2_result, instrs2) = handleMemForExpr (TmpIntExpr e2) in
        (* We have to make sure we're evaluating e1 before e2. So if
           there were any instructions created that involved evaluating
           e2, we need to make sure e1 happens before. We do this
           by moving e1 to a new tmp beforehand. *)
        let (final_e1, final_instrs1) =
             (match instrs2 with
                 [] -> (e1_result, instrs1)
               | _ -> (let t = Tmp (Temp.create()) in (TmpIntArg (TmpLoc t),
                       instrs1 @ TmpInfAddrMov32(TmpIntExpr e1_result, t)::[])))
            in
        (TmpIntExpr (TmpInfAddrBinopExpr(op, final_e1, e2_result)),
         final_instrs1 @ instrs2)
    | TmpPtrExpr (TmpAlloc typee) -> 
           (* alloc becomes a function call to malloc *) 
             (TmpPtrExpr (TmpPtrSharedExpr (TmpInfAddrFunCall ("malloc",
              TmpIntExpr (TmpIntArg (TmpConst (getSizeForType typee)))::[]))),
              [])
                                         
    | TmpBoolExpr (TmpBoolSharedExpr e) ->
         let (e_result, instrs) = handleSharedExpr BOOL e in
         (TmpBoolExpr (TmpBoolSharedExpr e_result), instrs)
    | TmpIntExpr (TmpIntSharedExpr e) -> 
         let (e_result, instrs) = handleSharedExpr INT e in
         (TmpBoolExpr (TmpBoolSharedExpr e_result), instrs)
    (* | TmpPtrExpr (TmpPtrSharedExpr e) -> handleSharedExpr Pointer *)
    | _ -> failwith "not yet implemented"          

  
and handleArrayAccess elemType ptrExp indexExpr =
       let (TmpPtrExpr ptr_final, ptr_instrs) =
           handleMemForExpr (TmpPtrExpr ptrExp) in
       let (TmpIntExpr index_final, index_instrs) =
           handleMemForExpr (TmpIntExpr indexExpr) in
       let elemSize = getSizeForType elemType in
       (* The number of elems is stored at the address ptr_final - 8 *)
       let numElemsPtr = TmpInfAddrSub64(ptr_final, TmpIntArg (TmpConst 8)) in
       let numElemsExpr = TmpIntSharedExpr (TmpInfAddrDeref numElemsPtr) in
       let resultTmp = Tmp (Temp.create()) in
       let errorLabel = GenLabel.create() in
       let doTheAccessLabel = GenLabel.create() in
       (* Note that the operand order for cmp has already been reversed!
          So cmp (a,b) followed by jg will jump is b > a *)
       let indexLowerCheck = TmpInfAddrBoolInstr (TmpInfAddrCmp32(
           TmpIntExpr (TmpIntArg (TmpConst 0)), TmpIntExpr index_final))::
           TmpInfAddrJump(JL, errorLabel)::[] in
       let indexUpperCheck = TmpInfAddrBoolInstr (TmpInfAddrCmp32(
           TmpIntExpr numElemsExpr, TmpIntExpr index_final))::
                             TmpInfAddrJump(JGE, errorLabel)::
                             TmpInfAddrJump(JL, doTheAccessLabel)::[] in
       let throwError = TmpInfAddrVoidFunCall("raise",
                              TmpIntExpr (TmpIntArg (TmpConst 12))::[]) in
       let accessOffsetExpr = TmpInfAddrBinopExpr(MUL,
                          TmpIntArg (TmpConst (getSizeForType elemType)),
                                              numElemsExpr) in
       let accessPtrExpr = TmpInfAddrAdd64(ptr_final, accessOffsetExpr) in
       let doTheAccess = (match elemType with
                    BOOL -> TmpInfAddrMov32(TmpBoolExpr (TmpBoolSharedExpr
                               (TmpInfAddrDeref accessPtrExpr)), resultTmp)
                  | INT -> TmpInfAddrMov32(TmpIntExpr (TmpIntSharedExpr
                               (TmpInfAddrDeref accessPtrExpr)), resultTmp)
                  | Pointer _ -> TmpInfAddrMov64(TmpPtrSharedExpr
                               (TmpInfAddrDeref accessPtrExpr), resultTmp)
                  | _ -> assert(false)) in
      (* Ok now actually put all of the instructions together *)
      (* The array pointer is evaluated first, I checked *)
      let allInstrs = ptr_instrs @ index_instrs @ indexLowerCheck
             @ indexUpperCheck @ TmpInfAddrLabel(errorLabel)::throwError
             ::TmpInfAddrLabel(doTheAccessLabel)::doTheAccess::[] in
      let resultTmpExpr = (match elemType with
                         INT -> TmpIntExpr (TmpIntArg (TmpLoc resultTmp))
                       | BOOL -> TmpBoolExpr (TmpBoolArg (TmpLoc resultTmp))
                       | Pointer _ -> TmpPtrExpr (TmpPtrArg (TmpLoc resultTmp))
                       | _ -> assert(false))
      in (resultTmpExpr, allInstrs)

let handleMemForInstr = function
      TmpInfAddrJump j -> TmpInfAddrJump j::[]
    | TmpInfAddrLabel lbl -> TmpInfAddrLabel lbl::[]
      

let handleMemForFunDef (fName, tmpParams, instrs) =
    TmpInfAddrFunDef(fName, tmpParams,
         List.flatten (List.map handleMemForInstr instrs))
      

let rec handleMemStuff (prog: tmpInfAddrGlobalDecl list) =
    match prog with
       [] -> []
     | TmpStructDef(structTypeName, fields)::rest ->
         let () = updateStructDefsMap structTypeName fields in handleMemStuff rest
     | TmpInfAddrFunDef(fName, tmpParams, instrs)::rest ->
         handleMemForFunDef(fName, tmpParams, instrs)::handleMemStuff rest