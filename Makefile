EMACS ?= emacs

# Run all tests by default.
MATCH ?=

.PHONY: test clean checkdoc compile pre-commit

default: compile

# Remove compiled files
clean:
	rm -f *.elc monet-autoloads.el

EL_FILES := monet.el monet-emacs-tools.el

checkdoc:
	for FILE in ${EL_FILES}; do $(EMACS) --batch -L . --eval "(package-initialize)" -eval "(setq sentence-end-double-space nil)" -eval "(checkdoc-file \"$$FILE\")" 2>&1 | grep -v "should be imperative" || true ; done

compile: clean
	@$(EMACS) --batch -L . --eval "(package-initialize)" \
		--eval "(setq sentence-end-double-space nil)" \
		--eval "(package-generate-autoloads \"monet\" \".\")" \
		-f batch-byte-compile $(EL_FILES) 2>&1 | grep -v "websocket" || true

TEST_FILES := tests/test-helpers.el tests/test-registry.el tests/test-dispatch.el \
              tests/test-emacs-tools.el tests/test-hooks.el

test:
	$(EMACS) --batch -L . -L tests --eval "(package-initialize)" -l ert -l monet.el -l monet-emacs-tools.el \
		$(foreach f,$(TEST_FILES),-l $(f)) \
		$(if $(MATCH),--eval "(ert-run-tests-batch-and-exit \"$(MATCH)\")",-f ert-run-tests-batch-and-exit)

pre-commit: checkdoc test
