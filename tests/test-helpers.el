;;; tests/test-helpers.el --- Shared test macros for Monet ERT suite  -*- lexical-binding: t -*-

;;; Code:

(defmacro monet-test-with-clean-registry (&rest body)
  "Execute BODY with a clean, isolated tool registry and enabled-sets."
  (declare (indent 0))
  `(let ((monet--tool-registry nil)
         (monet--enabled-sets '(:core :simple-diff)))
     ,@body))

(defmacro monet-test-with-clean-hooks (&rest body)
  "Execute BODY with an isolated `monet--claude-hook-functions' list."
  (declare (indent 0))
  `(let ((monet--claude-hook-functions nil))
     ,@body))

(provide 'test-helpers)
;;; tests/test-helpers.el ends here
