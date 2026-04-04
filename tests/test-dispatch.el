;;; tests/test-dispatch.el --- Dispatch, core-tools, and conflict-resolution tests  -*- lexical-binding: t -*-

;;; Code:
(require 'ert)
(require 'monet)
(require 'test-helpers)

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

(provide 'test-dispatch)
;;; tests/test-dispatch.el ends here
