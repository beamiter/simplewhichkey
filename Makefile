.PHONY: check test test-vim test-scale test-keys defcompile clean

# The full gate, in the order that fails fastest.
check: defcompile test-vim test-scale test-keys

# Compile every :def function so type errors surface without pressing a key.
defcompile:
	vim -N -u NONE -n -es -S tests/defcompile.vim

test-vim:
	vim -N -u NONE -n -es -S tests/vim_smoke.vim

# What a panel costs is sweeps of the mapping table times mappings in it, so
# the budget is expressed in sweeps rather than in seconds a loaded machine
# can invent.
test-scale:
	vim -N -u NONE -n -es -S tests/vim_scale.vim

# Real keystrokes need a pty.
test-keys:
	@rm -f tests/.keys-result tests/.keys-clipboard-plus-result tests/.keys-clipboard-star-result
	@script -qec "stty cols 100 rows 30; vim -N -u NONE -n -i NONE -S tests/vim_keys.vim" /dev/null >/dev/null
	@cat tests/.keys-result
	@grep -q '^PASS$$' tests/.keys-result
	@SIMPLEWHICHKEY_TEST_CLIPBOARD=unnamedplus SIMPLEWHICHKEY_TEST_OUT=tests/.keys-clipboard-plus-result script -qec "stty cols 100 rows 30; vim -N -u NONE -n -i NONE -S tests/vim_operator_clipboard.vim" /dev/null >/dev/null
	@cat tests/.keys-clipboard-plus-result
	@grep -q '^PASS unnamedplus$$' tests/.keys-clipboard-plus-result
	@SIMPLEWHICHKEY_TEST_CLIPBOARD=unnamed SIMPLEWHICHKEY_TEST_OUT=tests/.keys-clipboard-star-result script -qec "stty cols 100 rows 30; vim -N -u NONE -n -i NONE -S tests/vim_operator_clipboard.vim" /dev/null >/dev/null
	@cat tests/.keys-clipboard-star-result
	@grep -q '^PASS unnamed$$' tests/.keys-clipboard-star-result
	@rm -f tests/.keys-result tests/.keys-clipboard-plus-result tests/.keys-clipboard-star-result

test: test-vim test-scale test-keys

clean:
	rm -f tests/.keys-result tests/.keys-clipboard-plus-result tests/.keys-clipboard-star-result doc/tags
