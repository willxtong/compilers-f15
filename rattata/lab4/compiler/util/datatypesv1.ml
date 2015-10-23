(* ident and c0type have to be in here to avoid a circular build
   error :( *)
type c0type = INT | BOOL | VOID | TypedefType of ident | Pointer of c0type | Array of c0type | Struct of ident 
and ident = string
(* everything in c0 is an int! *)              
type const = int

type reg = EAX | EBX | ECX | EDX | RBP | RSP | ESI | EDI | R8 | R9 | R10 | R11 | R12 | R13 | R14 | R15

(* the int is the memory offest from the register *)
type memAddr = reg * int

(* These are for actual assembly instructions. Tmps are not allowed. *)
type intBinop = ADD | MUL | SUB | FAKEDIV | FAKEMOD
              | BIT_AND | BIT_OR | BIT_XOR
              | RSHIFT | LSHIFT              
type assemLoc = Reg of reg | MemAddr of memAddr
type assemArg = AssemLoc of assemLoc | Const of const
type boolInstr = TEST of assemArg * assemLoc
               | CMP of assemArg * assemLoc
type assemIntInstr = intBinop * assemArg * assemLoc
type jump = JNE | JE | JG | JLE | JL | JGE | JMP_UNCOND 
type label = int
type jumpInstr = jump * label
type assemInstr = MOV of assemArg * assemLoc
                | MOVQ of assemArg * assemLoc
                | SUBQ of assemArg * assemLoc
                | ADDQ of assemArg * assemLoc
                | INT_BINOP of assemIntInstr
                | PUSH of reg
                | POP of reg
                | RETURN
                | JUMP of jumpInstr
                | BOOL_INSTR of boolInstr
                | LABEL of label
                | CALL of ident
type assemFunDef = AssemFunDef of ident * assemInstr list
type assemProg = assemFunDef list

(* Assembly Code with wonky instructions (i.e. idiv, etc) *)
(* This comes after 2Addr in the pipeline, but needs to be below
   here so that they can refer to 2AddrInstrs (since this is a
   strict superset of normal 2Addr *)
type assemInstrWonky = AssemInstr of assemInstr
                   | CDQ (* needed for idiv *)
                   | IDIV of assemArg
type wonkyFunDef = WonkyFunDef of ident * assemInstrWonky list
type assemProgWonky = wonkyFunDef list

(* Below here allows tmps, but also allows actual assembly instructions.
   Note: Because we allow actual assembly instructions, memory
   addresses are allowed. Memory addresses should not occur prior
   to register allocation, at least not in L1 (unless I'm missing
   something) *)
type tmp = Tmp of int
type tmpArg = TmpLoc of tmp | TmpConst of const
(* Two Address Code *)
type tmpBoolInstr = TmpTest of tmpArg * tmp
                  | TmpCmp of tmpArg * tmp
type tmp2AddrBinop = intBinop * tmpArg * tmp
type tmp2AddrInstr = Tmp2AddrMov of tmpArg * tmp
                   | Tmp2AddrBinop of tmp2AddrBinop
                   | Tmp2AddrReturn of tmpArg
                   | Tmp2AddrJump of jumpInstr
                   | Tmp2AddrBoolInstr of tmpBoolInstr
                   | Tmp2AddrLabel of label
                    (* tmp option because voids have no dest *)
                   | Tmp2AddrFunCall of ident * tmpArg list * tmp option
type tmp2AddrFunDef = Tmp2AddrFunDef of ident * tmp list *
                                        tmp2AddrInstr list
type tmp2AddrProg = tmp2AddrFunDef list

(* Three Address Code *)
type tmp3AddrBinop = intBinop * tmpArg * tmpArg *  tmp
type tmp3AddrInstr = Tmp3AddrMov of tmpArg *  tmp
                   | Tmp3AddrBinop of tmp3AddrBinop
                   | Tmp3AddrReturn of tmpArg
                   | Tmp3AddrJump of jumpInstr
                   | Tmp3AddrBoolInstr of tmpBoolInstr
                   | Tmp3AddrLabel of label
                  (* function name, arg list, dest. Dest is an
                  option because void function don't need to move
                  the result anywhere *)
                   | Tmp3AddrFunCall of ident * tmpArg list * tmp option
type tmp3AddrFunDef = Tmp3AddrFunDef of ident * tmp list *
                                        tmp3AddrInstr list
type tmp3AddrProg = tmp3AddrFunDef list
    
(* Inf Address Code: any number of operands on right hand side *)
type tmpIntExpr = TmpIntArg of tmpArg
                | TmpInfAddrBinopExpr of intBinop *
                                         tmpIntExpr * 
                                         tmpIntExpr
                | TmpInfAddrIntFunCall of ident * tmpExpr list
and tmpBoolExpr = TmpBoolArg of tmpArg
                | TmpInfAddrBoolFunCall of ident * tmpExpr list
and tmpExpr = TmpBoolExpr of tmpBoolExpr
             | TmpIntExpr of tmpIntExpr
and tmpInfAddrBoolInstr = TmpInfAddrTest of tmpBoolExpr * tmpBoolExpr
                        | TmpInfAddrCmp of tmpIntExpr * tmpIntExpr
type tmpInfAddrInstr = TmpInfAddrMov of tmpExpr * tmp
                   | TmpInfAddrJump of jumpInstr
                   | TmpInfAddrBoolInstr of tmpInfAddrBoolInstr
                   | TmpInfAddrLabel of label
                   | TmpInfAddrReturn of tmpExpr
                   | TmpInfAddrVoidFunCall of ident * tmpExpr list
type tmpInfAddrFunDef = TmpInfAddrFunDef of ident * tmp list
                                   * tmpInfAddrInstr list
                         (* function name, param names,
                            instruction list *)
type tmpInfAddrProg = tmpInfAddrFunDef list