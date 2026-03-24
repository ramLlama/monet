;;; monet-emacs-tools.el --- Emacs introspection MCP tools for Monet  -*- lexical-binding: t -*-

;; Author: Ram Krishnaraj
;; Keywords: tools, ai

;;; Commentary:
;; Provides Emacs introspection tools (xref, imenu, treesit) as an opt-in
;; extension to Monet.  Tools are registered in the :introspection set, which
;; is disabled by default.
;;
;; To activate all introspection tools:
;;   (monet-register-emacs-tools)
;;   (monet-enable-tool-set :introspection)
;;
;; Or enable individual tools:
;;   (monet-register-emacs-tools)
;;   (monet-enable-tool "imenu_list_symbols")

;;; Code:
(require 'monet)
(require 'xref)
(require 'imenu)

;;; Helpers

(defun monet-emacs-tools--find-buffer (file-path)
  "Return a buffer visiting FILE-PATH, opening it if necessary.
Returns nil if FILE-PATH does not exist."
  (when (file-exists-p file-path)
    (find-file-noselect (expand-file-name file-path))))

(defun monet-emacs-tools--format-xref (item)
  "Format an xref ITEM as \"file:line: summary\"."
  (let* ((loc (xref-item-location item))
         (summary (xref-item-summary item)))
    (condition-case _
        (let* ((file (xref-location-group loc))
               (line (xref-location-line loc)))
          (format "%s:%d: %s" file line summary))
      (error summary))))

;;; xref tools

(defun monet-emacs-tools--xref-find (backend-fn identifier file-path)
  "Call BACKEND-FN with IDENTIFIER from the context of FILE-PATH.
Returns a list of MCP content objects."
  (let ((buf (monet-emacs-tools--find-buffer file-path)))
    (unless buf
      (error "File not found: %s" file-path))
    (with-current-buffer buf
      (let* ((backend (xref-find-backend))
             (xrefs (condition-case err
                        (funcall backend-fn backend identifier)
                      (error
                       (list (format "xref backend error: %s"
                                     (error-message-string err)))))))
        (if (null xrefs)
            (list `((type . "text") (text . "No results found.")))
          (list `((type . "text")
                  (text . ,(mapconcat
                            (lambda (item)
                              (if (stringp item)
                                  item
                                (monet-emacs-tools--format-xref item)))
                            xrefs "\n")))))))))

(defun monet-emacs-tools--make-xref-handler (backend-fn)
  "Return an MCP handler that calls BACKEND-FN via `monet-emacs-tools--xref-find'.
The returned handler reads :identifier and :file_path from params."
  (lambda (params _session)
    (let ((identifier (alist-get 'identifier params))
          (file-path (alist-get 'file_path params)))
      (condition-case err
          (monet-emacs-tools--xref-find backend-fn identifier file-path)
        (error
         (list `((type . "text")
                 (text . ,(format "Error: %s" (error-message-string err))))))))))

(defalias 'monet-emacs-tools--xref-find-references-handler
  (monet-emacs-tools--make-xref-handler #'xref-backend-references)
  "MCP handler for xref_find_references.
PARAMS contains identifier and file_path.")

(defalias 'monet-emacs-tools--xref-find-definitions-handler
  (monet-emacs-tools--make-xref-handler #'xref-backend-definitions)
  "MCP handler for xref_find_definitions.
PARAMS contains identifier and file_path.")

(defun monet-emacs-tools--xref-find-apropos-handler (params _session)
  "MCP handler for xref_find_apropos.
PARAMS contains pattern and file_path.
_SESSION is unused."
  (let ((pattern (alist-get 'pattern params))
        (file-path (alist-get 'file_path params)))
    (condition-case err
        (let ((buf (monet-emacs-tools--find-buffer file-path)))
          (unless buf
            (error "File not found: %s" file-path))
          (with-current-buffer buf
            (let* ((backend (xref-find-backend))
                   ;; Check for etags without a loaded tags table
                   (is-etags (eq backend 'etags))
                   (tags-ok (or (not is-etags)
                                (condition-case nil
                                    (progn (tags-table-check-computed-list) t)
                                  (error nil)))))
              (if (not tags-ok)
                  (list `((type . "text")
                          (text . "No tags table loaded. Run M-x visit-tags-table first.")))
                (let ((xrefs (condition-case err2
                                 (xref-backend-apropos backend pattern)
                               (error
                                (list (format "xref apropos error: %s"
                                              (error-message-string err2)))))))
                  (if (null xrefs)
                      (list `((type . "text") (text . "No results found.")))
                    (list `((type . "text")
                            (text . ,(mapconcat
                                      (lambda (item)
                                        (if (stringp item)
                                            item
                                          (monet-emacs-tools--format-xref item)))
                                      xrefs "\n"))))))))))
      (error
       (list `((type . "text")
               (text . ,(format "Error: %s" (error-message-string err)))))))))

;;; imenu tool

(defun monet-emacs-tools--format-imenu-entry (entry file prefix)
  "Format a single imenu ENTRY for FILE with category PREFIX.
Returns a list of formatted strings."
  (let ((name (car entry))
        (val (cdr entry)))
    (cond
     ;; Skip internal imenu entries
     ((string-prefix-p "*" name) nil)
     ;; Nested category: (category-name . items-alist)
     ((and (listp val) (listp (car val)))
      (let ((category (if (string= prefix "") name
                        (concat prefix "/" name))))
        (mapcan (lambda (sub)
                  (monet-emacs-tools--format-imenu-entry sub file category))
                val)))
     ;; Marker entry: (name . marker)
     ((markerp val)
      (let ((line (with-current-buffer (marker-buffer val)
                    (line-number-at-pos (marker-position val)))))
        (list (format "%s:%d: %s%s" file line
                      (if (string= prefix "") "" (concat "[" prefix "] "))
                      name))))
     ;; Number entry: (name . position)
     ((numberp val)
      (with-current-buffer (find-file-noselect file)
        (let ((line (line-number-at-pos val)))
          (list (format "%s:%d: %s%s" file line
                        (if (string= prefix "") "" (concat "[" prefix "] "))
                        name)))))
     (t nil))))

(defun monet-emacs-tools--imenu-list-symbols-handler (params _session)
  "MCP handler for imenu_list_symbols.
PARAMS contains file_path.
_SESSION is unused."
  (let ((file-path (alist-get 'file_path params)))
    (condition-case err
        (let ((buf (monet-emacs-tools--find-buffer file-path)))
          (unless buf
            (error "File not found: %s" file-path))
          (with-current-buffer buf
            (let* ((index (condition-case err2
                              (imenu--make-index-alist t)
                            (error
                             (error "imenu error: %s" (error-message-string err2)))))
                   (entries (mapcan (lambda (entry)
                                      (monet-emacs-tools--format-imenu-entry
                                       entry (buffer-file-name buf) ""))
                                    index)))
              (if (null entries)
                  (list `((type . "text") (text . "No symbols found.")))
                (list `((type . "text")
                        (text . ,(mapconcat #'identity entries "\n"))))))))
      (error
       (list `((type . "text")
               (text . ,(format "Error: %s" (error-message-string err)))))))))

;;; treesit tool

(defun monet-emacs-tools--treesit-node-info (node file)
  "Return a string describing treesit NODE in FILE."
  (let* ((start-pos (treesit-node-start node))
         (end-pos (treesit-node-end node))
         (text (let ((raw (treesit-node-text node)))
                 (if (> (length raw) 80)
                     (concat (substring raw 0 80) "…")
                   raw)))
         (start-line (line-number-at-pos start-pos))
         (end-line (line-number-at-pos end-pos))
         (field (treesit-node-field-name node)))
    (format "%s:%d-%d  type=%s  named=%s%s\n  text: %s"
            file start-line end-line
            (treesit-node-type node)
            (if (treesit-node-check node 'named) "t" "nil")
            (if field (format "  field=%s" field) "")
            text)))

(defun monet-emacs-tools--treesit-dump-tree (node depth max-depth)
  "Recursively dump NODE up to MAX-DEPTH levels, starting at DEPTH.
Returns a list of strings."
  (when (<= depth max-depth)
    (let* ((indent (make-string (* depth 2) ?\s))
           (field (treesit-node-field-name node))
           (text-preview
            (when (treesit-node-check node 'leaf)
              (let ((raw (treesit-node-text node)))
                (concat " " (if (> (length raw) 40)
                                (concat (substring raw 0 40) "…")
                              raw))))))
      (cons (format "%s(%s%s%s)"
                    indent
                    (treesit-node-type node)
                    (if field (format " [%s]" field) "")
                    (or text-preview ""))
            (when (< depth max-depth)
              (let ((children '()))
                (dotimes (i (min 20 (treesit-node-child-count node)))
                  (let ((child (treesit-node-child node i)))
                    (when child
                      (setq children
                            (append children
                                    (monet-emacs-tools--treesit-dump-tree
                                     child (1+ depth) max-depth))))))
                children))))))

(defun monet-emacs-tools--treesit-info-handler (params _session)
  "MCP handler for treesit_info.
PARAMS may contain: file_path, line (optional), column (optional),
whole_file (optional bool), include_ancestors (optional bool),
include_children (optional bool).
_SESSION is unused."
  (let ((file-path (alist-get 'file_path params))
        (line (alist-get 'line params))
        (column (alist-get 'column params))
        (whole-file (alist-get 'whole_file params))
        (include-ancestors (alist-get 'include_ancestors params))
        (include-children (alist-get 'include_children params)))
    (condition-case err
        (progn
          (unless (treesit-available-p)
            (error "Tree-sitter is not available in this Emacs build"))
          (let ((buf (monet-emacs-tools--find-buffer file-path)))
            (unless buf
              (error "File not found: %s" file-path))
            (with-current-buffer buf
              (unless (treesit-parser-list)
                (error "No tree-sitter parser active for %s" file-path))
              (let ((file (buffer-file-name buf)))
                (if whole-file
                    ;; Dump the entire syntax tree
                    (let* ((root (treesit-buffer-root-node))
                           (lines (monet-emacs-tools--treesit-dump-tree
                                   root 0 20)))
                      (list `((type . "text")
                              (text . ,(mapconcat #'identity lines "\n")))))
                  ;; Point-based info
                  (let* ((pos (save-excursion
                                (goto-char (point-min))
                                (when line
                                  (forward-line (1- line)))
                                (when column
                                  (move-to-column column))
                                (point)))
                         (node (treesit-node-at pos))
                         (parts (list (monet-emacs-tools--treesit-node-info
                                       node file))))
                    ;; Ancestors
                    (when include-ancestors
                      (let ((parent (treesit-node-parent node))
                            (levels 0))
                        (while (and parent (< levels 10))
                          (setq parts
                                (append parts
                                        (list (concat "\nAncestor: "
                                                      (monet-emacs-tools--treesit-node-info
                                                       parent file)))))
                          (setq parent (treesit-node-parent parent))
                          (setq levels (1+ levels)))))
                    ;; Children
                    (when include-children
                      (dotimes (i (min 20 (treesit-node-child-count node)))
                        (let ((child (treesit-node-child node i)))
                          (when child
                            (setq parts
                                  (append parts
                                          (list (concat "\nChild: "
                                                        (monet-emacs-tools--treesit-node-info
                                                         child file)))))))))
                    (list `((type . "text")
                            (text . ,(mapconcat #'identity parts "\n"))))))))))
      (error
       (list `((type . "text")
               (text . ,(format "Error: %s" (error-message-string err)))))))))

;;; Registration

;;;###autoload
(defun monet-register-emacs-tools ()
  "Register Emacs introspection tools in the :introspection set.
Tools are disabled by default; activate with:
  (monet-enable-tool-set :introspection)
or enable individual tools with `monet-enable-tool'."
  (interactive)
  (monet-make-tool
   :name "xref_find_references"
   :description "Find all references to a symbol using xref."
   :schema '((type . "object")
             (properties . ((identifier . ((type . "string")
                                           (description . "Symbol to find references for")))
                            (file_path . ((type . "string")
                                         (description . "File to establish xref context")))))
             (required . ["identifier" "file_path"]))
   :handler #'monet-emacs-tools--xref-find-references-handler
   :set :introspection)
  (monet-make-tool
   :name "xref_find_definitions"
   :description "Find the definition of a symbol using xref."
   :schema '((type . "object")
             (properties . ((identifier . ((type . "string")
                                           (description . "Symbol to find definition of")))
                            (file_path . ((type . "string")
                                         (description . "File to establish xref context")))))
             (required . ["identifier" "file_path"]))
   :handler #'monet-emacs-tools--xref-find-definitions-handler
   :set :introspection)
  (monet-make-tool
   :name "xref_find_apropos"
   :description "Search for symbols matching a pattern using xref apropos."
   :schema '((type . "object")
             (properties . ((pattern . ((type . "string")
                                        (description . "Pattern to search for")))
                            (file_path . ((type . "string")
                                         (description . "File to establish xref context")))))
             (required . ["pattern" "file_path"]))
   :handler #'monet-emacs-tools--xref-find-apropos-handler
   :set :introspection)
  (monet-make-tool
   :name "imenu_list_symbols"
   :description "List all symbols in a file using imenu."
   :schema '((type . "object")
             (properties . ((file_path . ((type . "string")
                                          (description . "File to list symbols from")))))
             (required . ["file_path"]))
   :handler #'monet-emacs-tools--imenu-list-symbols-handler
   :set :introspection)
  (monet-make-tool
   :name "treesit_info"
   :description (concat "Get tree-sitter syntax tree information for a file or point. "
                        "Requires tree-sitter support in Emacs 29+.")
   :schema '((type . "object")
             (properties . ((file_path . ((type . "string")
                                          (description . "File to inspect")))
                            (line . ((type . "integer")
                                     (description . "1-based line number (omit for whole_file)")))
                            (column . ((type . "integer")
                                       (description . "0-based column number")))
                            (whole_file . ((type . "boolean")
                                           (description . "Dump the entire syntax tree")))
                            (include_ancestors . ((type . "boolean")
                                                  (description . "Include ancestor nodes")))
                            (include_children . ((type . "boolean")
                                                 (description . "Include child nodes")))))
             (required . ["file_path"]))
   :handler #'monet-emacs-tools--treesit-info-handler
   :set :introspection))

(provide 'monet-emacs-tools)
;;; monet-emacs-tools.el ends here
