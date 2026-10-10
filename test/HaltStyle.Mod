MODULE HaltStyle; (* Expected to halt: CreateStyledScalar in a style it doesn't write *)

(* Run by `make test`, which requires a failed ASSERT with code
   Fyaml.AssertStyle (65). Reaching the end means the check failed. *)

IMPORT Fyaml, Out;

VAR d: Fyaml.Document; n: Fyaml.Node;

BEGIN
  d := Fyaml.NewDocument();
  n := d.CreateStyledScalar("x", Fyaml.StyleFolded);  (* must halt here *)
  Out.String("HaltStyle: did not halt"); Out.Ln
END HaltStyle.
