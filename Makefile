NVIM_CMD := nvim --headless --noplugin

# Neovim plugins versions.
# These are dev dependencies.
MINI_TEST_GIT_COMMIT := v0.17.0
# Points to a commit rather than to a tag because the plugin relies on `listeners.on_session`,
# which is in nvim-dap's default branch but not in its latest tag (0.10.0)
NVIM_DAP_GIT_COMMIT := 9e848e09a697ee95302a3ef2dd43fd6eb709e570

# Run mini.test tests.
.PHONY: test
test: deps/mini.test deps/nvim-dap
	$(NVIM_CMD) -u ./scripts/minimal_init.lua -c "lua MiniTest.run()"

deps/mini.test:
	@mkdir -p deps
	git clone --depth 1 --branch $(MINI_TEST_GIT_COMMIT) \
	https://github.com/nvim-mini/mini.test \
	$@

deps/nvim-dap:
	@mkdir -p $@
	git -C $@ init --quiet
	git -C $@ fetch --depth 1 --quiet \
	https://github.com/mfussenegger/nvim-dap \
	$(NVIM_DAP_GIT_COMMIT)
	git -C $@ checkout --quiet FETCH_HEAD
