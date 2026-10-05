# polibfyaml -- Oberon-2 binding to libfyaml for poc, the Peaseblossom
# Oberon Compiler.  See AGENTS.md.
#
# poc builds a program from its main module's source, finding the modules
# it imports on the import path (src/, plus test/ or bench/), and compiles
# every one of them again on each build; src/FyThin.c, beside FyThin.Mod,
# is compiled and linked with them as FyThin's part in C. What it writes -
# each module's .sym, .ll and .o, and the programs - goes into $(BUILD).
#
# Every program writes the library modules' files into the same $(BUILD),
# so make must not build two at once.
#
# make install builds the poc library polibfyaml (FyThin.c's object
# included) under -OC, the only size model the binding supports, in
# $(POC_OBERON_LIBRARIES)/polibfyaml (poc puts it in <triple>/OC/ there),
# where other repos' poc makefiles find it with -library-path. A program
# using it still needs libfyaml's flags, as $(LINK) below: the library
# doesn't record them.

POC      ?= poc
# The size model: decided in PLAN.md; never mix models.
POCFLAGS := -OC
VALGRIND ?= valgrind --leak-check=full --show-leak-kinds=all --error-exitcode=99 --suppressions=poc-gc.supp --suppressions=libfyaml.supp

# libfyaml's header and library: clang compiles FyThin.c with the -I flags,
# and links with the -L/-l ones.
FYAML_CFLAGS := $(shell pkg-config --cflags libfyaml)
FYAML_LIBS   := $(shell pkg-config --libs libfyaml)
LINK := $(foreach f,$(FYAML_CFLAGS),-c-flag $(f)) $(foreach f,$(FYAML_LIBS),-link $(f))

BUILD := build

# Each library in its own directory under POC_OBERON_LIBRARIES, so a
# program names only the libraries it uses.
POC_OBERON_LIBRARIES ?= /usr/local/sw/versions/oberon/poc/lib
LIBRARY := polibfyaml
LIBDIR = $(POC_OBERON_LIBRARIES)/$(LIBRARY)
LIBMODS := FyThin Fyaml FyamlStreams
TRIPLE = $(shell $(POC) -version | sed -n 's/^target \([^ ]*\).*/\1/p')

LIBSRC := src/FyThin.Mod src/FyThin.c src/Fyaml.Mod src/FyamlStreams.Mod
# Test programs (test/<name>.Mod, each a main module).
TESTS := TestThin TestParseErrors TestQuickstart TestNavigate TestPath TestLiveness TestBuild TestMutate TestScalars TestAnchors TestLocation TestStreams TestStdin TestStdinError TestStdinStream
# Programs that must halt (test/<name>.Mod), as name:Assert-code. poc's
# ASSERT(x, n) prints "assertion failed (n)" on standard error and exits
# with status 10, so `make test` requires both.
HALTTESTS := HaltClosed:61 HaltKind:62 HaltIndex:63 HaltStale:61 HaltAttach:64 HaltAttached:64 HaltTyped:62 HaltResolved:61 HaltStream:61
ASSERTSTATUS := 10

# Example programs (examples/<name>.Mod), as name:required-exit-status.
# `make test` runs each from examples/ and requires that status and
# stdout identical to examples/<name>.expected. The Example*Error ones
# report a deliberate error in their fixture, so exit 1.
EXAMPLES := ExampleConfig:0 ExampleSyntaxError:1 ExampleValueError:1 ExampleMissingField:1

TESTBINS := $(TESTS:%=$(BUILD)/%)
HALTBINS := $(foreach h,$(HALTTESTS),$(BUILD)/$(firstword $(subst :, ,$(h))))
EXAMPLEBINS := $(foreach e,$(EXAMPLES),$(BUILD)/$(firstword $(subst :, ,$(e))))

# Benchmarks (bench/), built by `make bench`, not by `all`.
BENCHES := BenchWide BenchStreams
BENCHBINS := $(BENCHES:%=$(BUILD)/%)
# Generated inputs, the same sizes as alibfyaml's; large, so in build/.
WIDE := $(BUILD)/wide.yaml
MANYDOCS := $(BUILD)/manydocs.yaml
RUNS ?= 10

.PHONY: all tests test valgrind bench clean install uninstall
.NOTPARALLEL:

all: tests

tests: $(TESTBINS) $(HALTBINS) $(EXAMPLEBINS)

$(BUILD):
	mkdir -p $@

$(BUILD)/Test%: test/Test%.Mod test/Check.Mod $(LIBSRC) | $(BUILD)
	$(POC) $(POCFLAGS) -import-path src -import-path test -output-dir $(BUILD) $(LINK) -o $@ $<

$(BUILD)/Halt%: test/Halt%.Mod $(LIBSRC) | $(BUILD)
	$(POC) $(POCFLAGS) -import-path src -output-dir $(BUILD) $(LINK) -o $@ $<

$(BUILD)/Example%: examples/Example%.Mod $(LIBSRC) | $(BUILD)
	$(POC) $(POCFLAGS) -import-path src -output-dir $(BUILD) $(LINK) -o $@ $<

$(BUILD)/Bench%: bench/Bench%.Mod bench/Timing.Mod $(LIBSRC) | $(BUILD)
	$(POC) $(POCFLAGS) -import-path src -import-path bench -output-dir $(BUILD) $(LINK) -o $@ $<

$(WIDE): bench/gen_wide.py | $(BUILD)
	python3 bench/gen_wide.py 200000 $@

$(MANYDOCS): bench/gen_manydocs.py | $(BUILD)
	python3 bench/gen_manydocs.py 20000 $@

# Each benchmark $(RUNS) times: n/mean/min/max/stddev of elapsed_seconds.
bench: $(BENCHBINS) $(WIDE) $(MANYDOCS)
	@$(BUILD)/BenchWide $(WIDE) | grep -v elapsed
	@$(BUILD)/BenchStreams $(MANYDOCS) | grep -v elapsed
	@for p in typed nav thin parse; do \
	  printf 'BenchWide %-6s ' $$p; bench/run_stats.sh $(RUNS) $(BUILD)/BenchWide $(WIDE) $$p; \
	done
	@printf 'BenchStreams       '; bench/run_stats.sh $(RUNS) $(BUILD)/BenchStreams $(MANYDOCS)
	@printf 'BenchStreams gc    '; bench/run_stats.sh $(RUNS) $(BUILD)/BenchStreams $(MANYDOCS) gc

# Shell function, called from within test/: a test's stdin --
# <name>.stdin if there is one (TestStdin and friends), else /dev/null.
STDIN := stdin() { if [ -f $$1.stdin ]; then echo $$1.stdin; else echo /dev/null; fi; }

# Run every test from test/ (fixtures are relative to it); report all,
# fail at the end if any failed. Each halt test must exit with poc's
# ASSERT status and name its Assert code on standard error.
test: tests
	@$(STDIN); status=0; for t in $(TESTS); do \
	  echo "== $$t"; (cd test && ../$(BUILD)/$$t < $$(stdin $$t)) || status=1; \
	done; \
	for h in $(HALTTESTS); do \
	  t=$${h%%:*}; code=$${h##*:}; echo "== $$t (must fail ASSERT code $$code)"; \
	  (cd test && ../$(BUILD)/$$t) 2> $(BUILD)/$$t.err; got=$$?; \
	  if [ $$got -eq $(ASSERTSTATUS) ] && grep -q "assertion failed ($$code)" $(BUILD)/$$t.err; then \
	    echo "ok   - $$t: $$(cat $(BUILD)/$$t.err)"; \
	  else echo "FAIL - $$t exited with $$got: $$(cat $(BUILD)/$$t.err)"; status=1; fi; \
	done; \
	for x in $(EXAMPLES); do \
	  e=$${x%%:*}; want=$${x##*:}; \
	  echo "== $$e (must exit $$want with examples/$$e.expected)"; \
	  (cd examples && ../$(BUILD)/$$e) > $(BUILD)/$$e.out; got=$$?; \
	  if [ $$got -eq $$want ] && cmp -s $(BUILD)/$$e.out examples/$$e.expected; then echo "ok   - $$e"; \
	  else echo "FAIL - $$e: exit $$got, output:"; diff examples/$$e.expected $(BUILD)/$$e.out; status=1; fi; \
	done; exit $$status

# Besides definite/indirect leaks, every still-reachable block must be
# the collector's own (its heap chunks and tables): leaked libfyaml memory
# whose address is still held in the Oberon heap (e.g. unfreed orphan
# nodes) shows up only as still-reachable blocks that libfyaml allocated.
# test/vg-reachable.sh checks that.
valgrind: tests
	@$(STDIN); status=0; for t in $(TESTS); do \
	  echo "== valgrind $$t"; \
	  (cd test && $(VALGRIND) --log-file=../$(BUILD)/$$t.vg ../$(BUILD)/$$t < $$(stdin $$t)) || status=1; \
	  grep -E 'ERROR SUMMARY|lost:|reachable:' $(BUILD)/$$t.vg; \
	  test/vg-reachable.sh $(BUILD)/$$t.vg || { echo "FAIL - $$t: still-reachable memory the collector did not allocate"; status=1; }; \
	done; exit $$status

# Install only a library that compiles: every test program imports it.
# Built in $(BUILD)/lib/, then copied with poc -install-library, which
# copies only what a program needs: the archive (FyThin.c's object is in
# it), the shared object, the manifest, and each module's .sym and
# .owner (not the .o, .ll and FyThin.c.o that -library also writes). A
# library records the poc that built it, and another poc refuses it:
# install again after upgrading poc.
install: tests
	cd src && $(POC) $(POCFLAGS) -output-dir $(abspath $(BUILD))/lib $(foreach f,$(FYAML_CFLAGS),-c-flag $(f)) \
	  -library $(LIBRARY) $(LIBMODS:%=%.Mod)
	install -d $(LIBDIR)
	$(POC) $(POCFLAGS) -library-path $(BUILD)/lib -output-dir $(LIBDIR) -install-library $(LIBRARY)

# Remove what make install wrote, and only that.
uninstall:
	d=$(LIBDIR)/$(TRIPLE)/OC; \
	rm -f $$d/lib$(LIBRARY).a $$d/lib$(LIBRARY).so $$d/$(LIBRARY).library \
	  $(foreach x,$(LIBMODS),$$d/$(x).sym $$d/$(x).owner); \
	rmdir $$d 2>/dev/null; true

clean:
	rm -rf $(BUILD)
