module G = Graph
module H = Hashtbl
module L = List
module A = Array
module S = Set
open Datatypesv1

let listToString i a = String.concat "" (List.map (fun x -> string_of_int(i)^": " ^string_of_int(x) ^ ", ") a @["\n"])

let listArrayToString a = String.concat "" (Array.to_list(Array.mapi listToString a))

let isLive liveSet line = try let () = H.find liveSet line in true
                          with Not_found -> false

let isDef t prog line =
    match Array.get prog line with
         Tmp2AddrMov(src, dest) -> (dest = Tmp t)
       | Tmp2AddrBinop(op, src, dest) -> (dest = Tmp t)
       | _ -> false

let isUsed t prog line =
    match Array.get prog line with
         Tmp2AddrMov(src, dest) -> (src = TmpLoc (Tmp t))
       | Tmp2AddrBinop(op, src, dest) -> ((src = (TmpLoc (Tmp t)))
                                           || (dest = Tmp t))
       | Tmp2AddrReturn arg -> (arg = TmpLoc (Tmp t))
       | Tmp2AddrBoolInstr (TmpCmp (arg, loc)) ->
              ((arg = (TmpLoc (Tmp t))) || (loc = Tmp t))
       | Tmp2AddrBoolInstr (TmpTest (arg, loc)) ->
              ((arg = (TmpLoc (Tmp t))) || (loc = Tmp t))
       | _ -> false

let rec findLiveLinesRec t prog predsPerLine liveLinesSet succLine currLine =
    (* let () = (if t =2 then print_string("curr: " ^ string_of_int(currLine) *)
    (*                                     ^ " from " ^ string_of_int(succLine) ^"\n")) in *)
    if isDef t prog currLine then (let () = H.replace liveLinesSet succLine () in liveLinesSet) else
    try (let () = H.find liveLinesSet currLine in liveLinesSet)
        (* If we've already declared the var live here, we're done *)
    with Not_found -> let () = H.add liveLinesSet currLine () in
       (* Add it to liveLinesSet if it's live, otherwise do nothing. *)
         let () =
                (if (isLive liveLinesSet succLine && not (isDef t prog currLine))
                  || isUsed t prog currLine (* It's live on this line *)
                then H.replace liveLinesSet currLine ()) in
         let () = (if isDef t prog currLine
            (* if it's defined on this line it's always live on the next line,
               I think. This is to deal with temps that are assigned but
               never used *)
                   then H.replace liveLinesSet succLine ()) in
          (* Then make the recurisve calls in both cases *)
 let _ =
            List.map (findLiveLinesRec t prog predsPerLine
                              liveLinesSet currLine)
                 (Array.get predsPerLine currLine) in liveLinesSet

let addLineToList line () acc = line::acc

let findLiveLines t prog predsPerLine =
    let startLine = (Array.length prog) - 1 in
    let result = H.create 500 in
    (* let () = print_string(listArrayToString predsPerLine) in *)
    let liveLinesSet = findLiveLinesRec t prog predsPerLine
                       result startLine startLine in
    H.fold addLineToList liveLinesSet []
    (* let () = (if t=2 then print_string(listToString t r) ) in r *)


let rec findPredecessors (predecessorsArray : (int list) array)
      (progArray : tmp2AddrInstr array) (lineNum : int) =
  (* Note the -1 here to avoid index-out-of-range! *)
  if lineNum = (A.length progArray) - 1 then ()
  else (match A.get progArray lineNum with
              Tmp2AddrJump(j, l) -> 
                (let () = (match j with
                                JMP_UNCOND -> ()
                              | _ -> (A.set predecessorsArray (lineNum + 1) (lineNum ::
                                                                           (A.get predecessorsArray (lineNum + 1))))) in
                let () = (A.iteri
                            (fun index -> fun instr -> 
                              (match instr with
                                     Tmp2AddrLabel(l') -> 
                                        if l = l'
                                           (* why is this index + 1?? *)
                                        then predecessorsArray.(index) <- (lineNum :: predecessorsArray.(index)) 
                                        else ()
                                   | _ -> () )) progArray)
                in findPredecessors predecessorsArray progArray (lineNum + 1))
            | _ -> let () = (A.set predecessorsArray (lineNum + 1) (lineNum ::
                                                             (A.get predecessorsArray (lineNum + 1)))) in
                   findPredecessors predecessorsArray progArray (lineNum + 1))

let rec drawAllEdges (line : int list) interferenceGraph =
  match line with
        [] -> ()
      | temp :: line' -> (let () = L.iter (fun t -> G.addEdge interferenceGraph (temp, t)) line' in
                          drawAllEdges line' interferenceGraph)

let handleTemp t prog predsPerLine interferenceGraph liveTmpsPerLine =
    let () = G.initVertex interferenceGraph t in
    let liveLinesForT = findLiveLines t prog predsPerLine in
    let () = L.iter (fun line -> (A.set liveTmpsPerLine line (t::A.get liveTmpsPerLine line))) liveLinesForT
        in ()
    

let drawGraph (temps : int list) (prog : tmp2AddrInstr array) predsPerLine =
  let liveTmpsPerLine = A.make (A.length prog) [] in
  let interferenceGraph = G.emptyGraph() in
  let () = L.iter (fun t -> handleTemp t prog predsPerLine interferenceGraph liveTmpsPerLine) temps in
  (* let () = L.iter (fun t -> (let () = G.initVertex interferenceGraph t in *)
  (*                            let liveLines = findLiveLines t prog predsPerLine in *)
  (*                            L.iter (fun l -> (A.set liveTmpsPerLine l (t::liveTmpsPerLine.(l))) liveLines) temps in *)
  let () = A.iter (fun line -> drawAllEdges line interferenceGraph) liveTmpsPerLine in
  interferenceGraph

let analyzeLiveness (prog : tmp2AddrProg) temps =
  let progArray = A.of_list prog in
  let len = A.length progArray in
  let lineToPredecessorsArray = A.make len [] in
  let () = findPredecessors lineToPredecessorsArray progArray 0 in
  drawGraph temps progArray lineToPredecessorsArray
  
