;;; monet-tests.el --- ERT test suite for Monet   -*- lexical-binding: t -*-

;; Author: Ram Krishnaraj
;; Keywords: tools, ai, test

;;; Commentary:
;; ERT tests for the Monet tool registry API, dispatch, and introspection tools.
;;
;; Run with (via Makefile):
;;   make test

;;; Code:
(require 'ert)
(require 'monet)
(require 'monet-emacs-tools)

;;; Test Helpers

(defmacro monet-test-with-clean-registry (&rest body)
  "Execute BODY with a clean, isolated tool registry."
  (declare (indent 0))
  `(let ((monet--tool-registry nil))
     ,@body))

;;; Registry CRUD Tests

(ert-deftest monet-test-make-tool-register ()
  "Registering a new tool adds it to the registry."
  (monet-test-with-clean-registry
    (monet-make-tool :name "testTool"
                     :description "Test"
                     :schema '((type . "object") (properties . ()))
                     :handler #'ignore)
    (should (assoc "testTool" monet--tool-registry))))

(ert-deftest monet-test-make-tool-lookup ()
  "Registered tool handler is retrievable from the registry."
  (monet-test-with-clean-registry
    (monet-make-tool :name "testTool"
                     :description "Test"
                     :schema '((type . "object") (properties . ()))
                     :handler #'ignore)
    (should (equal (plist-get (cdr (assoc "testTool" monet--tool-registry)) :handler)
                   #'ignore))))

(ert-deftest monet-test-make-tool-override ()
  "Re-registering a tool replaces its handler without duplicating the entry."
  (monet-test-with-clean-registry
    (monet-make-tool :name "testTool"
                     :description "Test"
                     :schema '((type . "object") (properties . ()))
                     :handler #'ignore)
    (monet-make-tool :name "testTool"
                     :description "Test v2"
                     :schema '((type . "object") (properties . ()))
                     :handler #'identity)
    (should (equal (plist-get (cdr (assoc "testTool" monet--tool-registry)) :handler)
                   #'identity))
    (should (= (length (seq-filter (lambda (e) (string= (car e) "testTool"))
                                   monet--tool-registry))
               1))))

;;; Default Enabled State Tests

(ert-deftest monet-test-core-tools-enabled-by-default ()
  "Tools in :core set are enabled by default."
  (monet-test-with-clean-registry
    (monet-make-tool :name "coreTool"
                     :description "Test"
                     :schema '((type . "object") (properties . ()))
                     :handler #'ignore
                     :set :core)
    (should (plist-get (cdr (assoc "coreTool" monet--tool-registry)) :enabled))))

(ert-deftest monet-test-diff-tools-enabled-by-default ()
  "Tools in :diff set are enabled by default."
  (monet-test-with-clean-registry
    (monet-make-tool :name "diffTool"
                     :description "Test"
                     :schema '((type . "object") (properties . ()))
                     :handler #'ignore
                     :set :diff)
    (should (plist-get (cdr (assoc "diffTool" monet--tool-registry)) :enabled))))

(ert-deftest monet-test-custom-set-disabled-by-default ()
  "Tools in custom sets are disabled by default."
  (monet-test-with-clean-registry
    (monet-make-tool :name "customTool"
                     :description "Test"
                     :schema '((type . "object") (properties . ()))
                     :handler #'ignore
                     :set :my-package)
    (should-not (plist-get (cdr (assoc "customTool" monet--tool-registry)) :enabled))))

(ert-deftest monet-test-override-preserves-enabled-state ()
  "Re-registering a tool preserves its current enabled state."
  (monet-test-with-clean-registry
    ;; Register as :diff (starts enabled)
    (monet-make-tool :name "openDiff"
                     :description "Open a diff"
                     :schema '((type . "object") (properties . ()))
                     :handler #'ignore
                     :set :diff)
    ;; Override with :birbal (custom set, would be disabled if new)
    (monet-make-tool :name "openDiff"
                     :description "Birbal diff"
                     :schema '((type . "object") (properties . ()))
                     :handler #'identity
                     :set :birbal)
    ;; Should still be enabled (preserved from before)
    (should (plist-get (cdr (assoc "openDiff" monet--tool-registry)) :enabled))))

;;; Enable/Disable Individual Tool Tests

(ert-deftest monet-test-enable-tool ()
  "Enable a single tool by setting its :enabled flag to t."
  (monet-test-with-clean-registry
    (monet-make-tool :name "testTool"
                     :description "Test"
                     :schema '((type . "object") (properties . ()))
                     :handler #'ignore
                     :set :my-package)         ; starts disabled
    (monet-enable-tool "testTool")
    (should (plist-get (cdr (assoc "testTool" monet--tool-registry)) :enabled))))

(ert-deftest monet-test-disable-tool ()
  "Disable a tool by setting its :enabled flag to nil."
  (monet-test-with-clean-registry
    (monet-make-tool :name "testTool"
                     :description "Test"
                     :schema '((type . "object") (properties . ()))
                     :handler #'ignore
                     :set :core)              ; starts enabled
    (monet-disable-tool "testTool")
    (should-not (plist-get (cdr (assoc "testTool" monet--tool-registry)) :enabled))))

;;; Enable/Disable Tool Set Tests

(ert-deftest monet-test-enable-tool-set ()
  "Enable all tools whose :set matches the given set keyword."
  (monet-test-with-clean-registry
    (monet-make-tool :name "tool1"
                     :description "Test"
                     :schema '((type . "object") (properties . ()))
                     :handler #'ignore
                     :set :my-set)
    (monet-make-tool :name "tool2"
                     :description "Test"
                     :schema '((type . "object") (properties . ()))
                     :handler #'ignore
                     :set :my-set)
    (monet-enable-tool-set :my-set)
    (should (plist-get (cdr (assoc "tool1" monet--tool-registry)) :enabled))
    (should (plist-get (cdr (assoc "tool2" monet--tool-registry)) :enabled))))

(ert-deftest monet-test-enable-tool-set-only-affects-matching ()
  "Only tools in the target set are enabled; other sets are unaffected."
  (monet-test-with-clean-registry
    (monet-make-tool :name "setA-tool"
                     :description "Test"
                     :schema '((type . "object") (properties . ()))
                     :handler #'ignore
                     :set :set-a)
    (monet-make-tool :name "setB-tool"
                     :description "Test"
                     :schema '((type . "object") (properties . ()))
                     :handler #'ignore
                     :set :set-b)
    (monet-enable-tool-set :set-a)
    (should (plist-get (cdr (assoc "setA-tool" monet--tool-registry)) :enabled))
    (should-not (plist-get (cdr (assoc "setB-tool" monet--tool-registry)) :enabled))))

(ert-deftest monet-test-disable-tool-set ()
  "Disable all tools whose current :set matches the given set keyword."
  (monet-test-with-clean-registry
    (monet-make-tool :name "tool1"
                     :description "Test"
                     :schema '((type . "object") (properties . ()))
                     :handler #'ignore
                     :set :core)
    (monet-make-tool :name "tool2"
                     :description "Test"
                     :schema '((type . "object") (properties . ()))
                     :handler #'ignore
                     :set :core)
    (monet-disable-tool-set :core)
    (should-not (plist-get (cdr (assoc "tool1" monet--tool-registry)) :enabled))
    (should-not (plist-get (cdr (assoc "tool2" monet--tool-registry)) :enabled))))

(ert-deftest monet-test-enable-tool-set-with-reset ()
  "With RESET, all tools are disabled before the target set is enabled."
  (monet-test-with-clean-registry
    (monet-make-tool :name "core-tool"
                     :description "Test"
                     :schema '((type . "object") (properties . ()))
                     :handler #'ignore
                     :set :core)             ; starts enabled
    (monet-make-tool :name "other-tool"
                     :description "Test"
                     :schema '((type . "object") (properties . ()))
                     :handler #'ignore
                     :set :other)
    (monet-enable-tool "other-tool")         ; manually enable
    ;; Both are now enabled. Enable :core with reset.
    (monet-enable-tool-set :core t)
    ;; :core tool should be enabled
    (should (plist-get (cdr (assoc "core-tool" monet--tool-registry)) :enabled))
    ;; :other tool should be disabled (reset cleared it, not re-enabled by :core)
    (should-not (plist-get (cdr (assoc "other-tool" monet--tool-registry)) :enabled))))

(ert-deftest monet-test-reset-tools ()
  "Every tool in the registry is disabled by monet-reset-tools."
  (monet-test-with-clean-registry
    (monet-make-tool :name "t1"
                     :description "Test"
                     :schema '((type . "object") (properties . ()))
                     :handler #'ignore
                     :set :core)
    (monet-make-tool :name "t2"
                     :description "Test"
                     :schema '((type . "object") (properties . ()))
                     :handler #'ignore
                     :set :diff)
    (monet-reset-tools)
    (should-not (plist-get (cdr (assoc "t1" monet--tool-registry)) :enabled))
    (should-not (plist-get (cdr (assoc "t2" monet--tool-registry)) :enabled))))

;;; Ownership Transfer Tests

(ert-deftest monet-test-ownership-transfer-disable-old-set ()
  "Disabling old set does not affect tool re-registered under new set."
  (monet-test-with-clean-registry
    ;; Register in :diff set (enabled)
    (monet-make-tool :name "openDiff"
                     :description "Open a diff"
                     :schema '((type . "object") (properties . ()))
                     :handler #'ignore
                     :set :diff)
    ;; Register another :diff tool
    (monet-make-tool :name "closeAllDiffTabs"
                     :description "Close diffs"
                     :schema '((type . "object") (properties . ()))
                     :handler #'ignore
                     :set :diff)
    ;; Re-register openDiff as :birbal (ownership transfer)
    (monet-make-tool :name "openDiff"
                     :description "Birbal diff"
                     :schema '((type . "object") (properties . ()))
                     :handler #'identity
                     :set :birbal)
    ;; Verify ownership changed
    (should (eq (plist-get (cdr (assoc "openDiff" monet--tool-registry)) :set) :birbal))
    ;; Disable the :diff set
    (monet-disable-tool-set :diff)
    ;; openDiff should still be enabled (it's :birbal now)
    (should (plist-get (cdr (assoc "openDiff" monet--tool-registry)) :enabled))
    ;; closeAllDiffTabs should be disabled (still :diff)
    (should-not (plist-get (cdr (assoc "closeAllDiffTabs" monet--tool-registry)) :enabled))))

;;; Dispatch Tests

(ert-deftest monet-test-get-tools-list-only-enabled ()
  "Only enabled tools appear in the monet--get-tools-list result."
  (monet-test-with-clean-registry
    (monet-make-tool :name "enabled-tool"
                     :description "Enabled"
                     :schema '((type . "object") (properties . ()))
                     :handler #'ignore
                     :set :core)             ; enabled
    (monet-make-tool :name "disabled-tool"
                     :description "Disabled"
                     :schema '((type . "object") (properties . ()))
                     :handler #'ignore
                     :set :my-set)           ; disabled
    (let ((list (monet--get-tools-list)))
      (should (= (length list) 1))
      (should (equal (alist-get 'name (aref list 0)) "enabled-tool")))))

(ert-deftest monet-test-get-tools-list-includes-schema ()
  "Output includes description and inputSchema for each enabled tool."
  (monet-test-with-clean-registry
    (let ((schema '((type . "object") (properties . ((x . ((type . "string"))))))))
      (monet-make-tool :name "myTool"
                       :description "My tool"
                       :schema schema
                       :handler #'ignore
                       :set :core)
      (let* ((list (monet--get-tools-list))
             (entry (aref list 0)))
        (should (equal (alist-get 'name entry) "myTool"))
        (should (equal (alist-get 'description entry) "My tool"))
        (should (equal (alist-get 'inputSchema entry) schema))))))

(ert-deftest monet-test-get-tool-handler-returns-handler ()
  "The handler function is returned for an enabled tool."
  (monet-test-with-clean-registry
    (monet-make-tool :name "myTool"
                     :description "Test"
                     :schema '((type . "object") (properties . ()))
                     :handler #'ignore
                     :set :core)
    (should (eq (monet--get-tool-handler "myTool") #'ignore))))

(ert-deftest monet-test-get-tool-handler-nil-for-disabled ()
  "Nil is returned for a disabled tool."
  (monet-test-with-clean-registry
    (monet-make-tool :name "myTool"
                     :description "Test"
                     :schema '((type . "object") (properties . ()))
                     :handler #'ignore
                     :set :my-set)           ; disabled
    (should-not (monet--get-tool-handler "myTool"))))

(ert-deftest monet-test-get-tool-handler-nil-for-unknown ()
  "Nil is returned for an unregistered tool name."
  (monet-test-with-clean-registry
    (should-not (monet--get-tool-handler "unknownTool"))))

;;; monet-register-core-tools Tests

(ert-deftest monet-test-register-core-tools-populates-registry ()
  "All expected core and diff tools are registered and enabled."
  (monet-test-with-clean-registry
    (monet-register-core-tools)
    (should (monet--get-tool-handler "getCurrentSelection"))
    (should (monet--get-tool-handler "getLatestSelection"))
    (should (monet--get-tool-handler "getDiagnostics"))
    (should (monet--get-tool-handler "getOpenEditors"))
    (should (monet--get-tool-handler "getWorkspaceFolders"))
    (should (monet--get-tool-handler "checkDocumentDirty"))
    (should (monet--get-tool-handler "saveDocument"))
    (should (monet--get-tool-handler "openFile"))
    (should (monet--get-tool-handler "openDiff"))
    (should (monet--get-tool-handler "closeAllDiffTabs"))
    (should (monet--get-tool-handler "close_tab"))))

(ert-deftest monet-test-register-core-tools-restores-after-override ()
  "Default handlers are restored by monet-register-core-tools after an override."
  (monet-test-with-clean-registry
    (monet-register-core-tools)
    (let ((original-handler (monet--get-tool-handler "getCurrentSelection")))
      ;; Override getCurrentSelection with a sentinel
      (monet-make-tool :name "getCurrentSelection"
                       :description "Custom"
                       :schema '((type . "object") (properties . ()))
                       :handler #'identity
                       :set :birbal)
      ;; Verify override is active
      (should (eq (monet--get-tool-handler "getCurrentSelection") #'identity))
      ;; Restore defaults
      (monet-register-core-tools)
      ;; Verify original handler is back
      (should (eq (monet--get-tool-handler "getCurrentSelection") original-handler)))))

(ert-deftest monet-test-register-core-tools-clears-custom-tools ()
  "Externally registered tools are cleared when monet-register-core-tools is called."
  (monet-test-with-clean-registry
    (monet-register-core-tools)
    (monet-make-tool :name "externalTool"
                     :description "External"
                     :schema '((type . "object") (properties . ()))
                     :handler #'ignore
                     :set :external)
    ;; Re-register core tools
    (monet-register-core-tools)
    ;; External tool should be gone
    (should-not (assoc "externalTool" monet--tool-registry))))

;;; Introspection Tool Registration Tests

(ert-deftest monet-test-register-emacs-tools-adds-introspection-set ()
  "Five tools are registered in the :introspection set."
  (monet-test-with-clean-registry
    (monet-register-emacs-tools)
    (should (assoc "xref_find_references" monet--tool-registry))
    (should (assoc "xref_find_definitions" monet--tool-registry))
    (should (assoc "xref_find_apropos" monet--tool-registry))
    (should (assoc "imenu_list_symbols" monet--tool-registry))
    (should (assoc "treesit_info" monet--tool-registry))))

(ert-deftest monet-test-register-emacs-tools-disabled-by-default ()
  "Introspection tools are disabled by default after registration."
  (monet-test-with-clean-registry
    (monet-register-emacs-tools)
    (should-not (monet--get-tool-handler "xref_find_references"))
    (should-not (monet--get-tool-handler "imenu_list_symbols"))
    (should-not (monet--get-tool-handler "treesit_info"))))

(ert-deftest monet-test-register-emacs-tools-enable-set ()
  "Enabling :introspection set makes the tools accessible via monet--get-tool-handler."
  (monet-test-with-clean-registry
    (monet-register-emacs-tools)
    (monet-enable-tool-set :introspection)
    (should (monet--get-tool-handler "xref_find_references"))
    (should (monet--get-tool-handler "xref_find_definitions"))
    (should (monet--get-tool-handler "xref_find_apropos"))
    (should (monet--get-tool-handler "imenu_list_symbols"))
    (should (monet--get-tool-handler "treesit_info"))))

(ert-deftest monet-test-register-emacs-tools-coexists-with-core ()
  "Introspection tools coexist with core tools when both are registered."
  (monet-test-with-clean-registry
    (monet-register-core-tools)
    (monet-register-emacs-tools)
    (monet-enable-tool-set :introspection)
    ;; Core tools still enabled
    (should (monet--get-tool-handler "getCurrentSelection"))
    (should (monet--get-tool-handler "openDiff"))
    ;; Introspection tools now enabled
    (should (monet--get-tool-handler "imenu_list_symbols"))))

;;; imenu output format tests

(ert-deftest monet-test-imenu-format-marker-entry ()
  "Marker-based imenu entries format as file:line: name."
  (with-temp-buffer
    (insert "hello world\nsecond line\n")
    (let* ((file (make-temp-file "monet-test"))
           (marker (progn (goto-char 14) (point-marker)))
           (entry (cons "my-func" marker))
           (result (monet-emacs-tools--format-imenu-entry entry file "")))
      (unwind-protect
          (progn
            (should (= (length result) 1))
            (should (string-match "my-func" (car result)))
            (should (string-match ":" (car result))))
        (delete-file file)))))

(ert-deftest monet-test-imenu-format-skips-star-entries ()
  "Imenu entries whose names start with * are skipped."
  (with-temp-buffer
    (let* ((marker (point-marker))
           (entry (cons "*Rescan*" marker))
           (result (monet-emacs-tools--format-imenu-entry entry "" "")))
      (should (null result)))))

(ert-deftest monet-test-imenu-format-nested-category ()
  "Nested imenu categories are flattened with category prefix."
  (with-temp-buffer
    (insert "line one\nline two\n")
    (let* ((m1 (progn (goto-char 1) (point-marker)))
           (m2 (progn (goto-char 10) (point-marker)))
           (nested `("Methods" . (("foo" . ,m1) ("bar" . ,m2))))
           (result (monet-emacs-tools--format-imenu-entry nested "" "")))
      (should (= (length result) 2))
      (should (cl-some (lambda (s) (string-match "\\[Methods\\]" s)) result))
      (should (cl-some (lambda (s) (string-match "foo" s)) result))
      (should (cl-some (lambda (s) (string-match "bar" s)) result)))))

(provide 'monet-tests)
;;; monet-tests.el ends here
