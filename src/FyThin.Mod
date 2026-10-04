MODULE FyThin; (* Thin libfyaml binding: direct calls, no ownership or error policy *)

(* Low-level access to libfyaml's core API. Handles are SYSTEM.ADDRESS
   values holding the C pointer; strings go in and out as an address
   plus an explicit length. Nothing here copies, frees, or checks:
   build the idiomatic API in Fyaml on top of this module rather than
   using it directly.

   Two kinds of declaration. A libfyaml or libc function that takes and
   returns only pointers, sizes and ints is declared here as an external
   ["C"] procedure, and wrapped in an exported Oberon procedure: poc 0.1.0
   does not keep an external procedure's linkage name in the .sym file, so
   an importer would call it by its Oberon name and fail to link
   (AGENTS.md, "poc 0.1.0 problems"). What an Oberon declaration cannot
   say is in FyThin.c beside this file, which poc compiles with clang
   against the installed <libfyaml.h> and links with the program:
   libfyaml's static inline helpers (fy_node_is_mapping and friends),
   struct fy_parse_cfg (built there), the fields of struct fy_diag_error
   and struct fy_mark (read there), the values of its enums and #defines,
   C's stdin and errno. So no C struct is mirrored as an Oberon record,
   and clang computes every layout from the header. Its functions are
   named "FyThin.-...", and give a truth value as an int32_t 0 or 1, which
   the procedures here turn into a BOOLEAN.

   A procedure with a VAR parameter hands C the parameter's address.

   Only the entry points Fyaml actually calls are bound here.

   Types: boundary signatures use explicit sizes -- SYSTEM.INT32 for C
   int and enums, SYSTEM.ADDRESS for pointers and size_t -- so each one
   states the C type it carries, and means the same under -O2 and -OC. *)

IMPORT SYSTEM;

TYPE
  Document* = SYSTEM.ADDRESS;  (* struct fy_document* *)
  Node* = SYSTEM.ADDRESS;      (* struct fy_node* *)
  NodePair* = SYSTEM.ADDRESS;  (* struct fy_node_pair* *)
  Diag* = SYSTEM.ADDRESS;      (* struct fy_diag* *)
  DiagError* = SYSTEM.ADDRESS; (* struct fy_diag_error* *)
  Parser* = SYSTEM.ADDRESS;    (* struct fy_parser* *)

(* ---- FyThin.c ---- *)

PROCEDURE ["C", "FyThin.-document-build-from-string"] CDocumentBuildFromString(str, len: SYSTEM.ADDRESS; resolve: SYSTEM.INT32; diag: Diag): Document;
PROCEDURE ["C", "FyThin.-document-build-from-file"] CDocumentBuildFromFile(file: SYSTEM.ADDRESS; resolve: SYSTEM.INT32; diag: Diag): Document;
PROCEDURE ["C", "FyThin.-document-build-from-stdin"] CDocumentBuildFromStdin(resolve: SYSTEM.INT32; diag: Diag): Document;
PROCEDURE ["C", "FyThin.-parser-create"] CParserCreate(resolve: SYSTEM.INT32; diag: Diag): Parser;
PROCEDURE ["C", "FyThin.-parser-set-input-stdin"] CParserSetInputStdin(fyp: Parser; name: SYSTEM.ADDRESS): SYSTEM.INT32;
PROCEDURE ["C", "FyThin.-diag-got-error"] CDiagGotError(diag: Diag): SYSTEM.INT32;
PROCEDURE ["C", "FyThin.-diag-set-collect-errors"] CDiagSetCollectErrors(diag: Diag; collect: SYSTEM.INT32);
PROCEDURE ["C", "FyThin.-node-is-scalar"] CNodeIsScalar(fyn: Node): SYSTEM.INT32;
PROCEDURE ["C", "FyThin.-node-is-sequence"] CNodeIsSequence(fyn: Node): SYSTEM.INT32;
PROCEDURE ["C", "FyThin.-node-is-mapping"] CNodeIsMapping(fyn: Node): SYSTEM.INT32;
PROCEDURE ["C", "FyThin.-node-is-alias"] CNodeIsAlias(fyn: Node): SYSTEM.INT32;
PROCEDURE ["C", "FyThin.-node-is-null"] CNodeIsNull(fyn: Node): SYSTEM.INT32;
PROCEDURE ["C", "FyThin.-node-is-attached"] CNodeIsAttached(fyn: Node): SYSTEM.INT32;
PROCEDURE ["C", "FyThin.-node-scalar-mark"] CNodeScalarMark(fyn: Node; linep, colp: SYSTEM.ADDRESS): SYSTEM.INT32;
PROCEDURE ["C", "FyThin.-style"] CStyle(which: SYSTEM.INT32): SYSTEM.INT32;
PROCEDURE ["C", "FyThin.-emitter-flag"] CEmitterFlag(which: SYSTEM.INT32): SYSTEM.INT32;

(* ---- libfyaml and libc, called directly ---- *)

PROCEDURE ["C", "fy_diag_create"] CDiagCreate(cfg: SYSTEM.ADDRESS): Diag;
PROCEDURE ["C", "fy_diag_errors_iterate"] CDiagErrorsIterate(diag: Diag; prevp: SYSTEM.ADDRESS): DiagError;
PROCEDURE ["C", "fy_node_get_tag"] CNodeGetTag(fyn: Node; lenp: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
PROCEDURE ["C", "fy_node_get_scalar"] CNodeGetScalar(fyn: Node; lenp: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
PROCEDURE ["C", "fy_node_sequence_iterate"] CNodeSequenceIterate(fyn: Node; prevp: SYSTEM.ADDRESS): Node;
PROCEDURE ["C", "fy_node_mapping_iterate"] CNodeMappingIterate(fyn: Node; prevp: SYSTEM.ADDRESS): NodePair;
PROCEDURE ["C", "fy_document_create"] CDocumentCreate(cfg: SYSTEM.ADDRESS): Document;
PROCEDURE ["C", "strtod"] CStrtod(p, endp: SYSTEM.ADDRESS): LONGREAL;

(* A BOOLEAN as FyThin.c's int32_t truth value. *)
PROCEDURE Truth(b: BOOLEAN): SYSTEM.INT32;
BEGIN IF b THEN RETURN 1 ELSE RETURN 0 END
END Truth;

(* ---- Documents ---- *)

(* Builds a document from len bytes at str. libfyaml does NOT copy the
   input: scalars of the returned document are spans into it, so the
   memory at str must stay valid and unchanged until DocumentDestroy.
   Never pass the address of a value ARRAY OF CHAR parameter -- poc
   copies those into the procedure's frame, which dies on return, and
   valgrind cannot see the resulting dangling spans (PLAN.md, "Buffer
   lifetime"). resolve sets FYPCF_RESOLVE_DOCUMENT (anchors, aliases,
   merge keys). Returns 0 on parse failure, with the errors collected
   in diag (see DiagCreate). *)
PROCEDURE DocumentBuildFromString*(str, len: SYSTEM.ADDRESS; resolve: BOOLEAN; diag: Diag): Document;
BEGIN RETURN CDocumentBuildFromString(str, len, Truth(resolve), diag)
END DocumentBuildFromString;

(* file: address of a 0X-terminated path. Returns 0 on failure. *)
PROCEDURE DocumentBuildFromFile*(file: SYSTEM.ADDRESS; resolve: BOOLEAN; diag: Diag): Document;
BEGIN RETURN CDocumentBuildFromFile(file, Truth(resolve), diag)
END DocumentBuildFromFile;

(* Reads C's stdin to its end (all of it, even past the first
   document: libfyaml reads a stream input in blocks, confirmed live)
   and builds its first document. libfyaml copies what it reads, so
   nothing needs to outlive the call; errors are labelled "<stream>".
   Returns 0 on failure. *)
PROCEDURE DocumentBuildFromStdin*(resolve: BOOLEAN; diag: Diag): Document;
BEGIN RETURN CDocumentBuildFromStdin(Truth(resolve), diag)
END DocumentBuildFromStdin;

PROCEDURE ["C", "fy_document_destroy"] CDocumentDestroy(fyd: Document);
PROCEDURE DocumentDestroy*(fyd: Document);
BEGIN CDocumentDestroy(fyd)
END DocumentDestroy;

(* ---- Streaming parser ---- *)

(* A parser for a stream of "---"-separated documents; 0 on failure. *)
PROCEDURE ParserCreate*(resolve: BOOLEAN; diag: Diag): Parser;
BEGIN RETURN CParserCreate(Truth(resolve), diag)
END ParserCreate;

(* Not copied (an fyit_memory input): the len bytes at str must stay
   valid until the parser AND every document loaded from it are
   destroyed. 0 on success. *)
PROCEDURE ["C", "fy_parser_set_string"] CParserSetString(fyp: Parser; str, len: SYSTEM.ADDRESS): SYSTEM.INT32;
PROCEDURE ParserSetString*(fyp: Parser; str, len: SYSTEM.ADDRESS): SYSTEM.INT32;
BEGIN RETURN CParserSetString(fyp, str, len)
END ParserSetString;

(* file: a 0X-terminated path that must stay valid while the parser
   is in use -- libfyaml opens the file lazily (alibfyaml found this
   as a use-after-free). Documents loaded from it don't need it
   (confirmed live under valgrind). 0 on success. *)
PROCEDURE ["C", "fy_parser_set_input_file"] CParserSetInputFile(fyp: Parser; file: SYSTEM.ADDRESS): SYSTEM.INT32;
PROCEDURE ParserSetInputFile*(fyp: Parser; file: SYSTEM.ADDRESS): SYSTEM.INT32;
BEGIN RETURN CParserSetInputFile(fyp, file)
END ParserSetInputFile;

(* Reads C's stdin. name: a 0X-terminated label for errors, which
   libfyaml keeps without copying (fy_parser_set_input_fp), so it
   must stay valid while the parser is in use. What libfyaml reads is
   copied into its own buffers; documents loaded from it don't need
   name (confirmed live under valgrind). 0 on success. *)
PROCEDURE ParserSetInputStdin*(fyp: Parser; name: SYSTEM.ADDRESS): SYSTEM.INT32;
BEGIN RETURN CParserSetInputStdin(fyp, name)
END ParserSetInputStdin;

(* The next document, or 0 at the end or on an error: DiagGotError
   tells them apart. After an error every later call returns 0 too;
   libfyaml can't resync to the documents after a malformed one
   (confirmed live; alibfyaml found even fy_parser_reset doesn't). *)
PROCEDURE ["C", "fy_parse_load_document"] CParseLoadDocument(fyp: Parser): Document;
PROCEDURE ParseLoadDocument*(fyp: Parser): Document;
BEGIN RETURN CParseLoadDocument(fyp)
END ParseLoadDocument;

PROCEDURE ["C", "fy_parser_destroy"] CParserDestroy(fyp: Parser);
PROCEDURE ParserDestroy*(fyp: Parser);
BEGIN CParserDestroy(fyp)
END ParserDestroy;

(* TRUE once an error was reported to diag; sticky. *)
PROCEDURE DiagGotError*(diag: Diag): BOOLEAN;
BEGIN RETURN CDiagGotError(diag) # 0
END DiagGotError;

(* ---- Resolving ---- *)

(* Resolves anchors, aliases and merge keys in place: an alias node
   becomes a copy of its target (fy_node_copy_to_scalar), and each
   merge-key pair is freed. 0 on success; errors go to the document's
   diag, e.g. "cyclic reference detected" (confirmed live). *)
PROCEDURE ["C", "fy_document_resolve"] CDocumentResolve(fyd: Document): SYSTEM.INT32;
PROCEDURE DocumentResolve*(fyd: Document): SYSTEM.INT32;
BEGIN RETURN CDocumentResolve(fyd)
END DocumentResolve;

(* Makes diag the document's diag; the document takes a reference, so
   DiagDestroy on it afterwards only silences it (fy_diag_destroy
   marks it destroyed and unrefs it). A parsed document keeps its
   parse diag the same way, already silenced. *)
PROCEDURE ["C", "fy_document_set_diag"] CDocumentSetDiag(fyd: Document; diag: Diag): SYSTEM.INT32;
PROCEDURE DocumentSetDiag*(fyd: Document; diag: Diag): SYSTEM.INT32;
BEGIN RETURN CDocumentSetDiag(fyd, diag)
END DocumentSetDiag;

(* 0 for an empty document. *)
PROCEDURE ["C", "fy_document_root"] CDocumentRoot(fyd: Document): Node;
PROCEDURE DocumentRoot*(fyd: Document): Node;
BEGIN RETURN CDocumentRoot(fyd)
END DocumentRoot;

(* ---- Diagnostics ---- *)

(* A diag with default config. Pass to a parse call, then destroy it
   exactly once with DiagDestroy. *)
PROCEDURE DiagCreate*(): Diag;
BEGIN RETURN CDiagCreate(0)
END DiagCreate;

PROCEDURE ["C", "fy_diag_destroy"] CDiagDestroy(diag: Diag);
PROCEDURE DiagDestroy*(diag: Diag);
BEGIN CDiagDestroy(diag)
END DiagDestroy;

(* With collect = TRUE, errors are kept for DiagErrorsIterate. *)
PROCEDURE DiagSetCollectErrors*(diag: Diag; collect: BOOLEAN);
BEGIN CDiagSetCollectErrors(diag, Truth(collect))
END DiagSetCollectErrors;

(* Iterates the collected errors: start with prev = 0; returns 0 when
   done. Each error lives as long as diag. *)
PROCEDURE DiagErrorsIterate*(diag: Diag; VAR prev: SYSTEM.ADDRESS): DiagError;
BEGIN RETURN CDiagErrorsIterate(diag, SYSTEM.ADR(prev))
END DiagErrorsIterate;

(* Fields of a collected error. Msg and File are 0X-terminated C
   strings, or 0. Line and Column are 1-based (alibfyaml confirmed
   this; fy_mark's are 0-based). *)
PROCEDURE ["C", "FyThin.-error-msg"] CErrorMsg(e: DiagError): SYSTEM.ADDRESS;
PROCEDURE ErrorMsg*(e: DiagError): SYSTEM.ADDRESS;
BEGIN RETURN CErrorMsg(e)
END ErrorMsg;
PROCEDURE ["C", "FyThin.-error-file"] CErrorFile(e: DiagError): SYSTEM.ADDRESS;
PROCEDURE ErrorFile*(e: DiagError): SYSTEM.ADDRESS;
BEGIN RETURN CErrorFile(e)
END ErrorFile;
PROCEDURE ["C", "FyThin.-error-line"] CErrorLine(e: DiagError): SYSTEM.INT32;
PROCEDURE ErrorLine*(e: DiagError): SYSTEM.INT32;
BEGIN RETURN CErrorLine(e)
END ErrorLine;
PROCEDURE ["C", "FyThin.-error-column"] CErrorColumn(e: DiagError): SYSTEM.INT32;
PROCEDURE ErrorColumn*(e: DiagError): SYSTEM.INT32;
BEGIN RETURN CErrorColumn(e)
END ErrorColumn;

(* ---- Node kinds ---- *)

(* fy_node_is_scalar/_sequence/_mapping are static inlines in the
   header, not exported symbols, so FyThin.c calls them. An alias node
   counts as a scalar (fy_node_is_alias further checks the style); with
   resolve on there are none. *)
PROCEDURE NodeIsScalar*(fyn: Node): BOOLEAN;
BEGIN RETURN CNodeIsScalar(fyn) # 0
END NodeIsScalar;

PROCEDURE NodeIsSequence*(fyn: Node): BOOLEAN;
BEGIN RETURN CNodeIsSequence(fyn) # 0
END NodeIsSequence;

PROCEDURE NodeIsMapping*(fyn: Node): BOOLEAN;
BEGIN RETURN CNodeIsMapping(fyn) # 0
END NodeIsMapping;

(* fy_node_is_alias is a static inline too; fy_node_is_null is
   exported. fy_node_is_null is TRUE for an empty plain scalar
   ("key:" with nothing after) but not for a quoted "" nor for the
   text "~"/"null" (confirmed live), and it reads an uninitialised
   field on an unresolved alias (slibfyaml, under valgrind), so ask
   NodeIsAlias first. *)
PROCEDURE NodeIsAlias*(fyn: Node): BOOLEAN;
BEGIN RETURN CNodeIsAlias(fyn) # 0
END NodeIsAlias;

PROCEDURE NodeIsNull*(fyn: Node): BOOLEAN;
BEGIN RETURN CNodeIsNull(fyn) # 0
END NodeIsNull;

(* Tags and styles *)

(* The explicit tag's text, verbatim ("!mytag"), not 0X-terminated;
   0 if the node has none (confirmed live). *)
PROCEDURE NodeGetTag*(fyn: Node; VAR len: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
BEGIN RETURN CNodeGetTag(fyn, SYSTEM.ADR(len))
END NodeGetTag;

(* One of the Style* values below (enum fy_node_style). *)
PROCEDURE ["C", "fy_node_get_style"] CNodeGetStyle(fyn: Node): SYSTEM.INT32;
PROCEDURE NodeGetStyle*(fyn: Node): SYSTEM.INT32;
BEGIN RETURN CNodeGetStyle(fyn)
END NodeGetStyle;

(* enum fy_node_style's values, read from the header by FyThin.c rather
   than retyped. *)
PROCEDURE StyleFlow*(): SYSTEM.INT32; BEGIN RETURN CStyle(0) END StyleFlow;
PROCEDURE StyleBlock*(): SYSTEM.INT32; BEGIN RETURN CStyle(1) END StyleBlock;
PROCEDURE StylePlain*(): SYSTEM.INT32; BEGIN RETURN CStyle(2) END StylePlain;
PROCEDURE StyleSingleQuoted*(): SYSTEM.INT32; BEGIN RETURN CStyle(3) END StyleSingleQuoted;
PROCEDURE StyleDoubleQuoted*(): SYSTEM.INT32; BEGIN RETURN CStyle(4) END StyleDoubleQuoted;
PROCEDURE StyleLiteral*(): SYSTEM.INT32; BEGIN RETURN CStyle(5) END StyleLiteral;
PROCEDURE StyleFolded*(): SYSTEM.INT32; BEGIN RETURN CStyle(6) END StyleFolded;
PROCEDURE StyleAlias*(): SYSTEM.INT32; BEGIN RETURN CStyle(7) END StyleAlias;

(* TRUE for a plain (unquoted, non-block) scalar. *)
PROCEDURE NodeIsPlain*(fyn: Node): BOOLEAN;
BEGIN RETURN NodeGetStyle(fyn) = StylePlain()
END NodeIsPlain;

(* The start of a scalar's token, 0-based (fy_mark's convention; the
   diag's are 1-based). Only scalars have one: a mapping or sequence
   has no scalar token. A scalar made by fy_node_create_scalar_copy
   reports 0, 0 (confirmed live), which can't be told from a parsed
   scalar at the start of the input. FALSE if fyn has no location (not
   a scalar, or no start mark). *)
PROCEDURE NodeScalarMark*(fyn: Node; VAR line, column: SYSTEM.INT32): BOOLEAN;
BEGIN RETURN CNodeScalarMark(fyn, SYSTEM.ADR(line), SYSTEM.ADR(column)) # 0
END NodeScalarMark;

(* ---- Scalars ---- *)

(* Returns the address of the scalar's bytes and stores their count in
   len. The bytes are NOT 0X-terminated and may contain 0X: copy
   exactly len bytes. Returns 0 if fyn is not a scalar. *)
PROCEDURE NodeGetScalar*(fyn: Node; VAR len: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
BEGIN RETURN CNodeGetScalar(fyn, SYSTEM.ADR(len))
END NodeGetScalar;

(* ---- Sequences ---- *)

PROCEDURE ["C", "fy_node_sequence_item_count"] CNodeSequenceItemCount(fyn: Node): SYSTEM.INT32;
PROCEDURE NodeSequenceItemCount*(fyn: Node): SYSTEM.INT32;
BEGIN RETURN CNodeSequenceItemCount(fyn)
END NodeSequenceItemCount;

(* 0-based; 0 if out of range. *)
PROCEDURE ["C", "fy_node_sequence_get_by_index"] CNodeSequenceGetByIndex(fyn: Node; index: SYSTEM.INT32): Node;
PROCEDURE NodeSequenceGetByIndex*(fyn: Node; index: SYSTEM.INT32): Node;
BEGIN RETURN CNodeSequenceGetByIndex(fyn, index)
END NodeSequenceGetByIndex;

(* Start with prev = 0; returns 0 when done. *)
PROCEDURE NodeSequenceIterate*(fyn: Node; VAR prev: SYSTEM.ADDRESS): Node;
BEGIN RETURN CNodeSequenceIterate(fyn, SYSTEM.ADR(prev))
END NodeSequenceIterate;

(* ---- Mappings ---- *)

PROCEDURE ["C", "fy_node_mapping_item_count"] CNodeMappingItemCount(fyn: Node): SYSTEM.INT32;
PROCEDURE NodeMappingItemCount*(fyn: Node): SYSTEM.INT32;
BEGIN RETURN CNodeMappingItemCount(fyn)
END NodeMappingItemCount;

(* key/len: the key's bytes and length, not kept after the call.
   Returns 0 if there is no such key. *)
PROCEDURE ["C", "fy_node_mapping_lookup_value_by_string"] CNodeMappingLookupValueByString(fyn: Node; key, len: SYSTEM.ADDRESS): Node;
PROCEDURE NodeMappingLookupValueByString*(fyn: Node; key, len: SYSTEM.ADDRESS): Node;
BEGIN RETURN CNodeMappingLookupValueByString(fyn, key, len)
END NodeMappingLookupValueByString;

(* Like NodeMappingLookupValueByString, but returns the key node. *)
PROCEDURE ["C", "fy_node_mapping_lookup_key_by_string"] CNodeMappingLookupKeyByString(fyn: Node; key, len: SYSTEM.ADDRESS): Node;
PROCEDURE NodeMappingLookupKeyByString*(fyn: Node; key, len: SYSTEM.ADDRESS): Node;
BEGIN RETURN CNodeMappingLookupKeyByString(fyn, key, len)
END NodeMappingLookupKeyByString;

(* Start with prev = 0; returns 0 when done. *)
PROCEDURE NodeMappingIterate*(fyn: Node; VAR prev: SYSTEM.ADDRESS): NodePair;
BEGIN RETURN CNodeMappingIterate(fyn, SYSTEM.ADR(prev))
END NodeMappingIterate;

PROCEDURE ["C", "fy_node_pair_key"] CNodePairKey(p: NodePair): Node;
PROCEDURE NodePairKey*(p: NodePair): Node;
BEGIN RETURN CNodePairKey(p)
END NodePairKey;
PROCEDURE ["C", "fy_node_pair_value"] CNodePairValue(p: NodePair): Node;
PROCEDURE NodePairValue*(p: NodePair): Node;
BEGIN RETURN CNodePairValue(p)
END NodePairValue;

(* ---- Paths ---- *)

(* path/len: the path's bytes and length, not kept after the call.
   Aliases are not followed (FYNWF_DONT_FOLLOW). Returns 0 if there is
   no such node. *)
PROCEDURE ["C", "FyThin.-node-by-path"] CNodeByPath(fyn: Node; path, len: SYSTEM.ADDRESS): Node;
PROCEDURE NodeByPath*(fyn: Node; path, len: SYSTEM.ADDRESS): Node;
BEGIN RETURN CNodeByPath(fyn, path, len)
END NodeByPath;

(* A malloc'd, 0X-terminated path: the caller frees it with Free.
   alibfyaml confirmed the root gives "/" (not NULL, as the header
   claims); 0 is still possible in principle. *)
PROCEDURE ["C", "fy_node_get_path"] CNodeGetPath(fyn: Node): SYSTEM.ADDRESS;
PROCEDURE NodeGetPath*(fyn: Node): SYSTEM.ADDRESS;
BEGIN RETURN CNodeGetPath(fyn)
END NodeGetPath;

(* ---- Building and mutating ---- *)

(* Frees an unattached node and, recursively, everything attached to
   it. Refuses (-1) an attached node. fy_document_destroy frees only
   the tree, so a node created and never attached must be freed this
   way or it leaks (confirmed live with valgrind). *)
PROCEDURE ["C", "fy_node_free"] CNodeFree(fyn: Node): SYSTEM.INT32;
PROCEDURE NodeFree*(fyn: Node): SYSTEM.INT32;
BEGIN RETURN CNodeFree(fyn)
END NodeFree;

(* An empty document (no root), default config. 0 on failure. *)
PROCEDURE DocumentCreate*(): Document;
BEGIN RETURN CDocumentCreate(0)
END DocumentCreate;

(* Makes fyn (unattached) the root. 0 on success, -1 if fyn is already
   attached. FREES THE PREVIOUS ROOT TREE, if any (fy-doc.c:
   fy_node_detach_and_free(fyd->root)). *)
PROCEDURE ["C", "fy_document_set_root"] CDocumentSetRoot(fyd: Document; fyn: Node): SYSTEM.INT32;
PROCEDURE DocumentSetRoot*(fyd: Document; fyn: Node): SYSTEM.INT32;
BEGIN RETURN CDocumentSetRoot(fyd, fyn)
END DocumentSetRoot;

(* Merges fyn into the node at path (fy_node_insert rules: a scalar,
   or a node of a different kind, replaces the target and FREES it; a
   mapping/sequence into the same kind merges, replacing and freeing
   the values of duplicate keys). Then frees fyn -- unconditionally,
   on success and failure (fy-doc.c calls fy_node_free(fyn), which
   refuses only if fyn is attached). 0 on success, -1 on failure,
   e.g. no node at path. *)
PROCEDURE ["C", "fy_document_insert_at"] CDocumentInsertAt(fyd: Document; path, len: SYSTEM.ADDRESS; fyn: Node): SYSTEM.INT32;
PROCEDURE DocumentInsertAt*(fyd: Document; path, len: SYSTEM.ADDRESS; fyn: Node): SYSTEM.INT32;
BEGIN RETURN CDocumentInsertAt(fyd, path, len, fyn)
END DocumentInsertAt;

(* A new unattached scalar holding a copy of size bytes at data. *)
PROCEDURE ["C", "fy_node_create_scalar_copy"] CNodeCreateScalarCopy(fyd: Document; data, size: SYSTEM.ADDRESS): Node;
PROCEDURE NodeCreateScalarCopy*(fyd: Document; data, size: SYSTEM.ADDRESS): Node;
BEGIN RETURN CNodeCreateScalarCopy(fyd, data, size)
END NodeCreateScalarCopy;

PROCEDURE ["C", "fy_node_create_sequence"] CNodeCreateSequence(fyd: Document): Node;
PROCEDURE NodeCreateSequence*(fyd: Document): Node;
BEGIN RETURN CNodeCreateSequence(fyd)
END NodeCreateSequence;
PROCEDURE ["C", "fy_node_create_mapping"] CNodeCreateMapping(fyd: Document): Node;
PROCEDURE NodeCreateMapping*(fyd: Document): Node;
BEGIN RETURN CNodeCreateMapping(fyd)
END NodeCreateMapping;

(* TRUE once fyn is part of a tree (root, item, key, or value). *)
PROCEDURE NodeIsAttached*(fyn: Node): BOOLEAN;
BEGIN RETURN CNodeIsAttached(fyn) # 0
END NodeIsAttached;

(* Attaches fyn (unattached, same document) at the end of seq. 0 on
   success; -1 if seq is not a sequence, fyn is attached, or from
   another document. Never frees fyn. *)
PROCEDURE ["C", "fy_node_sequence_append"] CNodeSequenceAppend(seq, fyn: Node): SYSTEM.INT32;
PROCEDURE NodeSequenceAppend*(seq, fyn: Node): SYSTEM.INT32;
BEGIN RETURN CNodeSequenceAppend(seq, fyn)
END NodeSequenceAppend;

(* Attaches key and value (unattached, same document) as a new last
   pair of map. 0 on success; -1 if map is not a mapping, either node
   is attached or from another document, or key duplicates an
   existing key (fy_node_mapping_pair_insert_prepare). Never frees
   them. *)
PROCEDURE ["C", "fy_node_mapping_append"] CNodeMappingAppend(map, key, value: Node): SYSTEM.INT32;
PROCEDURE NodeMappingAppend*(map, key, value: Node): SYSTEM.INT32;
BEGIN RETURN CNodeMappingAppend(map, key, value)
END NodeMappingAppend;

(* ---- Emitting ---- *)

(* A malloc'd, 0X-terminated emission of fyd (free it with Free), or 0
   on failure. flags: enum fy_emitter_cfg_flags, an int. *)
PROCEDURE ["C", "fy_emit_document_to_string"] CEmitDocumentToString(fyd: Document; flags: SYSTEM.INT32): SYSTEM.ADDRESS;
PROCEDURE EmitDocumentToString*(fyd: Document; flags: SYSTEM.INT32): SYSTEM.ADDRESS;
BEGIN RETURN CEmitDocumentToString(fyd, flags)
END EmitDocumentToString;

(* Writes fyd to the file named by file (0X-terminated), created or
   truncated. 0 on success, else the errno (e.g. from fopen), or -1
   for a failure that set none. *)
PROCEDURE ["C", "FyThin.-emit-document-to-file"] CEmitDocumentToFile(fyd: Document; flags: SYSTEM.INT32; file: SYSTEM.ADDRESS): SYSTEM.INT32;
PROCEDURE EmitDocumentToFile*(fyd: Document; flags: SYSTEM.INT32; file: SYSTEM.ADDRESS): SYSTEM.INT32;
BEGIN RETURN CEmitDocumentToFile(fyd, flags, file)
END EmitDocumentToFile;

(* enum fy_emitter_cfg_flags values, read from the header by FyThin.c
   rather than retyped. The mode values form a multi-bit field: combine
   at most one mode with FlagSortKeys. *)
PROCEDURE FlagDefault*(): SYSTEM.INT32; BEGIN RETURN CEmitterFlag(0) END FlagDefault;
PROCEDURE FlagSortKeys*(): SYSTEM.INT32; BEGIN RETURN CEmitterFlag(1) END FlagSortKeys;
PROCEDURE FlagModeOriginal*(): SYSTEM.INT32; BEGIN RETURN CEmitterFlag(2) END FlagModeOriginal;
PROCEDURE FlagModeBlock*(): SYSTEM.INT32; BEGIN RETURN CEmitterFlag(3) END FlagModeBlock;
PROCEDURE FlagModeFlow*(): SYSTEM.INT32; BEGIN RETURN CEmitterFlag(4) END FlagModeFlow;
PROCEDURE FlagModeFlowOneline*(): SYSTEM.INT32; BEGIN RETURN CEmitterFlag(5) END FlagModeFlowOneline;
PROCEDURE FlagModeJson*(): SYSTEM.INT32; BEGIN RETURN CEmitterFlag(6) END FlagModeJson;

(* ---- libc ---- *)

(* 0 if the file at path (0X-terminated) opens for reading, else the
   errno from fopen. libfyaml reports an unopenable file only on
   stderr ("[ERR]: failed to open ...") and collects nothing, so the
   caller checks first. A directory opens for reading, but libfyaml
   then prints "[ERR]: fy_parse_load_document() failed" and ParseFile
   gave a ParseError, while a stream found no documents and no error;
   so a directory gives EISDIR. It is found with fstat, not by reading:
   reading would lose input from a pipe given as a path (/dev/fd/N),
   which libfyaml opens again. *)
PROCEDURE ["C", "FyThin.-open-errno"] COpenErrno(path: SYSTEM.ADDRESS): SYSTEM.INT32;
PROCEDURE OpenErrno*(path: SYSTEM.ADDRESS): SYSTEM.INT32;
BEGIN RETURN COpenErrno(path)
END OpenErrno;

(* A static C string describing errno e. *)
PROCEDURE ["C", "strerror"] CStrerror(e: SYSTEM.INT32): SYSTEM.ADDRESS;
PROCEDURE Strerror*(e: SYSTEM.INT32): SYSTEM.ADDRESS;
BEGIN RETURN CStrerror(e)
END Strerror;

(* p: a 0X-terminated C string already checked against the float
   grammar. Correctly rounded (the C library's strtod); an overflow
   gives +-infinity. poc's programs never call setlocale, so "." is the
   decimal point. *)
PROCEDURE Strtod*(p: SYSTEM.ADDRESS): LONGREAL;
BEGIN RETURN CStrtod(p, 0)
END Strtod;

PROCEDURE ["C", "free"] CFree(p: SYSTEM.ADDRESS);
PROCEDURE Free*(p: SYSTEM.ADDRESS);
BEGIN CFree(p)
END Free;

PROCEDURE ["C", "strlen"] CStrlen(p: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
PROCEDURE Strlen*(p: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
BEGIN RETURN CStrlen(p)
END Strlen;

END FyThin.
