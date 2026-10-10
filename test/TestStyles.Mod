MODULE TestStyles; (* CreateStyledScalar: every text reads back as itself *)

(* The installed libfyaml writes a CreateScalar's text plain even where
   plain YAML doesn't hold it (PLAN.md, "Scalar styles"). Each text
   below, made with CreateStyledScalar in each style it takes, is
   emitted in each mode, parsed again and compared byte for byte; the
   style chosen is checked for a few, and one document's exact output.
   The texts are the ones the probe found CreateScalar breaking, and
   others the escaping and the block's indentation and chomping must
   get right. The last check is a tripwire on the bug itself: when
   CreateScalar's "#x" reads back right, the bug is fixed upstream. *)

IMPORT Fyaml, Check, Out;

CONST
  MaxTexts = 80;

VAR
  texts: ARRAY MaxTexts, 128 OF CHAR;
  nTexts: INTEGER;

(* Adds a text, written with escapes: /n line feed, /t tab, /r carriage
   return, /e escape (1BX), /q double quote, /N NEL, /L LS, /P PS,
   /B BOM, /x the byte FF (not UTF-8), // a slash; any other / stays. *)
PROCEDURE T(spec: ARRAY OF CHAR);
  VAR i, o: INTEGER; c: CHAR;

  PROCEDURE Put(c: CHAR);
  BEGIN texts[nTexts, o] := c; INC(o)
  END Put;

BEGIN
  i := 0; o := 0;
  WHILE spec[i] # 0X DO
    c := spec[i];
    IF (c = "/") & (spec[i + 1] # 0X) THEN
      INC(i); c := spec[i];
      CASE c OF
        "n": Put(0AX) | "t": Put(09X) | "r": Put(0DX) | "e": Put(1BX) | "q": Put(22X)
      | "N": Put(0C2X); Put(85X)
      | "L": Put(0E2X); Put(80X); Put(0A8X)
      | "P": Put(0E2X); Put(80X); Put(0A9X)
      | "B": Put(0EFX); Put(0BBX); Put(0BFX)
      | "x": Put(0FFX)
      | "/": Put("/")
      ELSE Put("/"); Put(c)
      END
    ELSE Put(c)
    END;
    INC(i)
  END;
  texts[nTexts, o] := 0X; INC(nTexts)
END T;

PROCEDURE Texts;
BEGIN
  nTexts := 0;
  (* What CreateScalar broke (the probe) *)
  T("#x"); T(" x"); T("x "); T("- x"); T("-"); T("? x"); T("!x"); T("|x"); T(">x"); T("%x"); T("@x");
  T("`x"); T("'x"); T("/qx"); T("  leading"); T("# not a comment");
  (* What it got right, which must stay right *)
  T("Raine"); T("Mode 1: Hand-to-Hand"); T("a: b"); T("x:y"); T("a #b"); T("a#b"); T("1/2"); T("10+");
  T("-5"); T("+5"); T(".5"); T("5'9/q"); T("Minions/e"); T("true"); T("null"); T("Null"); T("~"); T("");
  T("[x"); T("{x"); T("a, b"); T("&x"); T("*x"); T("--- x"); T("..."); T("a  b"); T("x:");
 T("na/N/L/Pme/B");
  (* Escapes and control characters *)
  T("back//slash /q and quote"); T("tab/there"); T("tab/tthere"); T("cr/rhere"); T("esc/e");
  (* Lines, for the literal block *)
  T("one/ntwo/n"); T("one/ntwo"); T("one/ntwo/n/n"); T("/nleading empty line"); T("  indented/nfirst/n");
  T("/tfirst tab/n"); T("trailing  /nspaces  /n"); T("last line  "); T("/n/n"); T("/n"); T("a/n/n/nb")
END Texts;

(* Emits a document holding every text, as items of a sequence nested
   in a mapping in a sequence, in style, with flags; parses it back and
   checks each text. Reports each one that differs. *)
PROCEDURE RoundTrip(style, flags: INTEGER; label: ARRAY OF CHAR);
  VAR d, d2: Fyaml.Document; root, m, seq, k, v, r2: Fyaml.Node; err: Fyaml.Error; s, got: Fyaml.String;
    i: INTEGER; ok, all: BOOLEAN;
BEGIN
  d := Fyaml.NewDocument();
  root := d.CreateSequence(); d.SetRoot(root);
  m := d.CreateMapping(); root.Append(m);
  seq := d.CreateSequence();
  FOR i := 0 TO nTexts - 1 DO v := d.CreateStyledScalar(texts[i], style); seq.Append(v) END;
  k := d.CreateScalar("texts"); ok := m.AppendPair(k, seq, err);
  s := d.ToYAML(flags, err);
  all := ok & (s # NIL);
  IF all THEN
    d2 := Fyaml.ParseString(s^, err);
    all := d2 # NIL;
    IF all THEN
      r2 := d2.Root(); r2 := r2.ByPath("/0/texts");
      all := (r2 # NIL) & r2.IsSequence() & (r2.Length() = nTexts);
      IF all THEN
        FOR i := 0 TO nTexts - 1 DO
          v := r2.Item(i); got := v.Scalar();
          IF got^ # texts[i] THEN
            all := FALSE; Out.String("    text "); Out.Int(i, 0); Out.String(" differs: ["); Out.String(got^);
            Out.String("]"); Out.Ln
          END
        END
      END;
      d2.Close
    ELSE Out.String(s^)
    END
  END;
  d.Close;
  Check.Check(all, label)
END RoundTrip;

PROCEDURE Strings(VAR s: ARRAY OF CHAR; a: ARRAY OF CHAR);
  VAR i, j: INTEGER;
BEGIN
  i := 0; WHILE s[i] # 0X DO INC(i) END;
  j := 0; WHILE (a[j] # 0X) & (i < LEN(s) - 1) DO s[i] := a[j]; INC(i); INC(j) END;
  s[i] := 0X
END Strings;

PROCEDURE RoundTrips;
  VAR modes: ARRAY 5 OF INTEGER; names: ARRAY 5, 16 OF CHAR; styles: ARRAY 3 OF INTEGER;
    snames: ARRAY 3, 16 OF CHAR; i, j: INTEGER; label: ARRAY 80 OF CHAR;
BEGIN
  modes[0] := Fyaml.emitModeBlock; names[0] := "block";
  modes[1] := Fyaml.emitDefault; names[1] := "default";
  modes[2] := Fyaml.emitModeOriginal; names[2] := "original";
  modes[3] := Fyaml.emitModeFlow; names[3] := "flow";
  modes[4] := Fyaml.emitModeFlowOneline; names[4] := "flow one-line";
  styles[0] := Fyaml.StylePlain; snames[0] := "plain";
  styles[1] := Fyaml.StyleDoubleQuoted; snames[1] := "double-quoted";
  styles[2] := Fyaml.StyleLiteral; snames[2] := "literal";
  FOR j := 0 TO 2 DO
    FOR i := 0 TO 4 DO
      label := "every text, "; Strings(label, snames[j]); Strings(label, ", emitted ");
      Strings(label, names[i]); Strings(label, ", reads back as itself");
      RoundTrip(styles[j], modes[i], label)
    END
  END
END RoundTrips;

(* The style a text in a style comes back with, after a block emit. *)
PROCEDURE StyleOf(text: ARRAY OF CHAR; style: INTEGER): INTEGER;
  VAR d, d2: Fyaml.Document; m, v: Fyaml.Node; err: Fyaml.Error; s: Fyaml.String; ok: BOOLEAN; r: INTEGER;
BEGIN
  d := Fyaml.NewDocument(); m := d.CreateMapping(); d.SetRoot(m);
  ok := m.AppendPair(d.CreateScalar("k"), d.CreateStyledScalar(text, style), err);
  s := d.ToYAML(Fyaml.emitModeBlock, err);
  d2 := Fyaml.ParseString(s^, err); m := d2.Root(); v := m.Value("k");
  r := v.Style();
  d2.Close; d.Close;
  RETURN r
END StyleOf;

PROCEDURE Styles;
  VAR nl2: ARRAY 4 OF CHAR;
BEGIN
  Check.Check(StyleOf("Raine", Fyaml.StylePlain) = Fyaml.StylePlain, "plain: a plain word stays plain");
  Check.Check(StyleOf("-5", Fyaml.StylePlain) = Fyaml.StylePlain, "plain: -5 stays plain");
  Check.Check(StyleOf("#x", Fyaml.StylePlain) = Fyaml.StyleDoubleQuoted, "plain: #x is double-quoted");
  Check.Check(StyleOf("null", Fyaml.StylePlain) = Fyaml.StyleDoubleQuoted, "plain: null's spelling is double-quoted");
  Check.Check(StyleOf("", Fyaml.StylePlain) = Fyaml.StyleDoubleQuoted, "plain: empty text is double-quoted");
  Check.Check(StyleOf("Raine", Fyaml.StyleDoubleQuoted) = Fyaml.StyleDoubleQuoted, "double-quoted: always");
  T("two/nlines/n");
  Check.Check(StyleOf(texts[nTexts - 1], Fyaml.StyleLiteral) = Fyaml.StyleLiteral, "literal: lines are a literal block");
  nl2[0] := 0AX; nl2[1] := 0AX; nl2[2] := 0X;
  Check.Check(StyleOf(nl2, Fyaml.StyleLiteral) = Fyaml.StyleDoubleQuoted, "literal: only line feeds are double-quoted");
  T("bell/e/n");
  Check.Check(StyleOf(texts[nTexts - 1], Fyaml.StyleLiteral) = Fyaml.StyleDoubleQuoted,
              "literal: a control character is double-quoted")
END Styles;

(* One document's exact output, taken from libfyaml's (not written from
   expectation): what a reader of the file sees. *)
PROCEDURE Exact;
  VAR d: Fyaml.Document; m, v: Fyaml.Node; err: Fyaml.Error; s: Fyaml.String; ok: BOOLEAN;
    want: ARRAY 256 OF CHAR;
BEGIN
  d := Fyaml.NewDocument(); m := d.CreateMapping(); d.SetRoot(m);
  ok := m.AppendPair(d.CreateScalar("name"), d.CreateStyledScalar("Raine", Fyaml.StylePlain), err);
  ok := ok & m.AppendPair(d.CreateScalar("hobby"), d.CreateStyledScalar("#1 fan", Fyaml.StylePlain), err);
  T("Two lines,/n  the second indented./n");
  ok := ok & m.AppendPair(d.CreateScalar("text"), d.CreateStyledScalar(texts[nTexts - 1], Fyaml.StyleLiteral), err);
  s := d.ToYAML(Fyaml.emitModeBlock, err);
  T("name: Raine/nhobby: /q#1 fan/q/ntext: |/n  Two lines,/n    the second indented./n");
  COPY(texts[nTexts - 1], want);
  Check.Check(ok & (s # NIL) & (s^ = want), "the exact block output");
  IF (s # NIL) & (s^ # want) THEN Out.String(s^) END;
  d.Close
END Exact;

PROCEDURE Others;
  VAR d, d2: Fyaml.Document; m, v, orphan: Fyaml.Node; err: Fyaml.Error; s, got: Fyaml.String; ok: BOOLEAN;
    line, column: INTEGER; bad: ARRAY 4 OF CHAR;
BEGIN
  d := Fyaml.NewDocument(); m := d.CreateMapping(); d.SetRoot(m);
  v := d.CreateStyledScalar("x", Fyaml.StyleDoubleQuoted);
  Check.Check(~v.Location(line, column), "a styled scalar has no Location");
  orphan := d.CreateStyledScalar("never attached", Fyaml.StyleLiteral);  (* freed by Close *)
  ok := m.AppendPair(d.CreateScalar("k"), v, err);
  bad[0] := "a"; bad[1] := 0FFX; bad[2] := 0X;
  v := d.CreateStyledScalar(bad, Fyaml.StyleDoubleQuoted);
  got := v.Scalar();
  Check.Check(v.IsScalar() & (got^ = bad), "text that isn't UTF-8 falls back to CreateScalar, the same text");
  d.Close;

  (* The tripwire: libfyaml's bug, still there. *)
  d := Fyaml.NewDocument(); m := d.CreateMapping(); d.SetRoot(m);
  ok := m.AppendPair(d.CreateScalar("k"), d.CreateScalar("#x"), err);
  s := d.ToYAML(Fyaml.emitModeBlock, err);
  d2 := Fyaml.ParseString(s^, err); m := d2.Root(); v := m.Value("k");
  ok := (v # NIL) & v.IsScalar();
  IF ok THEN got := v.Scalar(); ok := got^ = "#x" END;
  Check.Check(~ok, "libfyaml still writes CreateScalar's #x plain (if this fails, see PLAN.md, Scalar styles)");
  d2.Close; d.Close
END Others;

BEGIN
  Texts;
  RoundTrips;
  Styles;
  Exact;
  Others;
  Check.Summary
END TestStyles.
