(* L2 Compiler
 * Parse State System
 * Authors: Ben Plaut, William Tong
 *
 * This tracks filename and newline characters
 * so character positions in lexer tokens
 * can be converted to line.column format for error messages
 *)

open Core.Std

let currFilename = ref ""
let currLines = ref ([] : int list)

let setfile filename =
  currFilename := filename;
  currLines := []

let newline pos =
  currLines := pos :: !currLines

(* look (pos, newline_positions, line_number) = (line, col)
 * pos is buffer position
 * newline_positions is (reverse) list of newline positions in file
 * line_number is lenght of newline_positions
 *)
let rec look = function
    (pos, a :: rest, n) ->
      (* a is end of line n *)
      if a < pos then (n + 1, pos - a)
      else look (pos, rest, n - 1)
  | (pos, [], n) ->
      (* first line pos is off by 1 *)
      (1, pos - 1)
