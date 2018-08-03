;;; cider-grimoire.el --- Grimoire integration -*- lexical-binding: t -*-

;; Copyright © 2014-2018 Bozhidar Batsov and CIDER contributors
;;
;; Author: Bozhidar Batsov <bozhidar@batsov.com>

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;; This file is not part of GNU Emacs.

;;; Commentary:

;; A few commands for Grimoire documentation lookup.

;;; Code:

(require 'cider-client)
(require 'cider-common)
(require 'subr-x)
(require 'cider-compat)
(require 'cider-popup)

(require 'nrepl-dict)

(require 'url-vars)

(declare-function markdown-mode "markdown-mode.el")
(declare-function markdown-toggle-fontify-code-blocks-natively "markdown-mode.el")

(defconst cider-grimoire-url "http://conj.io/")
(defconst cider-clojuredocs-url "http://clojuredocs.org/")

(defconst cider-grimoire-buffer "*cider-grimoire*")

(defcustom cider-online-search-provider 'grimoire
  "The search engine used by cider-grimoire.
conj.io and clojuredocs.org are supported."
  :type '(choice (const :tag "conj.io" grimoire)
                 (const :tag "clojuredocs.org" clojuredocs))
  :options (list cider-grimoire-url cider-clojuredocs-url)
  :group 'cider)

(defun cider-grimoire-replace-special (name)
  "Convert special symbols in NAME to a grimoire friendly format."
  (thread-last name
    (replace-regexp-in-string (rx "?") "_QMARK_")
    (replace-regexp-in-string (rx ".") "_DOT_")
    (replace-regexp-in-string "/" "_SLASH_")
    (replace-regexp-in-string (rx (or (group string-start "_")
                                      (group "_" string-end))) "")))

(defun cider-clojuredocs-replace-special (name)
  "Convert special symbols in NAME to a clojuredocs friendly format."
  (thread-last name
    (replace-regexp-in-string (rx "?") "_q")
    (replace-regexp-in-string (rx (group (1+ "."))) "_\\1")
    (replace-regexp-in-string (rx "/") "_fs")
    (replace-regexp-in-string (rx "_" string-end) "")))

(defun cider-grimoire-url (name ns)
  "Generate a grimoire search v0 url from NAME, NS."
  (let ((base-url cider-grimoire-url))
    (when (and name ns)
      (concat base-url  "search/v0/" ns "/" (cider-grimoire-replace-special name) "/"))))

(defun cider-clojuredocs-url (name ns)
  "Generate a clojuredocs search url from NAME, NS."
  (let ((base-url cider-clojuredocs-url))
    (when (and name ns)
      (concat base-url ns "/" (cider-clojuredocs-replace-special name)))))

(defun cider-search-provider-url (name ns)
  "Generates a search url for the configured search provider from NAME, NS."
  (pcase cider-online-search-provider
    ('grimoire (cider-grimoire-url name ns))
    ('clojuredocs (cider-clojuredocs-url name ns))
    (other (error "Unknown search provider specified: %s" other))))

(defun cider-grimoire-web-lookup (symbol)
  "Open the grimoire documentation for SYMBOL in a web browser."
  (if-let* ((var-info (cider-var-info symbol)))
      (let ((name (nrepl-dict-get var-info "name"))
            (ns (nrepl-dict-get var-info "ns")))
        (browse-url (cider-search-provider-url name ns)))
    (error "Symbol %s not resolved" symbol)))

;;;###autoload
(defun cider-grimoire-web (&optional arg)
  "Open grimoire documentation in the default web browser.

Prompts for the symbol to use, or uses the symbol at point, depending on
the value of `cider-prompt-for-symbol'.  With prefix arg ARG, does the
opposite of what that option dictates."
  (interactive "P")
  (funcall (cider-prompt-for-symbol-function arg)
           "Grimoire doc for"
           #'cider-grimoire-web-lookup))

(defun cider-create-grimoire-buffer (content)
  "Create a new grimoire buffer with CONTENT."
  (with-current-buffer (cider-popup-buffer cider-grimoire-buffer t)
    (read-only-mode -1)
    (insert content)
    (when (require 'markdown-mode nil 'noerror)
      (markdown-mode)
      (cider-popup-buffer-mode 1)
      (when (fboundp 'markdown-toggle-fontify-code-blocks-natively)
        (markdown-toggle-fontify-code-blocks-natively 1)))
    (view-mode 1)
    (goto-char (point-min))
    (current-buffer)))

(defun cider-grimoire-lookup (symbol)
  "Look up the grimoire documentation for SYMBOL.

If SYMBOL is a special form, the clojure.core ns is used, as is
Grimoire's convention."
  (if-let* ((var-info (cider-var-info symbol)))
      (let ((name (nrepl-dict-get var-info "name"))
            (ns (nrepl-dict-get var-info "ns" "clojure.core"))
            (url-request-method "GET")
            (url-request-extra-headers `(("Content-Type" . "text/plain"))))
        (url-retrieve (cider-search-provider-url name ns)
                      (lambda (_status)
                        ;; we need to strip the http header
                        (goto-char (point-min))
                        (re-search-forward "^$")
                        (delete-region (point-min) (point))
                        (delete-blank-lines)
                        ;; and create a new buffer with whatever is left
                        (pop-to-buffer (cider-create-grimoire-buffer (buffer-string))))))
    (error "Symbol %s not resolved" symbol)))

;;;###autoload
(defun cider-grimoire (&optional arg)
  "Open grimoire documentation in a popup buffer.

Prompts for the symbol to use, or uses the symbol at point, depending on
the value of `cider-prompt-for-symbol'.  With prefix arg ARG, does the
opposite of what that option dictates."
  (interactive "P")
  (when (derived-mode-p 'clojurescript-mode)
    (user-error "`cider-grimoire' doesn't support ClojureScript"))
  (funcall (cider-prompt-for-symbol-function arg)
           "Grimoire doc for"
           #'cider-grimoire-lookup))

(provide 'cider-grimoire)

;;; cider-grimoire.el ends here
