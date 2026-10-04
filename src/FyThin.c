/* FyThin.c - the part of FyThin.Mod written in C.

   poc compiles a module's sibling .c with clang whenever it compiles the
   module, and links its object with the program (AGENTS.md, "Build").
   Everything here is a call FyThin.Mod cannot declare as a plain ["C"]
   external procedure:

   - libfyaml's static inline helpers (fy_node_is_mapping and friends),
     which are in the header and not in the library;
   - struct fy_parse_cfg, built here, and struct fy_diag_error's and
     struct fy_mark's fields, read here, so clang computes every layout
     from the installed header rather than FyThin.Mod mirroring it;
   - the values of enums and #defines (FYNS_*, FYECF_*, FYNWF_*);
   - C's stdin, errno, strerror and stat.

   The interface is in fixed-width types only, so that it means the same
   under both of poc's size models: int32_t for a C int or a truth value
   (0 or 1; poc's BOOLEAN is not given to C), intptr_t for a pointer or a
   size_t (SYSTEM.ADDRESS on the Oberon side).

   The names start with "FyThin.-": "-" cannot be in an Oberon name, so no
   module's procedure or variable can be called the same (poc's own runtime
   names its C parts' symbols the same way). */

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <libfyaml.h>

#define NAME(n) __asm__("FyThin.-" n)

typedef intptr_t address;

static struct fy_parse_cfg parse_config(int32_t resolve, address diag)
{
	struct fy_parse_cfg cfg;

	memset(&cfg, 0, sizeof cfg);
	cfg.flags = resolve ? FYPCF_RESOLVE_DOCUMENT : 0;
	cfg.diag = (struct fy_diag *)diag;
	return cfg;
}

/* ---- Documents ---- */

address document_build_from_string(address str, address len, int32_t resolve, address diag)
	NAME("document-build-from-string");
address document_build_from_string(address str, address len, int32_t resolve, address diag)
{
	struct fy_parse_cfg cfg = parse_config(resolve, diag);

	return (address)fy_document_build_from_string(&cfg, (const char *)str, (size_t)len);
}

address document_build_from_file(address file, int32_t resolve, address diag)
	NAME("document-build-from-file");
address document_build_from_file(address file, int32_t resolve, address diag)
{
	struct fy_parse_cfg cfg = parse_config(resolve, diag);

	return (address)fy_document_build_from_file(&cfg, (const char *)file);
}

address document_build_from_stdin(int32_t resolve, address diag)
	NAME("document-build-from-stdin");
address document_build_from_stdin(int32_t resolve, address diag)
{
	struct fy_parse_cfg cfg = parse_config(resolve, diag);

	return (address)fy_document_build_from_fp(&cfg, stdin);
}

/* ---- Streaming parser ---- */

/* fy_parser_create copies the config (fy_parse_setup: fyp->cfg = *cfg),
   so a local one is enough. */
address parser_create(int32_t resolve, address diag) NAME("parser-create");
address parser_create(int32_t resolve, address diag)
{
	struct fy_parse_cfg cfg = parse_config(resolve, diag);

	return (address)fy_parser_create(&cfg);
}

int32_t parser_set_input_stdin(address fyp, address name) NAME("parser-set-input-stdin");
int32_t parser_set_input_stdin(address fyp, address name)
{
	return fy_parser_set_input_fp((struct fy_parser *)fyp, (const char *)name, stdin);
}

int32_t diag_got_error(address diag) NAME("diag-got-error");
int32_t diag_got_error(address diag)
{
	return fy_diag_got_error((struct fy_diag *)diag) ? 1 : 0;
}

void diag_set_collect_errors(address diag, int32_t collect) NAME("diag-set-collect-errors");
void diag_set_collect_errors(address diag, int32_t collect)
{
	fy_diag_set_collect_errors((struct fy_diag *)diag, collect != 0);
}

/* ---- Fields of a collected error ---- */

address error_msg(address e) NAME("error-msg");
address error_msg(address e)
{
	return (address)((struct fy_diag_error *)e)->msg;
}

address error_file(address e) NAME("error-file");
address error_file(address e)
{
	return (address)((struct fy_diag_error *)e)->file;
}

int32_t error_line(address e) NAME("error-line");
int32_t error_line(address e)
{
	return ((struct fy_diag_error *)e)->line;
}

int32_t error_column(address e) NAME("error-column");
int32_t error_column(address e)
{
	return ((struct fy_diag_error *)e)->column;
}

/* ---- Node kinds: static inlines in the header ---- */

int32_t node_is_scalar(address fyn) NAME("node-is-scalar");
int32_t node_is_scalar(address fyn)
{
	return fy_node_is_scalar((struct fy_node *)fyn) ? 1 : 0;
}

int32_t node_is_sequence(address fyn) NAME("node-is-sequence");
int32_t node_is_sequence(address fyn)
{
	return fy_node_is_sequence((struct fy_node *)fyn) ? 1 : 0;
}

int32_t node_is_mapping(address fyn) NAME("node-is-mapping");
int32_t node_is_mapping(address fyn)
{
	return fy_node_is_mapping((struct fy_node *)fyn) ? 1 : 0;
}

int32_t node_is_alias(address fyn) NAME("node-is-alias");
int32_t node_is_alias(address fyn)
{
	return fy_node_is_alias((struct fy_node *)fyn) ? 1 : 0;
}

int32_t node_is_null(address fyn) NAME("node-is-null");
int32_t node_is_null(address fyn)
{
	return fy_node_is_null((struct fy_node *)fyn) ? 1 : 0;
}

int32_t node_is_attached(address fyn) NAME("node-is-attached");
int32_t node_is_attached(address fyn)
{
	return fy_node_is_attached((struct fy_node *)fyn) ? 1 : 0;
}

/* The start of a scalar's token, 0-based; 0 if it has none. */
int32_t node_scalar_mark(address fyn, address linep, address colp) NAME("node-scalar-mark");
int32_t node_scalar_mark(address fyn, address linep, address colp)
{
	struct fy_token *t = fy_node_get_scalar_token((struct fy_node *)fyn);
	const struct fy_mark *m = t ? fy_token_start_mark(t) : NULL;

	if (m == NULL)
		return 0;
	*(int32_t *)linep = m->line;
	*(int32_t *)colp = m->column;
	return 1;
}

/* ---- Paths ---- */

address node_by_path(address fyn, address path, address len) NAME("node-by-path");
address node_by_path(address fyn, address path, address len)
{
	return (address)fy_node_by_path((struct fy_node *)fyn, (const char *)path,
	    (size_t)len, FYNWF_DONT_FOLLOW);
}

/* ---- Emitting ---- */

/* 0 on success, else the errno (e.g. from fopen), or -1 for a failure
   that set none. */
int32_t emit_document_to_file(address fyd, int32_t flags, address file)
	NAME("emit-document-to-file");
int32_t emit_document_to_file(address fyd, int32_t flags, address file)
{
	int r;

	errno = 0;
	r = fy_emit_document_to_file((struct fy_document *)fyd,
	    (enum fy_emitter_cfg_flags)flags, (const char *)file);
	return r == 0 ? 0 : (errno ? errno : -1);
}

/* ---- Constants from the header ---- */

int32_t style(int32_t which) NAME("style");
int32_t style(int32_t which)
{
	switch (which) {
	case 0: return FYNS_FLOW;
	case 1: return FYNS_BLOCK;
	case 2: return FYNS_PLAIN;
	case 3: return FYNS_SINGLE_QUOTED;
	case 4: return FYNS_DOUBLE_QUOTED;
	case 5: return FYNS_LITERAL;
	case 6: return FYNS_FOLDED;
	default: return FYNS_ALIAS;
	}
}

int32_t emitter_flag(int32_t which) NAME("emitter-flag");
int32_t emitter_flag(int32_t which)
{
	switch (which) {
	case 0: return FYECF_DEFAULT;
	case 1: return FYECF_SORT_KEYS;
	case 2: return FYECF_MODE_ORIGINAL;
	case 3: return FYECF_MODE_BLOCK;
	case 4: return FYECF_MODE_FLOW;
	case 5: return FYECF_MODE_FLOW_ONELINE;
	default: return FYECF_MODE_JSON;
	}
}

/* ---- libc ---- */

/* 0 if the file at path opens for reading and is not a directory, else
   the errno from fopen, or EISDIR. See FyThin.OpenErrno. */
int32_t open_errno(address path) NAME("open-errno");
int32_t open_errno(address path)
{
	FILE *f = fopen((const char *)path, "r");
	int e = f ? 0 : errno;
	struct stat st;

	if (f) {
		if (fstat(fileno(f), &st) == 0 && S_ISDIR(st.st_mode))
			e = EISDIR;
		fclose(f);
	}
	return e;
}
