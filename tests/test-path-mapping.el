;;; tests/test-path-mapping.el --- Guest/host path mapping tests  -*- lexical-binding: t -*-

;;; Code:
(require 'ert)
(require 'monet)
(require 'test-helpers)

(defconst monet-test--mappings
  '(("/var/folders/x/ws/feat" . "/workspace"))
  "Host worktree mapped to the guest mount point.")

(defun monet-test--mapped-session ()
  "Return a session carrying `monet-test--mappings'."
  (make-monet--session :key "k" :port 1
                       :directory "/var/folders/x/ws/feat"
                       :path-mappings monet-test--mappings))

;;; monet--translate-path

(ert-deftest monet-test-translate-path-to-host ()
  "Guest paths rewrite to host paths, including the bare prefix."
  (should (equal (monet--translate-path monet-test--mappings 'to-host
                                        "/workspace/src/a.el")
                 "/var/folders/x/ws/feat/src/a.el"))
  (should (equal (monet--translate-path monet-test--mappings 'to-host
                                        "/workspace")
                 "/var/folders/x/ws/feat")))

(ert-deftest monet-test-translate-path-to-guest ()
  "Host paths rewrite to guest paths."
  (should (equal (monet--translate-path monet-test--mappings 'to-guest
                                        "/var/folders/x/ws/feat/src/a.el")
                 "/workspace/src/a.el")))

(ert-deftest monet-test-translate-path-respects-boundaries ()
  "A prefix only matches at a path-segment boundary."
  (should (equal (monet--translate-path monet-test--mappings 'to-guest
                                        "/var/folders/x/ws/feat-other/a.el")
                 "/var/folders/x/ws/feat-other/a.el")))

(ert-deftest monet-test-translate-path-file-uri ()
  "file:// URIs are translated on their path part."
  (should (equal (monet--translate-path monet-test--mappings 'to-guest
                                        "file:///var/folders/x/ws/feat/a.el")
                 "file:///workspace/a.el"))
  (should (equal (monet--translate-path monet-test--mappings 'to-host
                                        "file:///workspace/a.el")
                 "file:///var/folders/x/ws/feat/a.el")))

(ert-deftest monet-test-translate-path-no-match-identity ()
  "Unmapped paths pass through unchanged."
  (should (equal (monet--translate-path monet-test--mappings 'to-host
                                        "/etc/hosts")
                 "/etc/hosts")))

;;; monet--translate-paths (deep walk over protocol payloads)

(ert-deftest monet-test-translate-paths-tool-args ()
  "openDiff-style arguments translate path keys but never content."
  (let* ((session (monet-test--mapped-session))
         (args '((old_file_path . "/workspace/a.el")
                 (new_file_path . "/workspace/a.el")
                 (new_file_contents . ";; see /workspace/a.el\n(code)")
                 (tab_name . "diff a.el")))
         (translated (monet--translate-paths session 'to-host args)))
    (should (equal (alist-get 'old_file_path translated)
                   "/var/folders/x/ws/feat/a.el"))
    (should (equal (alist-get 'new_file_path translated)
                   "/var/folders/x/ws/feat/a.el"))
    ;; Contents are data, not paths — must remain verbatim.
    (should (equal (alist-get 'new_file_contents translated)
                   ";; see /workspace/a.el\n(code)"))
    (should (equal (alist-get 'tab_name translated) "diff a.el"))))

(ert-deftest monet-test-translate-paths-nested-and-vectors ()
  "The walk descends into nested alists and vectors (uri keys, folder lists)."
  (let* ((session (monet-test--mapped-session))
         (payload `((content . [((uri . "file:///var/folders/x/ws/feat/a.el")
                                 (text . "x"))])
                    (workspaceFolders . ["/var/folders/x/ws/feat"])))
         (translated (monet--translate-paths session 'to-guest payload)))
    (should (equal (alist-get 'uri (elt (alist-get 'content translated) 0))
                   "file:///workspace/a.el"))
    (should (equal (append (alist-get 'workspaceFolders translated) nil)
                   '("/workspace")))))

(ert-deftest monet-test-translate-paths-identity-without-mappings ()
  "Sessions without mappings return payloads untouched (eq, no copy)."
  (let ((session (make-monet--session :key "k" :port 1))
        (payload '((filePath . "/var/folders/x/ws/feat/a.el"))))
    (should (eq (monet--translate-paths session 'to-host payload) payload))))

;;; End-to-end through the dispatch choke points

(ert-deftest monet-test-tools-call-receives-host-paths ()
  "Tool handlers see host paths when the session has mappings."
  (monet-test-with-clean-registry
    (let (seen-args)
      (monet-make-tool :name "probe"
                       :description "capture args"
                       :schema '((type . "object"))
                       :handler (lambda (args _session)
                                  (setq seen-args args)
                                  []))
      (monet-enable-tool "probe")
      (cl-letf (((symbol-function 'monet--send-response) #'ignore))
        (monet--handle-tools-call
         (monet-test--mapped-session) nil 1
         ;; What `monet--on-message' passes after inbound translation
         ;; of the full params:
         (monet--translate-paths (monet-test--mapped-session) 'to-host
                                 '((name . "probe")
                                   (arguments . ((uri . "/workspace/a.el")))))))
      (should (equal (alist-get 'uri seen-args)
                     "/var/folders/x/ws/feat/a.el")))))

(ert-deftest monet-test-send-notification-emits-guest-paths ()
  "Outbound notifications translate host paths to guest paths."
  (let* ((session (monet-test--mapped-session))
         (sent nil))
    (setf (monet--session-initialized session) t)
    (cl-letf (((symbol-function 'monet--find-session-by-client)
               (lambda (_client) session))
              ((symbol-function 'websocket-send-text)
               (lambda (_ws text) (setq sent text))))
      (monet--send-notification
       'fake-client "selection_changed"
       '((filePath . "/var/folders/x/ws/feat/a.el") (text . "x")))
      (should (string-match-p "/workspace/a\\.el" sent))
      (should-not (string-match-p "/var/folders" sent)))))

;;; Lockfile + server-start integration

(ert-deftest monet-test-start-server-lockfile-lists-guest-folder ()
  "Server start derives guest workspaceFolders from the path mappings."
  (let ((lockdir (make-temp-file "monet-pm-lock-" t))
        (monet--sessions (make-hash-table :test 'equal)))
    (unwind-protect
        (cl-letf (((symbol-function 'monet--get-lockfile-dir) (lambda () lockdir))
                  ((symbol-function 'monet--find-free-port) (lambda () 12345))
                  ((symbol-function 'websocket-server)
                   (lambda (&rest _args) 'fake-server))
                  ((symbol-function 'monet-register-hooks) #'ignore))
          (monet-start-server-in-directory "k" "/var/folders/x/ws/feat"
                                           monet-test--mappings)
          (let* ((json (json-read-file (expand-file-name "12345.lock" lockdir)))
                 (folders (append (cdr (assq 'workspaceFolders json)) nil)))
            (should (equal folders '("/var/folders/x/ws/feat" "/workspace")))))
      (ignore-errors (delete-directory lockdir t)))))

(provide 'test-path-mapping)
;;; tests/test-path-mapping.el ends here
