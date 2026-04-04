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
  "Execute BODY with a clean, isolated tool registry and enabled-sets."
  (declare (indent 0))
  `(let ((monet--tool-registry nil)
         (monet--enabled-sets '(:core :simple-diff)))
     ,@body))

;;; Registry CRUD Tests

(ert-deftest monet-test-make-tool-register ()
  "Registering a new tool adds it to the registry."
  (monet-test-with-clean-registry
    (monet-make-tool :name "testTool"
                     :description "Test"
                     :schema '((type . "object") (properties . ()))
                     :handler #'ignore)
    (should (cl-find "testTool" monet--tool-registry
                     :key (lambda (e) (cdr (car e)))
                     :test #'equal))))

(ert-deftest monet-test-make-tool-lookup ()
  "Registered tool handler is retrievable from the registry."
  (monet-test-with-clean-registry
    (monet-make-tool :name "testTool"
                     :description "Test"
                     :schema '((type . "object") (properties . ()))
                     :handler #'ignore)
    (should (eq (monet--get-tool-handler "testTool") #'ignore))))

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
    (should (eq (monet--get-tool-handler "testTool") #'identity))
    (should (= (length (seq-filter (lambda (e) (equal (cdr (car e)) "testTool"))
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
    (should (monet--get-tool-handler "coreTool"))))

(ert-deftest monet-test-simple-diff-tools-enabled-by-default ()
  "Tools in :simple-diff set are enabled by default."
  (monet-test-with-clean-registry
    (monet-make-tool :name "diffTool"
                     :description "Test"
                     :schema '((type . "object") (properties . ()))
                     :handler #'ignore
                     :set :simple-diff)
    (should (monet--get-tool-handler "diffTool"))))

(ert-deftest monet-test-custom-set-disabled-by-default ()
  "Tools in custom sets are disabled by default."
  (monet-test-with-clean-registry
    (monet-make-tool :name "customTool"
                     :description "Test"
                     :schema '((type . "object") (properties . ()))
                     :handler #'ignore
                     :set :my-package)
    (should-not (monet--get-tool-handler "customTool"))))

(ert-deftest monet-test-override-preserves-enabled-state ()
  "Re-registering a tool preserves its current enabled state."
  (monet-test-with-clean-registry
    ;; Register as :simple-diff (starts enabled)
    (monet-make-tool :name "openDiff"
                     :description "Open a diff"
                     :schema '((type . "object") (properties . ()))
                     :handler #'ignore
                     :set :simple-diff)
    ;; Override with :birbal (same key (:simple-diff . "openDiff") replaced)
    ;; This re-registers under the same set, preserving enabled state
    (monet-make-tool :name "openDiff"
                     :description "Birbal diff"
                     :schema '((type . "object") (properties . ()))
                     :handler #'identity
                     :set :simple-diff)
    ;; Should still be enabled (preserved from before)
    (should (monet--get-tool-handler "openDiff"))))

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
    (should (monet--get-tool-handler "testTool"))))

(ert-deftest monet-test-disable-tool ()
  "Disable a tool by setting its :enabled flag to nil."
  (monet-test-with-clean-registry
    (monet-make-tool :name "testTool"
                     :description "Test"
                     :schema '((type . "object") (properties . ()))
                     :handler #'ignore
                     :set :core)              ; starts enabled
    (monet-disable-tool "testTool")
    (should-not (monet--get-tool-handler "testTool"))))

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
    (should (monet--get-tool-handler "tool1"))
    (should (monet--get-tool-handler "tool2"))))

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
    (should (monet--get-tool-handler "setA-tool"))
    (should-not (monet--get-tool-handler "setB-tool"))))

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
    (should-not (monet--get-tool-handler "tool1"))
    (should-not (monet--get-tool-handler "tool2"))))

(ert-deftest monet-test-enable-tool-set-with-reset ()
  "Calling monet-reset-tools then monet-enable-tool-set enables only the target set."
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
    ;; Both are now enabled. Reset then enable only :core.
    (monet-reset-tools)
    (monet-enable-tool-set :core)
    ;; :core tool should be enabled
    (should (monet--get-tool-handler "core-tool"))
    ;; :other tool should be disabled (reset cleared it, not re-enabled by :core)
    (should-not (monet--get-tool-handler "other-tool"))))

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
                     :set :simple-diff)
    (monet-reset-tools)
    (should-not (monet--get-tool-handler "t1"))
    (should-not (monet--get-tool-handler "t2"))))

;;; Ownership Transfer Tests

(ert-deftest monet-test-ownership-transfer-disable-old-set ()
  "Disabling old set does not affect tool re-registered under new set."
  (monet-test-with-clean-registry
    ;; Register in :simple-diff set (enabled)
    (monet-make-tool :name "openDiff"
                     :description "Open a diff"
                     :schema '((type . "object") (properties . ()))
                     :handler #'ignore
                     :set :simple-diff)
    ;; Register another :simple-diff tool
    (monet-make-tool :name "closeAllDiffTabs"
                     :description "Close diffs"
                     :schema '((type . "object") (properties . ()))
                     :handler #'ignore
                     :set :simple-diff)
    ;; Re-register openDiff as :birbal (new registry entry, since key is (set . name))
    (monet-make-tool :name "openDiff"
                     :description "Birbal diff"
                     :schema '((type . "object") (properties . ()))
                     :handler #'identity
                     :set :birbal)
    ;; Verify :birbal entry for openDiff exists
    (should (assoc '(:birbal . "openDiff") monet--tool-registry))
    ;; Disable the :simple-diff set
    (monet-disable-tool-set :simple-diff)
    ;; openDiff/:birbal is disabled by default (birbal not in monet--enabled-sets),
    ;; but it was newly registered so disabled; enable it manually to test isolation
    (monet-enable-tool-set :birbal)
    ;; openDiff should be enabled (it's :birbal now and :birbal is enabled)
    (should (monet--get-tool-handler "openDiff"))
    ;; closeAllDiffTabs should be disabled (still :simple-diff, which is now disabled)
    (should-not (monet--get-tool-handler "closeAllDiffTabs"))))

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
      ;; Override getCurrentSelection with a sentinel in a new :birbal set
      (monet-make-tool :name "getCurrentSelection"
                       :description "Custom"
                       :schema '((type . "object") (properties . ()))
                       :handler #'identity
                       :set :birbal)
      ;; Enable :birbal so it wins the conflict resolution
      (monet-enable-tool-set :birbal)
      ;; Verify override is active
      (should (eq (monet--get-tool-handler "getCurrentSelection") #'identity))
      ;; Restore defaults (clears registry; monet--enabled-sets retains :birbal but
      ;; no :birbal tools remain, so :core tools are enabled via monet--enabled-sets)
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
    (should-not (cl-find "externalTool" monet--tool-registry
                         :key (lambda (e) (cdr (car e)))
                         :test #'equal))))

;;; Conflict Resolution Tests

(ert-deftest monet-test-enable-ediff-disables-simple-diff ()
  "Enabling :ediff disables same-named tools in :simple-diff."
  (monet-test-with-clean-registry
    (monet-make-tool :name "openDiff"
                     :description "Simple diff"
                     :schema '((type . "object") (properties . ()))
                     :handler #'ignore
                     :set :simple-diff)
    (monet-make-tool :name "openDiff"
                     :description "Ediff"
                     :schema '((type . "object") (properties . ()))
                     :handler #'identity
                     :set :ediff)
    ;; :simple-diff is in monet--enabled-sets so openDiff/:simple-diff is enabled
    (should (eq (monet--get-tool-handler "openDiff") #'ignore))
    ;; Enable :ediff — should disable :simple-diff's openDiff
    (monet-enable-tool-set :ediff)
    (should (eq (monet--get-tool-handler "openDiff") #'identity))))

(ert-deftest monet-test-enable-simple-diff-disables-ediff ()
  "Enabling :simple-diff disables same-named tools in :ediff."
  (monet-test-with-clean-registry
    (monet-make-tool :name "openDiff"
                     :description "Simple diff"
                     :schema '((type . "object") (properties . ()))
                     :handler #'ignore
                     :set :simple-diff)
    (monet-make-tool :name "openDiff"
                     :description "Ediff"
                     :schema '((type . "object") (properties . ()))
                     :handler #'identity
                     :set :ediff)
    (monet-enable-tool-set :ediff)
    (should (eq (monet--get-tool-handler "openDiff") #'identity))
    ;; Now re-enable :simple-diff
    (monet-enable-tool-set :simple-diff)
    (should (eq (monet--get-tool-handler "openDiff") #'ignore))))

;;; :ediff Set Tests

(ert-deftest monet-test-register-core-tools-includes-ediff ()
  "Ediff tools are registered by monet-register-core-tools (disabled by default)."
  (monet-test-with-clean-registry
    (monet-register-core-tools)
    ;; :simple-diff's openDiff is enabled, so monet--get-tool-handler returns it
    ;; Verify :ediff entry EXISTS in registry even though disabled:
    (should (cl-find-if (lambda (e)
                          (and (equal (cdr (car e)) "openDiff")
                               (eq (plist-get (cdr e) :set) :ediff)))
                        monet--tool-registry))))

(ert-deftest monet-test-ediff-handler-returned-when-ediff-enabled ()
  "The ediff handler is returned by monet--get-tool-handler when :ediff is enabled."
  (monet-test-with-clean-registry
    (monet-register-core-tools)
    (monet-enable-tool-set :ediff)
    (should (eq (monet--get-tool-handler "openDiff")
                #'monet--tool-open-ediff-handler))))

(ert-deftest monet-test-simple-diff-handler-returned-after-reenabling ()
  "Re-enabling :simple-diff after :ediff restores the simple-diff handler."
  (monet-test-with-clean-registry
    (monet-register-core-tools)
    (monet-enable-tool-set :ediff)
    (monet-enable-tool-set :simple-diff)
    (should (eq (monet--get-tool-handler "openDiff")
                #'monet--tool-open-diff-handler))))

;;; Emacs Tools Registration Tests

(ert-deftest monet-test-register-emacs-tools-adds-emacs-tools-set ()
  "Five tools are registered in the :emacs-tools set."
  (monet-test-with-clean-registry
    (monet-register-emacs-tools)
    (should (cl-find "xref_find_references" monet--tool-registry
                     :key (lambda (e) (cdr (car e))) :test #'equal))
    (should (cl-find "xref_find_definitions" monet--tool-registry
                     :key (lambda (e) (cdr (car e))) :test #'equal))
    (should (cl-find "xref_find_apropos" monet--tool-registry
                     :key (lambda (e) (cdr (car e))) :test #'equal))
    (should (cl-find "imenu_list_symbols" monet--tool-registry
                     :key (lambda (e) (cdr (car e))) :test #'equal))
    (should (cl-find "treesit_info" monet--tool-registry
                     :key (lambda (e) (cdr (car e))) :test #'equal))))

(ert-deftest monet-test-register-emacs-tools-disabled-by-default ()
  "Introspection tools are disabled by default after registration."
  (monet-test-with-clean-registry
    (monet-register-emacs-tools)
    (should-not (monet--get-tool-handler "xref_find_references"))
    (should-not (monet--get-tool-handler "imenu_list_symbols"))
    (should-not (monet--get-tool-handler "treesit_info"))))

(ert-deftest monet-test-register-emacs-tools-enable-set ()
  "Enabling :emacs-tools set makes the tools accessible via monet--get-tool-handler."
  (monet-test-with-clean-registry
    (monet-register-emacs-tools)
    (monet-enable-tool-set :emacs-tools)
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
    (monet-enable-tool-set :emacs-tools)
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

;;; Claude Code Lifecycle Hook Tests

(defmacro monet-test-with-clean-hooks (&rest body)
  "Execute BODY with an isolated `monet--claude-hook-functions' list."
  (declare (indent 0))
  `(let ((monet--claude-hook-functions nil))
     ,@body))

(ert-deftest monet-test-add-claude-hook-handler ()
  "Adding a handler registers it in monet--claude-hook-functions."
  (monet-test-with-clean-hooks
    (monet-add-claude-hook-handler #'ignore)
    (should (memq #'ignore monet--claude-hook-functions))))

(ert-deftest monet-test-add-claude-hook-handler-idempotent ()
  "Adding the same handler twice does not duplicate it."
  (monet-test-with-clean-hooks
    (monet-add-claude-hook-handler #'ignore)
    (monet-add-claude-hook-handler #'ignore)
    (should (= 1 (length monet--claude-hook-functions)))))

(ert-deftest monet-test-remove-claude-hook-handler ()
  "Removing a handler deregisters it."
  (monet-test-with-clean-hooks
    (monet-add-claude-hook-handler #'ignore)
    (monet-remove-claude-hook-handler #'ignore)
    (should (null monet--claude-hook-functions))))

(ert-deftest monet-test-claude-hook-receive-dispatches ()
  "monet-claude-hook-receive calls each handler with (event data ctx)."
  (monet-test-with-clean-hooks
    (let ((received nil))
      (monet-add-claude-hook-handler
       (lambda (event data ctx) (push (list event data ctx) received)))
      (let ((tmpfile (make-temp-file "monet-hook-test-" nil ".json")))
        (unwind-protect
            (progn
              (with-temp-file tmpfile
                (insert (json-encode
                         '((hook_payload . ((hook_event_name . "Stop") (cwd . "/tmp")))
                           (monet_context . ((baton_session . "claude-1")))))))
              (monet-claude-hook-receive tmpfile)
              (should (= 1 (length received)))
              (let ((entry (car received)))
                (should (equal "Stop" (nth 0 entry)))
                (should (equal "/tmp" (cdr (assq 'cwd (nth 1 entry)))))
                (should (equal "claude-1"
                               (cdr (assq 'baton_session (nth 2 entry)))))))
          (ignore-errors (delete-file tmpfile)))))))

(ert-deftest monet-test-claude-hook-receive-handler-error-isolated ()
  "A failing handler does not prevent subsequent handlers from running."
  (monet-test-with-clean-hooks
    (let ((second-called nil))
      ;; Push in reverse order because monet-add-claude-hook-handler prepends
      (monet-add-claude-hook-handler
       (lambda (_e _d _c) (setq second-called t)))
      (monet-add-claude-hook-handler
       (lambda (_e _d _c) (error "intentional test error")))
      (let ((tmpfile (make-temp-file "monet-hook-test-" nil ".json")))
        (unwind-protect
            (progn
              (with-temp-file tmpfile
                (insert (json-encode
                         '((hook_payload . ((hook_event_name . "Stop")))
                           (monet_context . ())))))
              (monet-claude-hook-receive tmpfile)
              (should second-called))
          (ignore-errors (delete-file tmpfile)))))))

(ert-deftest monet-test-claude-hook-receive-missing-file ()
  "monet-claude-hook-receive silently returns when file does not exist."
  (monet-test-with-clean-hooks
    ;; Should not signal an error
    (should-not (monet-claude-hook-receive "/nonexistent/path/hook.json"))))

(ert-deftest monet-test-install-remove-claude-hooks ()
  "monet-install-claude-hooks writes entries; monet-remove-claude-hooks removes them."
  (let ((tmpdir (make-temp-file "monet-settings-test-" t))
        (script-path (monet--claude-hook-script-path)))
    (unwind-protect
        (cl-letf (((symbol-function 'monet--claude-settings-path)
                   (lambda () (expand-file-name "settings.json" tmpdir))))
          ;; Install
          (monet-install-claude-hooks)
          (let* ((settings (json-read-file (monet--claude-settings-path)))
                 (hooks (cdr (assq 'hooks settings))))
            (dolist (event '(Stop SubagentStop Notification UserPromptSubmit))
              (let* ((event-list (append (cdr (assq event hooks)) nil))
                     (commands (mapcar #'monet--hook-entry-command event-list)))
                (should (member script-path commands)))))
          ;; Remove
          (monet-remove-claude-hooks)
          (let* ((settings (json-read-file (monet--claude-settings-path)))
                 (hooks (cdr (assq 'hooks settings))))
            (dolist (event '(Stop SubagentStop Notification UserPromptSubmit))
              (let* ((event-list (append (cdr (assq event hooks)) nil))
                     (commands (mapcar #'monet--hook-entry-command event-list)))
                (should-not (member script-path commands))))))
      (ignore-errors (delete-directory tmpdir t)))))

(ert-deftest monet-test-install-claude-hooks-idempotent ()
  "monet-install-claude-hooks does not duplicate entries on repeated calls."
  (let ((tmpdir (make-temp-file "monet-settings-test-" t))
        (script-path (monet--claude-hook-script-path)))
    (unwind-protect
        (cl-letf (((symbol-function 'monet--claude-settings-path)
                   (lambda () (expand-file-name "settings.json" tmpdir))))
          (monet-install-claude-hooks)
          (monet-install-claude-hooks)
          (let* ((settings (json-read-file (monet--claude-settings-path)))
                 (hooks (cdr (assq 'hooks settings))))
            (dolist (event '(Stop SubagentStop Notification UserPromptSubmit))
              (let* ((event-list (append (cdr (assq event hooks)) nil))
                     (commands (mapcar #'monet--hook-entry-command event-list)))
                (should (= 1 (cl-count script-path commands :test #'equal)))))))
      (ignore-errors (delete-directory tmpdir t)))))

(provide 'monet-tests)
;;; monet-tests.el ends here
