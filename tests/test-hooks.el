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

(provide 'test-hooks)
;;; tests/test-hooks.el ends here
