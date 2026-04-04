;;; tests/test-registry.el --- Tool registry tests  -*- lexical-binding: t -*-

;;; Code:
(require 'ert)
(require 'monet)
(require 'test-helpers)

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

(provide 'test-registry)
;;; tests/test-registry.el ends here
