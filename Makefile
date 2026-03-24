EMACS ?= emacs
ELPA_DIR ?= $(HOME)/.emacs.d/elpa

# Run all tests by default.
MATCH ?=

.PHONY: test clean

default: all

# Remove compiled files
clean:
	rm -f *.elc

EL_FILES := $(wildcard *.el)

# Run checkdoc on elisp files. To do this, we run checkdoc-file via -eval on every .el file in EL_FILES
WEBSOCKET_DIR := $(firstword $(wildcard $(ELPA_DIR)/websocket-*/))
LOAD_PATHS := -L . $(if $(WEBSOCKET_DIR),-L $(WEBSOCKET_DIR))

checkdoc:
	for FILE in ${EL_FILES}; do $(EMACS) --batch $(LOAD_PATHS) -eval "(setq sentence-end-double-space nil)" -eval "(checkdoc-file \"$$FILE\")" 2>&1 | grep -v "should be imperative" || true ; done

compile: clean
	@$(EMACS) --batch $(LOAD_PATHS) \
		--eval "(setq sentence-end-double-space nil)" \
		-f batch-byte-compile *.el 2>&1 | grep -v "websocket" || true

test:
	$(EMACS) --batch $(LOAD_PATHS) -l ert -l monet.el -l monet-emacs-tools.el \
		-l monet-tests.el \
		$(if $(MATCH),--eval "(ert-run-tests-batch-and-exit \"$(MATCH)\")",-f ert-run-tests-batch-and-exit)

all: checkdoc compile
