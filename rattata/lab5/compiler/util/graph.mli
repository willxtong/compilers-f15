(* Graph Library that will contain basic addEdge, etc, operations,
   as well as color and max-cardinality search. *)

type vertex = int
type neighbors
type graph

val emptyGraph: unit -> graph

(* Initializes an empty set of neighbors for a vertex if
   none exists, otherwise does nothing. *)
(* Note: this doesn't have to be called before addEdge, as
   addEdge calls this. *)
val initVertex: graph -> vertex -> unit

val addEdge: graph -> (vertex * vertex) -> unit

val hasEdge: graph -> (vertex * vertex) -> bool

val getNeighbors: graph -> vertex -> neighbors option
                                 
(* Given a graph (an interference graph) and a tie-breaking function
   for when priorities are equal,
   returns a simplicial elimination order of the
   vertices, in a list *)
val maxCardSearch: graph -> (vertex -> vertex -> int) -> vertex list
    
(* Takes an interference graph and an ordering of vertices,
   returns an mapping of each vertex to a color (an integer) *)
val greedilyColor: graph -> vertex list -> (vertex, int) Hashtbl.t
