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

(defmacro monet-test-with-hook-server (&rest body)
  "Execute BODY with a fresh, isolated HTTP hook server.
Starts the server before BODY and stops it with cleanup after."
  (declare (indent 0))
  `(let ((monet--hook-server nil)
         (monet--hook-port nil))
     (monet--start-hook-server)
     (unwind-protect
         (progn ,@body)
       (monet--stop-hook-server))))

(provide 'test-helpers)
;;; tests/test-helpers.el ends here
