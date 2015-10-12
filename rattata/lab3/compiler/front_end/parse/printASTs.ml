open Datatypesv1
open PrintDatatypes
open Ast
open String

let identToString(i : ident) = i

let generalBinopToString(op : generalBinop) = 
  match op with
        IntBinop(i) -> intBinopToString(i)
      | DOUBLE_EQ -> " == "
      | GT -> " > "
      | LT -> " < "
      | LOG_AND -> " && "
      | _ -> assert(false)

let rec preElabExprToString(preelabexpr : preElabExpr) =
  match preelabexpr with
        PreElabConstExpr(c,t) -> constToString c
      | PreElabIdentExpr(i) -> identToString i
      | PreElabBinop(expr1, op, expr2) -> concat "" ["("; preElabExprToString expr1; " ";
                                                     generalBinopToString op; 
                                                     preElabExprToString expr2; ")"]
      | PreElabNot(expr1) -> concat "" ["!"; preElabExprToString(expr1)]
      | PreElabTernary(e1, e2, e3) -> "(" ^ (preElabExprToString e1) ^ " ? " ^
              (preElabExprToString e2) ^ " : " ^ (preElabExprToString e3) ^ ")"

let preElabDeclToString(preelabdecl : preElabDecl) =
  match preelabdecl with
        NewVar(i,t) -> c0typeToString(t) ^ identToString(i)
      | Init(i,t,p) -> concat "" [c0typeToString(t); identToString(i); " = "; preElabExprToString(p)]

let simpStmtToString(statement : simpStmt) =
  match statement with
        PreElabDecl(p) -> preElabDeclToString(p)
      | SimpAssign(i,p) -> concat "" [identToString(i); " = "; preElabExprToString(p)]
      | SimpStmtExpr(p) -> preElabExprToString(p)

let simpOptToString(sOpt : simpOpt) = 
  match sOpt with
        EmptySimp -> ""
      | HasSimpStmt(statement) -> simpStmtToString(statement)

let rec elseOptToString(eOpt : elseOpt) =
  match eOpt with
        EmptyElse -> ""
      | PreElabElse(p) -> preElabStmtToString(p)

and controlToString(c : control) = 
  match c with
        PreElabIf(pExpr,pStmt,eOpt) -> concat "" ["if("; preElabExprToString(pExpr); 
                                                  ") {\n\t"; preElabStmtToString(pStmt); 
                                                  "} \nelse {\n\t"; elseOptToString(eOpt); "\n}"]
      | PreElabWhile(pExpr,pStmt) -> concat "" ["while("; preElabExprToString(pExpr);
                                                ") {\n\t"; preElabStmtToString(pStmt); "\n}"]
      | PreElabFor(sOpt1,pExpr,sOpt2,pStmt) -> concat "" ["for("; simpOptToString(sOpt1); "; ";
                                                        preElabExprToString(pExpr); "; ";
                                                        simpOptToString(sOpt2); ") {\n\t";
                                                        preElabStmtToString(pStmt); "\n}"]
      | PreElabReturn(pExpr) -> "return " ^ preElabExprToString(pExpr)

and preElabStmtToString(pStmt : preElabStmt) = 
  match pStmt with
        SimpStmt(s) -> simpStmtToString(s)
      | Control(c) -> controlToString(c)
      | Block(b) -> blockToString(b)

and blockToString(blk : block) = concat "\n" (List.map preElabStmtToString blk) ^ "\n" 

let preElabASTToString(blk) = blockToString blk

(* ============ Untyped Post-Elab AST Print Functions ================= *)

let rec untypedPostElabExprToString(expression : untypedPostElabExpr) =
  match expression with
        UntypedPostElabConstExpr(c,t) -> constToString c
      | UntypedPostElabIdentExpr(i) -> identToString i
      | UntypedPostElabBinop(expr1, op, expr2) -> concat "" ["("; untypedPostElabExprToString expr1; " ";
                                                     generalBinopToString op; 
                                                     untypedPostElabExprToString expr2; ")"]
      | UntypedPostElabNot(expr1) -> concat "" ["!"; untypedPostElabExprToString(expr1)]
      | UntypedPostElabTernary(e1, e2, e3) -> "(" ^ (untypedPostElabExprToString e1) ^ " ? " ^
              (untypedPostElabExprToString e2) ^ " : " ^ (untypedPostElabExprToString e3) ^ ")"
      


let rec untypedPostElabStmtToString(s : untypedPostElabStmt) = 
  match s with
        UntypedPostElabDecl(identifier,constant) -> concat "" [c0typeToString(constant); identToString(identifier)]
      | UntypedPostElabAssignStmt(identifier,untypedexpr) -> concat "" [identToString(identifier); " = "; 
                                                                        untypedPostElabExprToString(untypedexpr)]
      | UntypedPostElabIf(expression,postelabast1,postelabast2) -> concat "" ["if("; untypedPostElabExprToString(expression); 
                                                  ") {\n\t"; untypedPostElabASTToString(postelabast1); 
                                                  "} \nelse {\n\t"; untypedPostElabASTToString(postelabast2); "\n}"]
      | UntypedPostElabWhile(expression,postelabast,init) -> concat "" ["while("; untypedPostElabExprToString(expression);
                                                ", "; untypedPostElabASTToString(init); ") {\n\t"; 
                                                      untypedPostElabASTToString(postelabast); "\n}"]
      | UntypedPostElabReturn(i) -> "return " ^ untypedPostElabExprToString(i)
      | UntypedPostElabBlock(blockAst) -> "\t" ^ untypedPostElabASTToString blockAst
                                          
and untypedPostElabASTToString(stmts : untypedPostElabAST) =
  concat "\n" (List.map untypedPostElabStmtToString stmts) ^ "\n"







(* ============ Typed Post-Elab AST Print Functions ================= *)

(*
let rec intExprToString(iExpr : intExpr) = 
  match iExpr with
        IntConst(c) -> constToString(c)
      | IntIdent(i) -> identToString(i)
      | ASTBinop(expr1, op, expr2) -> concat "" ["("; intExprToString(expr1); 
                                                      intBinopToString(op); 
                                                      intExprToString(expr2); 
                                                 ")"]

let rec boolExprToString(bExpr : boolExpr) =
  match bExpr with
        BoolConst(c) -> constToString(c)
      | BoolIdent(i) -> identToString(i)
      | GreaterThan(iExpr1,iExpr2) -> concat "" [intExprToString(iExpr1); " > "; intExprToString(iExpr2)]
      | IntEquals(iExpr1,iExpr2) -> concat "" [intExprToString(iExpr1); " == "; intExprToString(iExpr2)]
      | BoolEquals(bExpr1,bExpr2) -> concat "" [boolExprToString(bExpr1); " == "; boolExprToString(bExpr2)]
      | LogNot(bExpr) -> concat "" ["!"; boolExprToString bExpr]
      | LogAnd(bExpr1,bExpr2) -> concat "" [boolExprToString(bExpr1); " && "; boolExprToString(bExpr2)]

let exprToString(e : expr) = 
  match e with
        IntExpr(i) -> intExprToString(i)
      | BoolExpr(b) -> boolExprToString(b)

let assignStmtToString(i,e) = concat "" [identToString(i); " = "; exprToString(e)]

let rec stmtToString(s : stmt) = 
  match s with
        Decl(i,c) -> concat "" [c0typeToString(c); identToString(i)]
      | AssignStmt(a) -> assignStmtToString(a)
      | If(b,p1,p2) -> concat "" ["if("; boolExprToString(b); 
                                                  ") {\n\t"; postElabAstToString(p1); 
                                                  "} else {\n\t"; postElabAstToString(p2); "\n}"]
      | While(b,p) -> concat "" ["while("; boolExprToString(b);
                                                ") {\n\t"; postElabAstToString(p); "\n}"]
      | Return(i) -> "return " ^ intExprToString(i)

and postElabAstToString(stmts : stmt list) = concat "\n" (List.map stmtToString stmts) ^ "\n"
*)
