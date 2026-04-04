;;; tests/test-emacs-tools.el --- Emacs tools registration and imenu format tests  -*- lexical-binding: t -*-

;;; Code:
(require 'ert)
(require 'monet)
(require 'monet-emacs-tools)
(require 'test-helpers)

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

(provide 'test-emacs-tools)
;;; tests/test-emacs-tools.el ends here
