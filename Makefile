EMACS ?= emacs

# Run all tests by default.
MATCH ?=

.PHONY: test clean

default: all

# Remove compiled files
clean:
	rm -f *.elc

EL_FILES := $(wildcard *.el)

checkdoc:
	for FILE in ${EL_FILES}; do $(EMACS) --batch -L . --eval "(package-initialize)" -eval "(setq sentence-end-double-space nil)" -eval "(checkdoc-file \"$$FILE\")" 2>&1 | grep -v "should be imperative" || true ; done

compile: clean
	@$(EMACS) --batch -L . --eval "(package-initialize)" \
		--eval "(setq sentence-end-double-space nil)" \
		-f batch-byte-compile *.el 2>&1 | grep -v "websocket" || true

test:
	$(EMACS) --batch -L . --eval "(package-initialize)" -l ert -l monet.el -l monet-emacs-tools.el \
		-l monet-tests.el \
		$(if $(MATCH),--eval "(ert-run-tests-batch-and-exit \"$(MATCH)\")",-f ert-run-tests-batch-and-exit)

all: checkdoc compile
