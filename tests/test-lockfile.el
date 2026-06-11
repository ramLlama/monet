;;; tests/test-lockfile.el --- IDE lockfile and env-function tests  -*- lexical-binding: t -*-

;;; Code:
(require 'ert)
(require 'monet)
(require 'test-helpers)

;;; Lockfile workspaceFolders

(defmacro monet-test-with-lockfile-dir (&rest body)
  "Run BODY with the lockfile dir redirected to a temp dir bound to `lockdir'."
  (declare (indent 0))
  `(let ((lockdir (make-temp-file "monet-lockfile-test-" t)))
     (ignore lockdir)
     (unwind-protect
         (cl-letf (((symbol-function 'monet--get-lockfile-dir)
                    (lambda () lockdir)))
           ,@body)
       (ignore-errors (delete-directory lockdir t)))))

(ert-deftest monet-test-lockfile-single-workspace-folder ()
  "Without extras, workspaceFolders contains only the session folder."
  (monet-test-with-lockfile-dir
    (monet--create-lockfile "/proj" 12345 "tok" "key-1")
    (let* ((json (json-read-file (expand-file-name "12345.lock" lockdir)))
           (folders (cdr (assq 'workspaceFolders json))))
      (should (equal (append folders nil) '("/proj"))))))

(ert-deftest monet-test-lockfile-extra-workspace-folders ()
  "Extra folders are appended to workspaceFolders after the session folder.
A sandboxed Claude sees the worktree at a guest path (e.g. /workspace);
listing it lets Claude match the lockfile against its in-guest cwd."
  (monet-test-with-lockfile-dir
    (monet--create-lockfile "/proj" 12345 "tok" "key-1" '("/workspace"))
    (let* ((json (json-read-file (expand-file-name "12345.lock" lockdir)))
           (folders (cdr (assq 'workspaceFolders json))))
      (should (equal (append folders nil) '("/proj" "/workspace"))))))

;;; monet-start-server-function

(ert-deftest monet-test-start-server-function-env-shape ()
  "The env-function returns the documented (:env … :ports …) shape.
ENABLE_IDE_INTEGRATION must be the string \"true\" — Claude Code does
not recognize other truthy spellings."
  (cl-letf (((symbol-function 'monet--start-hook-server) (lambda () 41111))
            ((symbol-function 'monet-start-server-in-directory)
             (lambda (_key _dir &optional _extras)
               (make-monet--session :key "key-1" :port 42222))))
    (let ((monet--hook-port 41111))
      (let ((result (monet-start-server-function "key-1" "/proj")))
        (should (member "ENABLE_IDE_INTEGRATION=true" (plist-get result :env)))
        (should (member "CLAUDE_CODE_SSE_PORT=42222" (plist-get result :env)))
        (should (member "MONET_HOOK_PORT=41111" (plist-get result :env)))
        (should (equal (plist-get result :ports) '(42222 41111)))))))

(ert-deftest monet-test-start-server-function-passes-path-mappings ()
  "Path mappings flow through to the server start."
  (let (seen-mappings)
    (cl-letf (((symbol-function 'monet--start-hook-server) (lambda () 41111))
              ((symbol-function 'monet-start-server-in-directory)
               (lambda (_key _dir &optional mappings)
                 (setq seen-mappings mappings)
                 (make-monet--session :key "key-1" :port 42222))))
      (let ((monet--hook-port 41111))
        (monet-start-server-function "key-1" "/proj" '(("/proj" . "/workspace")))
        (should (equal seen-mappings '(("/proj" . "/workspace"))))))))

(provide 'test-lockfile)
;;; tests/test-lockfile.el ends here
