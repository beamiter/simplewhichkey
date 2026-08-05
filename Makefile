.PHONY: check test test-vim test-keys defcompile clean

# The full gate, in the order that fails fastest.
check: defcompile test-vim test-keys

# Compile every :def function so type errors surface without pressing a key.
defcompile:
	vim -N -u NONE -n -es -S tests/defcompile.vim

test-vim:
	vim -N -u NONE -n -es -S tests/vim_smoke.vim

# Real keystrokes need a pty.
test-keys:
	@rm -f tests/.keys-result
	@script -qec "stty cols 100 rows 30; vim -N -u NONE -S tests/vim_keys.vim" /dev/null >/dev/null
	@cat tests/.keys-result
	@grep -q '^PASS$$' tests/.keys-result

test: test-vim test-keys

clean:
	rm -f tests/.keys-result doc/tags
