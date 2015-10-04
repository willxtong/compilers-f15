open Datatypesv1
open PrintDatatypes
open Ast
open String

let identToString(i : ident) = i

let rec preElabExprToString(preelabexpr : preElabExpr) =
  match preelabexpr with
        PreElabConstExpr(c,t) -> concat "" [c0typeToString t; " "; constToString c]
      | IdentExpr(i) -> identToString i
      | PreElabBinop(expr1, op, expr2) -> concat "" [preElabExprToString expr1; 
                                                     intBinopToString op; 
                                                     preElabExprToString expr2]
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
                                                  "} else {\n\t"; elseOptToString(eOpt); "\n}"]
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

(* ============ Post-Elab AST Print Functions ================= *)

let rec intExprToString(iExpr : intExpr) = 
  match iExpr with
        IntConst(c) -> constToString(c)
      | IntIdent(i) -> identToString(i)
      | ASTBinop(expr1, op, expr2) -> concat "" [intExprToString(expr1); intBinopToString(op); intExprToString(expr2)]
