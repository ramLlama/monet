;;; tests/test-hooks.el --- Claude Code lifecycle hook tests  -*- lexical-binding: t -*-

;;; Code:
(require 'ert)
(require 'monet)
(require 'test-helpers)

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

;;; monet--hook-dispatch-envelope

(ert-deftest monet-test-hook-dispatch-envelope ()
  "monet--hook-dispatch-envelope calls each handler with (event data ctx)."
  (monet-test-with-clean-hooks
    (let ((received nil))
      (monet-add-claude-hook-handler
       (lambda (event data ctx) (push (list event data ctx) received)))
      (monet--hook-dispatch-envelope
       '((hook_payload . ((hook_event_name . "Stop") (cwd . "/tmp")))
         (monet_context . ((baton_session . "claude-1")))))
      (should (= 1 (length received)))
      (let ((entry (car received)))
        (should (equal "Stop" (nth 0 entry)))
        (should (equal "/tmp" (cdr (assq 'cwd (nth 1 entry)))))
        (should (equal "claude-1" (cdr (assq 'baton_session (nth 2 entry)))))))))

(ert-deftest monet-test-hook-dispatch-envelope-handler-error-isolated ()
  "A failing handler in monet--hook-dispatch-envelope does not block others."
  (monet-test-with-clean-hooks
    (let ((second-called nil))
      ;; Push in reverse order because monet-add-claude-hook-handler prepends
      (monet-add-claude-hook-handler
       (lambda (_e _d _c) (setq second-called t)))
      (monet-add-claude-hook-handler
       (lambda (_e _d _c) (error "intentional test error")))
      (monet--hook-dispatch-envelope
       '((hook_payload . ((hook_event_name . "Stop")))
         (monet_context . ())))
      (should second-called))))

;;; monet-claude-hook-receive (file-based, retained for compatibility)

(ert-deftest monet-test-claude-hook-receive-dispatches ()
  "monet-claude-hook-receive reads a JSON file and dispatches to handlers."
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

(ert-deftest monet-test-claude-hook-receive-missing-file ()
  "monet-claude-hook-receive silently returns when file does not exist."
  (monet-test-with-clean-hooks
    ;; Should not signal an error
    (should-not (monet-claude-hook-receive "/nonexistent/path/hook.json"))))

;;; HTTP hook server

(defun monet-test--http-post (port body-alist)
  "POST BODY-ALIST as JSON to the hook server at PORT.
Returns the HTTP status code, or nil on connection failure."
  (condition-case nil
      (let* ((body (encode-coding-string (json-encode body-alist) 'utf-8))
             (request (format (concat "POST /hook HTTP/1.1\r\n"
                                      "Host: 127.0.0.1\r\n"
                                      "Content-Type: application/json\r\n"
                                      "Content-Length: %d\r\n\r\n%s")
                              (length body) body))
             (status nil)
             (conn (make-network-process
                    :name "monet-hook-test-client"
                    :host "127.0.0.1"
                    :service port
                    :family 'ipv4
                    :coding 'no-conversion
                    :filter (lambda (_p data)
                              (when (string-match "HTTP/1\\.1 \\([0-9]+\\)" data)
                                (setq status (string-to-number (match-string 1 data))))))))
        (unwind-protect
            (progn
              (process-send-string conn request)
              (accept-process-output conn 2))
          (ignore-errors (delete-process conn)))
        status)
    (error nil)))

(ert-deftest monet-test-hook-http-dispatch ()
  "A valid POST to the HTTP hook server dispatches to registered handlers."
  (monet-test-with-clean-hooks
    (monet-test-with-hook-server
      (let ((received nil)
            (port monet--hook-port))
        (monet-add-claude-hook-handler
         (lambda (event data ctx) (push (list event data ctx) received)))
        (let ((status (monet-test--http-post
                       port
                       '((hook_payload . ((hook_event_name . "Stop") (cwd . "/tmp")))
                         (monet_context . ((baton_session . "s1")))))))
          (should (equal 200 status)))
        (should (= 1 (length received)))
        (let ((entry (car received)))
          (should (equal "Stop" (nth 0 entry)))
          (should (equal "/tmp" (cdr (assq 'cwd (nth 1 entry)))))
          (should (equal "s1" (cdr (assq 'baton_session (nth 2 entry))))))))))

(ert-deftest monet-test-hook-http-non-ascii-body ()
  "HTTP hook dispatch works correctly when the JSON body contains non-ASCII chars."
  (monet-test-with-clean-hooks
    (monet-test-with-hook-server
      (let ((received nil)
            (port monet--hook-port))
        (monet-add-claude-hook-handler
         (lambda (_event data _ctx) (push data received)))
        ;; Payload containing a non-ASCII Unicode string (é = U+00E9, 2 UTF-8 bytes)
        (let ((status (monet-test--http-post
                       port
                       '((hook_payload . ((hook_event_name . "Stop")
                                          (message . "café")))
                         (monet_context . ())))))
          (should (equal 200 status)))
        (should (= 1 (length received)))
        (should (equal "café" (cdr (assq 'message (car received)))))))))

(ert-deftest monet-test-hook-server-start-stop ()
  "monet--start-hook-server sets port; monet--stop-hook-server clears state."
  (let ((monet--hook-server nil)
        (monet--hook-port nil))
    (monet--start-hook-server)
    (should monet--hook-server)
    (should (integerp monet--hook-port))
    (monet--stop-hook-server)
    (should-not monet--hook-server)
    (should-not monet--hook-port)))

(ert-deftest monet-test-hook-server-start-idempotent ()
  "Calling monet--start-hook-server twice keeps the same server."
  (let ((monet--hook-server nil)
        (monet--hook-port nil))
    (monet--start-hook-server)
    (let ((first-server monet--hook-server)
          (first-port monet--hook-port))
      (monet--start-hook-server)
      (should (eq first-server monet--hook-server))
      (should (= first-port monet--hook-port)))
    (monet--stop-hook-server)))

;;; Hook settings install/remove

(defmacro monet-test-with-settings-sandbox (&rest body)
  "Run BODY with settings.json and the hooks dir redirected to a temp dir.
The temp directory is bound to `tmpdir' within BODY."
  (declare (indent 0))
  `(let ((tmpdir (make-temp-file "monet-settings-test-" t)))
     (ignore tmpdir)
     (unwind-protect
         (cl-letf (((symbol-function 'monet--claude-settings-path)
                    (lambda () (expand-file-name "settings.json" tmpdir)))
                   ((symbol-function 'monet--claude-hooks-dir)
                    (lambda () (expand-file-name "hooks/" tmpdir))))
           ,@body)
       (ignore-errors (delete-directory tmpdir t)))))

(ert-deftest monet-test-install-remove-claude-hooks ()
  "monet-install-claude-hooks writes entries; monet-remove-claude-hooks removes them.
The registered command is $HOME-relative so it resolves on the host and
inside sandbox guests alike (hook commands run through /bin/sh)."
  (monet-test-with-settings-sandbox
    ;; Install
    (monet-install-claude-hooks)
    (let* ((settings (json-read-file (monet--claude-settings-path)))
           (hooks (cdr (assq 'hooks settings))))
      (dolist (event '(Stop SubagentStop Notification UserPromptSubmit))
        (let* ((event-list (append (cdr (assq event hooks)) nil))
               (commands (mapcar #'monet--hook-entry-command event-list)))
          (should (member monet--claude-hook-command commands)))))
    ;; Remove
    (monet-remove-claude-hooks)
    (let* ((settings (json-read-file (monet--claude-settings-path)))
           (hooks (cdr (assq 'hooks settings))))
      (dolist (event '(Stop SubagentStop Notification UserPromptSubmit))
        (let* ((event-list (append (cdr (assq event hooks)) nil))
               (commands (mapcar #'monet--hook-entry-command event-list)))
          (should-not (member monet--claude-hook-command commands)))))))

(ert-deftest monet-test-install-claude-hooks-copies-script ()
  "monet-install-claude-hooks copies an executable hook script into hooks dir.
~/.claude is typically reachable inside sandbox guests (bind mount) while
the monet repo is not, so the script must live under ~/.claude."
  (monet-test-with-settings-sandbox
    (monet-install-claude-hooks)
    (let ((installed (expand-file-name "monet-claude-hook.py"
                                       (monet--claude-hooks-dir))))
      (should (file-exists-p installed))
      (should (file-executable-p installed)))))

(ert-deftest monet-test-install-claude-hooks-idempotent ()
  "monet-install-claude-hooks does not duplicate entries on repeated calls."
  (monet-test-with-settings-sandbox
    (monet-install-claude-hooks)
    (monet-install-claude-hooks)
    (let* ((settings (json-read-file (monet--claude-settings-path)))
           (hooks (cdr (assq 'hooks settings))))
      (dolist (event '(Stop SubagentStop Notification UserPromptSubmit))
        (let* ((event-list (append (cdr (assq event hooks)) nil))
               (commands (mapcar #'monet--hook-entry-command event-list)))
          (should (= 1 (cl-count monet--claude-hook-command commands
                                 :test #'equal))))))))

(ert-deftest monet-test-install-claude-hooks-preserves-other-entries ()
  "Install leaves non-monet hook entries untouched."
  (monet-test-with-settings-sandbox
    (monet--write-claude-settings
     `((hooks . ((Stop . [,(monet--hook-entry "/usr/bin/other-hook.sh")])))))
    (monet-install-claude-hooks)
    (let* ((settings (json-read-file (monet--claude-settings-path)))
           (hooks (cdr (assq 'hooks settings)))
           (stop-list (append (cdr (assq 'Stop hooks)) nil))
           (commands (mapcar #'monet--hook-entry-command stop-list)))
      (should (member "/usr/bin/other-hook.sh" commands))
      (should (member monet--claude-hook-command commands)))))

(provide 'test-hooks)
;;; tests/test-hooks.el ends here
