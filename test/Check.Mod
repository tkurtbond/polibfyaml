MODULE Check; (* Shared ok/FAIL reporting for the test programs *)

(* Each test program calls Check once per check and Summary at the
   very end of its body. Output, per check:
     ok   - <label>
     FAIL - <label>
   then "All checks passed." or "<N> check(s) failed."

   Summary exits with status 1 only when something failed; a passing
   run returns normally. Either way poc runs every pending GC finalizer
   as the program ends (GarbageCollectedHeap.FinalizeAll, from atexit),
   so valgrind's leak report is meaningful on both. (voc's
   Platform.Exit skips them, which is why olibfyaml returns normally.) *)

IMPORT Out, Platform;

VAR failed: LONGINT;

PROCEDURE Check*(ok: BOOLEAN; label: ARRAY OF CHAR);
BEGIN
  IF ok THEN Out.String("ok   - ") ELSE Out.String("FAIL - "); INC(failed) END;
  Out.String(label); Out.Ln
END Check;

PROCEDURE Summary*;
BEGIN
  IF failed = 0 THEN
    Out.String("All checks passed."); Out.Ln
  ELSE
    Out.Int(failed, 0); Out.String(" check(s) failed."); Out.Ln;
    Platform.Exit(1)
  END
END Summary;

BEGIN failed := 0
END Check.
