.PHONY: check test test-vim test-config test-scale test-interrupt test-keys defcompile doc-tags clean

# The full gate, in the order that fails fastest.
check: doc-tags defcompile test-vim test-config test-scale test-interrupt test-keys

# Vim help uses *word* as a global tag definition, not Markdown emphasis.
# Generate tags in a scratch directory so the gate catches accidental prose
# tags.  doc/tags is installation output in this repository and is ignored.
doc-tags:
	@tmp=$$(mktemp -d) && cp doc/*.txt $$tmp/ && \
	vim -Nu NONE -n -i NONE -es -c "helptags $$tmp" -c 'qa!' </dev/null && \
	status=0; \
	foreign=$$(awk -F'\t' '$$1 !~ /^(simplewhichkey|g:simplewhichkey|:SimpleWhichKey|<Plug>\(simplewhichkey)/ { print $$1 }' $$tmp/tags); \
	if [ -n "$$foreign" ]; then \
	  echo "doc: *word* in prose defined a global help tag: $$foreign" >&2; status=1; fi; \
	rm -rf $$tmp; \
	[ $$status -eq 0 ] && echo "doc: help tags are valid and plugin-scoped"

# -i NONE everywhere: the register tests read what is actually in the
# registers, and without it a |viminfo-file| both seeds them from the machine
# running the suite and writes the fixtures back out to it.
#
# Compile every :def function so type errors surface without pressing a key.
defcompile:
	vim -N -u NONE -n -i NONE -es -S tests/defcompile.vim

test-vim:
	vim -N -u NONE -n -i NONE -es -S tests/vim_smoke.vim

test-config:
	vim -N -u NONE -n -i NONE -es -S tests/vim_config.vim

# What a panel costs is sweeps of the mapping table times mappings in it, so
# the budget is expressed in sweeps rather than in seconds a loaded machine
# can invent.
test-scale:
	vim -N -u NONE -n -i NONE -es -S tests/vim_scale.vim

# interrupt() is portable and exercises the same Vim:Interrupt path as CTRL-C
# without needing a platform-specific `kill` command or a terminal driver.
test-interrupt:
	vim -N -u NONE -n -i NONE -es -S tests/vim_interrupt.vim

# Real keystrokes need a pty.
test-keys:
	@tmp=$$(mktemp -d) || exit 1; trap 'rm -rf "$$tmp"' 0 1 2 15; status=0; \
	SIMPLEWHICHKEY_TEST_OUT="$$tmp/keys" script -qec "stty cols 100 rows 30; vim -N -u NONE -n -i NONE -S tests/vim_keys.vim" /dev/null >/dev/null || status=1; \
	test -f "$$tmp/keys" && cat "$$tmp/keys" || status=1; \
	grep -q '^PASS$$' "$$tmp/keys" 2>/dev/null || status=1; \
	SIMPLEWHICHKEY_TEST_OUT="$$tmp/macro" script -qec "stty cols 100 rows 30; vim -N -u NONE -n -i NONE -S tests/vim_keys_macro.vim" /dev/null >/dev/null || status=1; \
	test -f "$$tmp/macro" && cat "$$tmp/macro" || status=1; \
	grep -q '^PASS macro$$' "$$tmp/macro" 2>/dev/null || status=1; \
	SIMPLEWHICHKEY_TEST_CLIPBOARD=unnamedplus SIMPLEWHICHKEY_TEST_OUT="$$tmp/plus" script -qec "stty cols 100 rows 30; vim -N -u NONE -n -i NONE -S tests/vim_operator_clipboard.vim" /dev/null >/dev/null || status=1; \
	test -f "$$tmp/plus" && cat "$$tmp/plus" || status=1; \
	grep -q '^PASS unnamedplus$$' "$$tmp/plus" 2>/dev/null || status=1; \
	SIMPLEWHICHKEY_TEST_CLIPBOARD=unnamed SIMPLEWHICHKEY_TEST_OUT="$$tmp/star" script -qec "stty cols 100 rows 30; vim -N -u NONE -n -i NONE -S tests/vim_operator_clipboard.vim" /dev/null >/dev/null || status=1; \
	test -f "$$tmp/star" && cat "$$tmp/star" || status=1; \
	grep -q '^PASS unnamed$$' "$$tmp/star" 2>/dev/null || status=1; \
	exit $$status

test: test-vim test-config test-scale test-keys

clean:
	rm -f tests/.keys-result tests/.keys-macro-result tests/.keys-clipboard-plus-result tests/.keys-clipboard-star-result doc/tags
