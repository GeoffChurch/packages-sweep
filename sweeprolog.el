;;; sweeprolog.el --- Embedded SWI-Prolog -*- lexical-binding:t -*-

;; Copyright (C) 2022 Eshel Yaron

;; Author: Eshel Yaron <me@eshelyaron.com>
;; Maintainer: Eshel Yaron <~eshel/dev@lists.sr.ht>
;; Keywords: prolog languages extensions
;; URL: https://git.sr.ht/~eshel/sweep
;; Package-Version: 0.6.0
;; Package-Requires: ((emacs "28"))

;; This file is NOT part of GNU Emacs.

;;; Commentary:

;; sweep is an embedding of SWI-Prolog in Emacs.  It uses the C
;; interfaces of both SWI-Prolog and Emacs Lisp to create a
;; dynamically loaded Emacs module that contains the SWI-Prolog
;; runtime.  sweep provides an interface for interacting with the
;; embedded Prolog via a set of Elisp functions, as well as user
;; facing modes and commands for writing and running Prolog within
;; Emacs.
;;
;; For more information, see the sweep manual at
;; <https://eshelyaron.com/sweep.html>.  The manual can also be read
;; locally by evaluating (info "(sweep) Top")

;;; Code:

(require 'comint)
(require 'xref)
(require 'autoinsert)
(require 'eldoc)
(require 'flymake)

(defgroup sweeprolog nil
  "SWI-Prolog Embedded in Emacs."
  :group 'prolog)

(defcustom sweeprolog-module-header-comment-skeleton ?\n
  "Additional content for the topmost comment in module headers.

The SWI-Prolog module header inserted by \\[auto-insert] includes
a multiline comment at the very start of the buffer which
contains the name and mail address of the author based on the
user options `user-full-name' and `user-mail-address'
respectively, followed by the value of this variable, is
interpreted as a skeleton (see `skeleton-insert').  In its
simplest form, this may be a string or a character.

This user option may be useful, for example, to include copyright
notices with the module header."
  :package-version '((sweeprolog . "0.4.6"))
  :type 'any
  :group 'sweeprolog)

(defcustom sweeprolog-indent-offset 4
  "Number of columns to indent lines with in `sweeprolog-mode' buffers."
  :package-version '((sweeprolog . "0.3.1"))
  :type 'integer
  :group 'sweeprolog)

(defcustom sweeprolog-qq-mode-alist '(("graphql"    . graphql-mode)
                                      ("javascript" . js-mode)
                                      ("html"       . html-mode))
  "Association between Prolog quasi-quotation types and Emacs modes.

This is a list of pairs of the form (TYPE . MODE), where TYPE is
a Prolog quasi-quotation type given as a string, and MODE is a
symbol specifing a major mode."
  :package-version '((sweeprolog . "0.4.3"))
  :type '(alist :key-type string :value-type symbol)
  :group 'sweeprolog)

(defcustom sweeprolog-enable-cycle-spacing t
  "If non-nil and `cycle-spacing-actions' is defined, extend it.

This makes the first invocation of \\[cycle-spacing] in
`sweeprolog-mode' buffers update whitespace around point using
`sweeprolog-align-spaces', which see."
  :package-version '((sweeprolog . "0.5.3"))
  :type 'boolean
  :group 'sweeprolog)

(defcustom sweeprolog-colourise-buffer-on-idle t
  "If non-nil, update highlighting of `sweeprolog-mode' buffers on idle."
  :package-version '((sweeprolog . "0.2.0"))
  :type 'boolean
  :group 'sweeprolog)

(defcustom sweeprolog-colourise-buffer-max-size 100000
  "Maximum buffer size to recolourise on idle."
  :package-version '((sweeprolog . "0.2.0"))
  :type 'integer
  :group 'sweeprolog)

(defcustom sweeprolog-colourise-buffer-min-interval 2
  "Minimum idle time to wait before recolourising the buffer."
  :package-version '((sweeprolog . "0.2.0"))
  :type 'float
  :group 'sweeprolog)

(defcustom sweeprolog-swipl-path nil
  "Path to the swipl executable.
When non-nil, this is used by the embedded SWI-Prolog runtime to
locate its \"home\" directory.  Otherwise, `executable-find' is
used to find the swipl executable."
  :package-version '((sweeprolog . "0.1.1"))
  :type 'string
  :group 'sweeprolog)

(defcustom sweeprolog-libswipl-path nil
  "Path to the libswipl shared object.
On Linux and other ELF-based platforms, `sweep' first loads
libswipl before loading `sweep-module'.  When this option is
nil (the default), libswipl is located automatically, otherwise
the value of this option is used as its path."
  :package-version '((sweeprolog . "0.6.1"))
  :type 'string
  :group 'sweeprolog)

(defcustom sweeprolog-messages-buffer-name "*sweep Messages*"
  "The name of the buffer to use for logging Prolog messages."
  :package-version '((sweeprolog . "0.1.1"))
  :type 'string
  :group 'sweeprolog)

(defcustom sweeprolog-read-flag-prompt "Flag: "
  "Prompt used for reading a Prolog flag name from the minibuffer."
  :package-version '((sweeprolog . "0.1.2"))
  :type 'string
  :group 'sweeprolog)

(defcustom sweeprolog-read-module-prompt "Module: "
  "Prompt used for reading a Prolog module name from the minibuffer."
  :package-version '((sweeprolog . "0.1.0"))
  :type 'string
  :group 'sweeprolog)

(defcustom sweeprolog-read-predicate-prompt "Predicate: "
  "Prompt used for reading a Prolog precicate name from the minibuffer."
  :package-version '((sweeprolog . "0.1.0"))
  :type 'string
  :group 'sweeprolog)

(defcustom sweeprolog-read-pack-prompt "Pack: "
  "Prompt used for reading a Prolog pack name from the minibuffer."
  :package-version '((sweeprolog . "0.1.0"))
  :type 'string
  :group 'sweeprolog)

(defcustom sweeprolog-top-level-display-action nil
  "Display action used for displaying the `sweeprolog-top-level' buffer."
  :package-version '((sweeprolog . "0.1.0"))
  :type 'function
  :group 'sweeprolog)

(defcustom sweeprolog-top-level-min-history-length 3
  "Minimum input length to record in the `sweeprolog-top-level' history.

Inputs shorther than the value of this variable will not be
inserted to the input history in `sweeprolog-top-level-mode' buffers."
  :package-version '((sweeprolog . "0.2.1"))
  :type 'string
  :group 'sweeprolog)

(defcustom sweeprolog-init-on-load t
  "If non-nil, initialize Prolog when `sweeprolog' is loaded."
  :package-version '((sweeprolog "0.1.0"))
  :type 'boolean
  :group 'sweeprolog)

(defcustom sweeprolog-init-args (list "-q"
                                      "--no-signals"
                                      (expand-file-name
                                       "sweep.pl"
                                       (file-name-directory load-file-name)))
  "List of strings used as initialization arguments for Prolog."
  :package-version '((sweeprolog "0.5.2"))
  :type '(repeat string)
  :group 'sweeprolog)

(defcustom sweeprolog-enable-flymake t
  "If non-nil, enable `flymake' suport in `sweeprolog-mode' buffers."
  :package-version '((sweeprolog "0.6.0"))
  :type 'boolean
  :group 'sweeprolog)

(defcustom sweeprolog-enable-eldoc t
  "If non-nil, enable `eldoc' suport in `sweeprolog-mode' buffers."
  :package-version '((sweeprolog "0.4.7"))
  :type 'boolean
  :group 'sweeprolog)

(defcustom sweeprolog-enable-cursor-sensor t
  "If non-nil, enable `cursor-sensor-mode' in `sweeprolog-mode'.

When enabled, `sweeprolog-mode' leverages `cursor-sensor-mode' to
highlight all occurences of the variable at point in the current
clause."
  :package-version '((sweeprolog "0.4.2"))
  :type 'boolean
  :group 'sweeprolog)

(defvar sweeprolog-prolog-server-port nil)

(declare-function sweeprolog-initialize    "sweep-module")
(declare-function sweeprolog-initialized-p "sweep-module")
(declare-function sweeprolog-open-query    "sweep-module")
(declare-function sweeprolog-next-solution "sweep-module")
(declare-function sweeprolog-cut-query     "sweep-module")
(declare-function sweeprolog-close-query   "sweep-module")
(declare-function sweeprolog-cleanup       "sweep-module")

(defun sweeprolog--ensure-module ()
  "Locate and load `sweep-module', unless already loaded."
  (unless (featurep 'sweep-module)
    (when-let ((exec-format (car
                             (save-match-data
                               (split-string
                                (shell-command-to-string
                                 (concat
                                  (shell-quote-argument
                                   (or sweeprolog-swipl-path (executable-find "swipl")))
                                  " -q"
                                  " -g 'current_prolog_flag(executable_format, X), writeln(X)'"
                                  " -t halt"))
                                "\n"
                                t)))))
      (let ((libswipl-path (or sweeprolog-libswipl-path
                               (car
                                (save-match-data
                                  (split-string
                                   (shell-command-to-string
                                    (concat
                                     (shell-quote-argument
                                      (or sweeprolog-swipl-path (executable-find "swipl")))
                                     " -q"
                                     " -g 'current_prolog_flag(libswipl, X), writeln(X)'"
                                     " -t halt"))
                                   "\n"))))))
        (condition-case _
            (load libswipl-path)
          (file-error (user-error
                       (concat "Failed to load `libswipl'. "
                               "Make sure SWI-Prolog is installed "
                               "and up to date"))))))
    (let ((sweep-module-path (car
                              (save-match-data
                                (split-string
                                 (shell-command-to-string
                                  (concat
                                   (shell-quote-argument
                                    (or sweeprolog-swipl-path (executable-find "swipl")))
                                   " -g write_sweep_module_location"
                                   " -t halt "
                                   (shell-quote-argument
                                    (expand-file-name
                                     "sweep.pl"
                                     (file-name-directory load-file-name)))))
                                 "\n")))))
      (condition-case _
          (load sweep-module-path)
        (file-error (user-error
                     (concat "Failed to locate `sweep-module'. "
                             "Make sure SWI-Prolog is installed "
                             "and up to date")))))))

(defface sweeprolog-debug-prefix-face
  '((default :inherit shadow))
  "Face used to highlight the \"DEBUG\" message prefix."
  :group 'sweeprolog-faces)

(defvar sweeprolog-debug-prefix-face 'sweeprolog-debug-prefix-face
  "Name of the face used to highlight the \"DEBUG\" message prefix.")

(defface sweeprolog-debug-topic-face
  '((default :inherit shadow))
  "Face used to highlight the topic in debug messages."
  :group 'sweeprolog-faces)

(defvar sweeprolog-debug-topic-face 'sweeprolog-debug-topic-face
  "Name of the face used to highlight the topic in debug messages.")

(defface sweeprolog-info-prefix-face
  '((default :inherit default))
  "Face used to highlight the \"INFO\" message prefix."
  :group 'sweeprolog-faces)

(defvar sweeprolog-info-prefix-face 'sweeprolog-info-prefix-face
  "Name of the face used to highlight the \"INFO\" message prefix.")

(defface sweeprolog-warning-prefix-face
  '((default :inherit font-lock-warning-face))
  "Face used to highlight the \"WARNING\" message prefix."
  :group 'sweeprolog-faces)

(defvar sweeprolog-warning-prefix-face 'sweeprolog-warning-prefix-face
  "Name of the face used to highlight the \"WARNING\" message prefix.")

(defface sweeprolog-error-prefix-face
  '((default :inherit error))
  "Face used to highlight the \"ERROR\" message prefix."
  :group 'sweeprolog-faces)

(defvar sweeprolog-error-prefix-face 'sweeprolog-error-prefix-face
  "Name of the face used to highlight the \"ERROR\" message prefix.")

(defun sweeprolog-view-messages ()
  "View the log of recent Prolog messages."
  (interactive)
  (with-current-buffer (get-buffer-create sweeprolog-messages-buffer-name)
    (goto-char (point-max))
    (let ((win (display-buffer (current-buffer))))
      (set-window-point win (point))
      win)))

(defun sweeprolog-current-prolog-flags (&optional prefix)
  "Return the list of defined Prolog flags defined with prefix PREFIX."
  (sweeprolog-open-query "user" "sweep" "sweep_current_prolog_flags" (or prefix ""))
  (let ((sol (sweeprolog-next-solution)))
    (sweeprolog-close-query)
    (when (sweeprolog-true-p sol)
      (cdr sol))))

(defun sweeprolog-read-prolog-flag ()
  "Read a Prolog flag from the minibuffer, with completion."
  (let* ((col (sweeprolog-current-prolog-flags))
         (completion-extra-properties
          (list :annotation-function
                (lambda (key)
                  (let* ((val (cdr (assoc-string key col))))
                    (if val
                        (concat (make-string
                                 (max (- 32 (length key)) 1) ? )
                                val)
                      nil))))))
    (completing-read sweeprolog-read-flag-prompt col)))

(defun sweeprolog-set-prolog-flag (flag value)
  "Set the Prolog flag FLAG to VALUE.
FLAG and VALUE are specified as strings and read as Prolog terms."
  (interactive (let ((f (sweeprolog-read-prolog-flag)))
                 (list f (read-string (concat "Set " f " to: ")))))
  (sweeprolog-open-query "user"
                    "sweep"
                    "sweep_set_prolog_flag"
                    (cons flag value))
  (let ((sol (sweeprolog-next-solution)))
    (sweeprolog-close-query)
    (if (sweeprolog-true-p sol)
        (message "Prolog flag %s set to %s" flag value)
      (user-error "Setting %s to %s failed!" flag value))))

(defun sweeprolog-setup-message-hook ()
  "Setup `thread_message_hook/3' to redirecet Prolog messages."
  (with-current-buffer (get-buffer-create sweeprolog-messages-buffer-name)
    (setq-local window-point-insertion-type t)
    (compilation-minor-mode 1))
  (sweeprolog-open-query "user"
                         "sweep"
                         "sweep_setup_message_hook"
                         nil)
  (let ((sol (sweeprolog-next-solution)))
    (sweeprolog-close-query)
    sol))

(defun sweeprolog-message (message)
  "Emit the Prolog message MESSAGE to the `sweep' messages buffer."
  (with-current-buffer (get-buffer-create sweeprolog-messages-buffer-name)
    (save-excursion
      (goto-char (point-max))
      (let ((kind (car message))
            (content (cdr message)))
        (pcase kind
          (`("debug" . ,topic)
           (insert (propertize "DEBUG" 'face sweeprolog-debug-prefix-face))
           (insert "[")
           (insert (propertize topic 'face sweeprolog-debug-topic-face))
           (insert "]: ")
           (insert content))
          ("informational"
           (insert (propertize "INFO" 'face sweeprolog-info-prefix-face))
           (insert ": ")
           (insert content))
          ("warning"
           (insert (propertize "WARNING" 'face sweeprolog-warning-prefix-face))
           (insert ": ")
           (insert content))
          ("error"
           (insert (propertize "ERROR" 'face sweeprolog-error-prefix-face))
           (insert ": ")
           (insert content))))
      (newline))))

(defun sweeprolog-start-prolog-server ()
  "Start the `sweep' Prolog top-level embedded server."
  (sweeprolog-open-query "user"
                         "sweep"
                         "sweep_top_level_server"
                         nil)
  (let ((sol (sweeprolog-next-solution)))
    (sweeprolog-close-query)
    (when (sweeprolog-true-p sol)
      (setq sweeprolog-prolog-server-port (cdr sol)))))

(defun sweeprolog-init (&rest args)
  "Initialize and setup the embedded Prolog runtime.

If specified, ARGS should be a list of string passed to Prolog as
extra initialization arguments."
  (apply #'sweeprolog-initialize
         (cons (or sweeprolog-swipl-path (executable-find "swipl"))
               (append sweeprolog-init-args args)))
  (sweeprolog-setup-message-hook)
  (sweeprolog-start-prolog-server))

(defun sweeprolog-restart (&rest args)
  "Restart the embedded Prolog runtime.

ARGS is a list of strings appended to the value of
`sweeprolog-init-args' to produce the Prolog initialization
arguments.

Interactively, with a prefix arguments, prompt for ARGS.
Otherwise set ARGS to nil."
  (interactive
   (and
    current-prefix-arg
    (split-string-shell-command (read-string "swipl arguments: "))))
  (when-let ((top-levels (seq-filter (lambda (buffer)
                                       (eq 'sweeprolog-top-level-mode
                                           (buffer-local-value 'major-mode
                                                               buffer)))
                                     (buffer-list))))
    (if (y-or-n-p "Stop running sweep top-level processes?")
        (dolist (buffer top-levels)
          (let ((process (get-buffer-process buffer)))
            (when (process-live-p process)
              (delete-process process))))
      (user-error "Cannot restart sweep with running top-level processes")))
  (message "Stoping sweep.")
  (sweeprolog-cleanup)
  (message "Starting sweep.")
  (apply #'sweeprolog-init args))

(defvar sweeprolog-predicate-completion-collection nil)

(defvar-local sweeprolog-buffer-module "user")

(defun sweeprolog-local-predicates-collection (&optional prefix)
  "Return a list of prediactes accessible in the current buffer.

When non-nil, only predicates whose name contains PREFIX are returned."
  (sweeprolog-open-query "user" "sweep" "sweep_local_predicate_completion"
                    (cons sweeprolog-buffer-module
                          prefix))
  (let ((sol (sweeprolog-next-solution)))
    (sweeprolog-close-query)
    (when (sweeprolog-true-p sol)
      (setq sweeprolog-predicate-completion-collection (cdr sol)))))

(defun sweeprolog-predicates-collection (&optional prefix)
  "Return a list of prediacte completion candidates matchitng PREFIX."
  (sweeprolog-open-query "user" "sweep" "sweep_predicates_collection" prefix)
  (let ((sol (sweeprolog-next-solution)))
    (sweeprolog-close-query)
    (when (sweeprolog-true-p sol)
      (cdr sol))))

(defun sweeprolog-predicate-references (mfn)
  "Find source locations where the predicate MFN is called."
  (sweeprolog-open-query "user" "sweep" "sweep_predicate_references" mfn)
  (let ((sol (sweeprolog-next-solution)))
    (sweeprolog-close-query)
    (when (sweeprolog-true-p sol)
      (cdr sol))))

(defun sweeprolog-predicate-location (mfn)
  "Return the source location where the predicate MFN is defined."
  (sweeprolog-open-query "user" "sweep" "sweep_predicate_location" mfn)
  (let ((sol (sweeprolog-next-solution)))
    (sweeprolog-close-query)
    (when (sweeprolog-true-p sol)
      (cdr sol))))

(defun sweeprolog-predicate-apropos (pattern)
  "Return a list of predicates whose name resembeles PATTERN."
  (sweeprolog-open-query "user" "sweep" "sweep_predicate_apropos" pattern)
  (let ((sol (sweeprolog-next-solution)))
    (sweeprolog-close-query)
    (when (sweeprolog-true-p sol)
      (cdr sol))))

(defun sweeprolog-read-predicate ()
  "Read a Prolog predicate (M:F/N) from the minibuffer, with completion."
  (let* ((col (sweeprolog-predicates-collection))
         (completion-extra-properties
          (list :annotation-function
                (lambda (key)
                  (let* ((val (cdr (assoc-string key col))))
                    (if val
                        (concat (make-string (- 64 (length key)) ? ) (car val))
                      nil))))))
    (completing-read sweeprolog-read-predicate-prompt col)))

(defun sweeprolog-predicate-prefix-boundaries (&optional point)
  (let ((case-fold-search nil))
    (save-mark-and-excursion
      (save-match-data
        (when point (goto-char point))
        (unless (bobp) (backward-char))
        (while (looking-at-p "[[:alnum:]_]")
          (backward-char))
        (when (looking-at-p ":[[:lower:]]")
          (unless (bobp) (backward-char))
          (while (looking-at-p "[[:alnum:]_]")
            (backward-char)))
        (forward-char)
        (when (looking-at-p "[[:lower:]]")
          (let ((start (point)))
            (while (looking-at-p "[[:alnum:]:_]")
              (forward-char))
            (cons start (point))))))))

(defun sweeprolog-prefix-operators (&optional file)
  (sweeprolog-open-query "user"
                    "sweep" "sweep_prefix_ops"
                    (or file (buffer-file-name)))
  (let ((sol (sweeprolog-next-solution)))
    (sweeprolog-close-query)
    (when (sweeprolog-true-p sol)
      (cdr sol))))

(defun sweeprolog-completion-at-point-function ()
  (when-let ((bounds (sweeprolog-predicate-prefix-boundaries)))
    (let ((start (car bounds))
          (end   (cdr bounds)))
      (list start end
            (completion-table-with-cache #'sweeprolog-local-predicates-collection)
            :exclusive 'no
            :annotation-function
            (lambda (key)
              (when-let ((ann (cdr (assoc-string key sweeprolog-predicate-completion-collection))))
                (concat " " (mapconcat #'identity ann ","))))
            :exit-function
            (lambda (key sts)
              (when (eq sts 'finished)
                (let ((opoint (point)))
                  (save-match-data
                    (combine-after-change-calls
                      (skip-chars-backward "1234567890")
                      (when (= ?/ (preceding-char))
                        (backward-char)
                        (let ((arity (string-to-number (buffer-substring-no-properties (1+ (point)) opoint))))
                          (delete-region (point) opoint)
                          (when (and
                                 (< 0 arity)
                                 (not
                                  (string=
                                   "op"
                                   (cadr
                                    (assoc-string
                                     key
                                     sweeprolog-predicate-completion-collection)))))
                            (insert "(")
                            (dotimes (_ (1- arity))
                              (insert "_, "))
                            (insert "_)")
                            (goto-char (1- opoint))))))))))))))

;;;###autoload
(defun sweeprolog-find-predicate (mfn)
  "Jump to the definition of the Prolog predicate MFN.
MFN must be a string of the form \"M:F/N\" where M is a Prolog
module name, F is a functor name and N is its arity."
  (interactive (list (sweeprolog-read-predicate)))
  (if-let ((loc (sweeprolog-predicate-location mfn)))
      (let ((path (car loc))
            (line (or (cdr loc) 1)))
        (find-file path)
        (goto-char (point-min))
        (forward-line (1- line)))
    (user-error "Unable to locate predicate %s" mfn)))

(defun sweeprolog-modules-collection ()
  (sweeprolog-open-query "user" "sweep" "sweep_modules_collection" nil)
  (let ((sol (sweeprolog-next-solution)))
    (sweeprolog-close-query)
    (when (sweeprolog-true-p sol)
      (cdr sol))))

(defun sweeprolog-module-path (mod)
  (sweeprolog-open-query "user" "sweep" "sweep_module_path" mod)
  (let ((sol (sweeprolog-next-solution)))
    (sweeprolog-close-query)
    (when (sweeprolog-true-p sol)
      (cdr sol))))

(defun sweeprolog-read-module-name ()
  "Read a Prolog module name from the minibuffer, with completion."
  (let* ((col (sweeprolog-modules-collection))
         (completion-extra-properties
          (list :annotation-function
                (lambda (key)
                  (let* ((val (cdr (assoc-string key col)))
                         (pat (car val))
                         (des (cdr val)))
                    (concat (make-string (max 0 (- 32 (length key))) ? )
                            (if des
                                (concat pat (make-string (max 0 (- 80 (length pat))) ? ) des)
                              pat)))))))
    (completing-read sweeprolog-read-module-prompt col)))


(defun sweeprolog--set-buffer-module ()
  (sweeprolog-open-query "user" "sweep" "sweep_path_module" (buffer-file-name))
  (let ((sol (sweeprolog-next-solution)))
    (sweeprolog-close-query)
    (when (sweeprolog-true-p sol)
      (setq sweeprolog-buffer-module (cdr sol)))))

;;;###autoload
(defun sweeprolog-find-module (mod)
  "Jump to the source file of the Prolog module MOD."
  (interactive (list (sweeprolog-read-module-name)))
  (find-file (sweeprolog-module-path mod)))

(defun sweeprolog-packs-collection ()
  (sweeprolog-open-query "user" "sweep" "sweep_packs_collection" "")
  (let ((sol (sweeprolog-next-solution)))
    (sweeprolog-close-query)
    (when (sweeprolog-true-p sol)
      (cdr sol))))

(defun sweeprolog-read-pack-name ()
  "Read a Prolog pack name from the minibuffer, with completion."
  (let* ((col (sweeprolog-packs-collection))
         (completion-extra-properties
          (list :annotation-function
                (lambda (key)
                  (let* ((val (cdr (assoc-string key col)))
                         (des (car val))
                         (ver (cadr val)))
                    (concat (make-string (max 0 (- 32 (length key))) ? )
                            (if des
                                (concat ver (make-string (max 0 (- 16 (length ver))) ? ) des)
                              ver)))))))
    (completing-read sweeprolog-read-pack-prompt col)))

(defun sweeprolog-true-p (sol)
  (or (eq (car sol) '!)
      (eq (car sol) t)))

;;;###autoload
(defun sweeprolog-pack-install (pack)
  "Install or upgrade Prolog package PACK."
  (interactive (list (sweeprolog-read-pack-name)))
  (sweeprolog-open-query "user" "sweep" "sweep_pack_install" pack)
  (let ((sol (sweeprolog-next-solution)))
    (sweeprolog-close-query)
    (if (sweeprolog-true-p sol)
        (message "Package install successful.")
      (user-error "Pacakge installation failed!"))))


(defgroup sweeprolog-faces nil
  "Faces used to highlight Prolog code."
  :group 'sweeprolog)

(defcustom sweeprolog-faces-style nil
  "Style of faces to use for highlighting Prolog code."
  :type '(choice (const :tag "Default" nil)
                 (const :tag "Light"   light)
                 (const :tag "Dark"    dark))
  :package-version '((sweeprolog . "0.3.2"))
  :group 'sweeprolog-faces)

(eval-when-compile
  (defmacro sweeprolog-defface (name def light dark doc)
    "Define sweeprolog face FACE with doc DOC."
    (declare
     (indent defun)
     (doc-string 4))
    (let ((func (intern (concat "sweeprolog-" (symbol-name name) "-face")))
          (facd (intern (concat "sweeprolog-" (symbol-name name) "-dark-face")))
          (facl (intern (concat "sweeprolog-" (symbol-name name) "-light-face")))
          (face (intern (concat "sweeprolog-" (symbol-name name) "-default-face"))))
      `(progn
         (defface ,facl
           '((default              . ,light))
           ,(concat "Light face used to highlight " (downcase doc))
           :group 'sweeprolog-faces)
         (defface ,facd
           '((default              . ,dark))
           ,(concat "Dark face used to highlight " (downcase doc))
           :group 'sweeprolog-faces)
         (defface ,face
           '((default              . ,def))
           ,(concat "Face used to highlight " (downcase doc))
           :group 'sweeprolog-faces)
         (defun ,func ()
           ,(concat "Return the face used to highlight " (downcase doc))
           (pcase sweeprolog-faces-style
             ('light ',facl)
             ('dark  ',facd)
             (_      ',face)))))))

(sweeprolog-defface
  functor
  (:inherit font-lock-function-name-face)
  (:foreground "navyblue")
  (:foreground "darkcyan")
  "Functors.")

(sweeprolog-defface
  arity
  (:inherit font-lock-function-name-face)
  (:foreground "navyblue")
  (:foreground "darkcyan")
  "Arities.")

(sweeprolog-defface
  predicate-indicator
  (:inherit font-lock-function-name-face)
  (:foreground "navyblue")
  (:foreground "darkcyan")
  "Predicate indicators.")

(sweeprolog-defface
  built-in
  (:inherit font-lock-keyword-face)
  (:foreground "blue")
  (:foreground "cyan")
  "Built in predicate calls.")

(sweeprolog-defface
  neck
  (:inherit font-lock-preprocessor-face)
  (:weight bold)
  (:weight bold)
  "Necks.")

(sweeprolog-defface goal
  (:inherit font-lock-function-name-face)
  (:inherit font-lock-function-name-face)
  (:inherit font-lock-function-name-face)
  "Unspecified predicate goals.")

(sweeprolog-defface
  string
  (:inherit font-lock-string-face)
  (:foreground "navyblue")
  (:foreground "palegreen")
  "Strings.")

(sweeprolog-defface
  comment
  (:inherit font-lock-comment-face)
  (:foreground "darkgreen")
  (:foreground "green")
  "Comments.")

(sweeprolog-defface
  head-built-in
  (:background "orange" :weight bold)
  (:background "orange" :weight bold)
  (:background "orange" :weight bold)
  "Built-in predicate definitons.")

(sweeprolog-defface
 method
  (:weight bold)
  (:weight bold)
  (:weight bold)
  "PCE classes.")

(sweeprolog-defface
  class
  (:underline t)
  (:underline t)
  (:underline t)
  "PCE classes.")

(sweeprolog-defface
  no-file
  (:foreground "red")
  (:foreground "red")
  (:foreground "red")
  "Non-existsing file specifications.")

(sweeprolog-defface
  head-local
  (:inherit font-lock-builtin-face)
  (:weight bold)
  (:weight bold)
  "Local predicate definitions.")

(sweeprolog-defface
  head-meta
  (:inherit font-lock-preprocessor-face)
  (:inherit default)
  (:inherit default)
  "Meta predicate definitions.")

(sweeprolog-defface
  head-dynamic
  (:inherit font-lock-constant-face)
  (:foreground "magenta" :weight bold)
  (:foreground "magenta" :weight bold)
  "Dynamic predicate definitions.")

(sweeprolog-defface
  head-multifile
  (:inherit font-lock-type-face)
  (:foreground "navyblue" :weight bold)
  (:foreground "palegreen" :weight bold)
  "Multifile predicate definitions.")

(sweeprolog-defface
  head-extern
  (:inherit font-lock-type-face)
  (:foreground "blue" :weight bold)
  (:foreground "cyan" :weight bold)
  "External predicate definitions.")

(sweeprolog-defface
  head-unreferenced
  (:inherit font-lock-warning-face)
  (:foreground "red" :weight bold)
  (:foreground "red" :weight bold)
  "Unreferenced predicate definitions.")

(sweeprolog-defface
  head-exported
  (:inherit font-lock-builtin-face)
  (:foreground "blue" :weight bold)
  (:foreground "cyan" :weight bold)
  "Exported predicate definitions.")

(sweeprolog-defface
  head-hook
  (:inherit font-lock-type-face)
  (:foreground "blue" :underline t)
  (:foreground "cyan" :underline t)
  "Hook definitions.")

(sweeprolog-defface
  head-iso
  (:inherit font-lock-keyword-face)
  (:background "orange" :weight bold)
  (:background "orange" :weight bold)
  "ISO specified predicate definitions.")

(sweeprolog-defface
  head-imported
  (:inherit font-lock-function-name-face)
  (:foreground "darkgoldenrod4" :weight bold)
  (:foreground "darkgoldenrod4" :weight bold)
  "Imported head terms.")

(sweeprolog-defface
  head-undefined
  (:inherit font-lock-warning-face)
  (:weight bold)
  (:weight bold)
  "Undefind head terms.")

(sweeprolog-defface
  head-public
  (:inherit font-lock-builtin-face)
  (:foreground "#016300" :weight bold)
  (:foreground "#016300" :weight bold)
  "Public definitions.")

(sweeprolog-defface
  meta-spec
  (:inherit font-lock-preprocessor-face)
  (:inherit font-lock-preprocessor-face)
  (:inherit font-lock-preprocessor-face)
  "Meta argument specifiers.")

(sweeprolog-defface
  recursion
  (:inherit font-lock-builtin-face)
  (:underline t)
  (:underline t)
  "Recursive calls.")

(sweeprolog-defface
  local
  (:inherit font-lock-function-name-face)
  (:foreground "navyblue")
  (:foreground "darkcyan")
  "Local predicate calls.")

(sweeprolog-defface
  autoload
  (:inherit font-lock-function-name-face)
  (:foreground "navyblue")
  (:foreground "darkcyan")
  "Autoloaded predicate calls.")

(sweeprolog-defface
  imported
  (:inherit font-lock-function-name-face)
  (:foreground "blue")
  (:foreground "cyan")
  "Imported predicate calls.")

(sweeprolog-defface
  extern
  (:inherit font-lock-function-name-face)
  (:foreground "blue" :underline t)
  (:foreground "cyan" :underline t)
  "External predicate calls.")

(sweeprolog-defface
  foreign
  (:inherit font-lock-keyword-face)
  (:foreground "darkturquoise")
  (:foreground "darkturquoise")
  "Foreign predicate calls.")

(sweeprolog-defface
  meta
  (:inherit font-lock-type-face)
  (:foreground "red4")
  (:foreground "red4")
  "Meta predicate calls.")

(sweeprolog-defface
  undefined
  (:inherit font-lock-warning-face)
  (:foreground "red")
  (:foreground "orange")
  "Undefined predicate calls.")

(sweeprolog-defface
  thread-local
  (:inherit font-lock-constant-face)
  (:foreground "magenta" :underline t)
  (:foreground "magenta" :underline t)
  "Thread local predicate calls.")

(sweeprolog-defface
  global
  (:inherit font-lock-keyword-face)
  (:foreground "magenta")
  (:foreground "darkcyan")
  "Global predicate calls.")

(sweeprolog-defface
  multifile
  (:inherit font-lock-function-name-face)
  (:foreground "navyblue")
  (:foreground "palegreen")
  "Multifile predicate calls.")

(sweeprolog-defface
  dynamic
  (:inherit font-lock-constant-face)
  (:foreground "magenta")
  (:foreground "magenta")
  "Dynamic predicate calls.")

(sweeprolog-defface
  undefined-import
  (:inherit font-lock-warning-face)
  (:foreground "red")
  (:foreground "red")
  "Undefined imports.")

(sweeprolog-defface
  html-attribute
  (:inherit font-lock-function-name-face)
  (:foreground "magenta4")
  (:foreground "magenta4")
  "HTML attributes.")

(sweeprolog-defface
  html-call
  (:inherit font-lock-keyword-face)
  (:foreground "magenta4" :weight bold)
  (:foreground "magenta4" :weight bold)
  "HTML calls.")

(sweeprolog-defface
  option-name
  (:inherit font-lock-constant-face)
  (:foreground "#3434ba")
  (:foreground "#3434ba")
  "Option names.")

(sweeprolog-defface
  no-option-name
  (:inherit font-lock-warning-face)
  (:foreground "red")
  (:foreground "orange")
  "Non-existent option names.")

(sweeprolog-defface
  flag-name
  (:inherit font-lock-constant-face)
  (:foreground "blue")
  (:foreground "cyan")
  "Flag names.")

(sweeprolog-defface
  no-flag-name
  (:inherit font-lock-warning-face)
  (:foreground "red")
  (:foreground "red")
  "Non-existent flag names.")

(sweeprolog-defface
  qq-type
  (:inherit font-lock-type-face)
  (:weight bold)
  (:weight bold)
  "Quasi-quotation types.")

(sweeprolog-defface
  qq-sep
  (:inherit font-lock-type-face)
  (:weight bold)
  (:weight bold)
  "Quasi-quotation separators.")

(sweeprolog-defface
  qq-open
  (:inherit font-lock-type-face)
  (:weight bold)
  (:weight bold)
  "Quasi-quotation open sequences.")

(sweeprolog-defface
  qq-content
  (:inherit default)
  (:foreground "red4")
  (:foreground "red4")
  "Quasi-quotation content.")

(sweeprolog-defface
  qq-close
  (:inherit font-lock-type-face)
  (:weight bold)
  (:weight bold)
  "Quasi-quotation close sequences.")

(sweeprolog-defface
  op-type
  (:inherit font-lock-type-face)
  (:foreground "blue")
  (:foreground "cyan")
  "Operator types.")

(sweeprolog-defface
  dict-tag
  (:inherit font-lock-constant-face)
  (:weight bold)
  (:weight bold)
  "Dict tags.")

(sweeprolog-defface
  dict-key
  (:inherit font-lock-keyword-face)
  (:weight bold)
  (:weight bold)
  "Dict keys.")

(sweeprolog-defface
  dict-sep
  (:inherit font-lock-keyword-face)
  (:weight bold)
  (:weight bold)
  "Dict separators.")

(sweeprolog-defface
  file
  (:inherit button)
  (:foreground "blue" :underline t)
  (:foreground "cyan" :underline t)
  "File specifiers.")

(sweeprolog-defface
  file-no-depend
  (:inherit font-lock-warning-face)
  (:foreground "blue" :underline t :background "pink")
  (:foreground "cyan" :underline t :background "pink")
  "Unused file specifiers.")

(sweeprolog-defface
  unused-import
  (:inherit font-lock-warning-face)
  (:foreground "blue" :background "pink")
  (:foreground "cyan" :background "pink")
  "Unused imports.")

(sweeprolog-defface
  identifier
  (:inherit font-lock-type-face)
  (:weight bold)
  (:weight bold)
  "Identifiers.")

(sweeprolog-defface
  hook
  (:inherit font-lock-preprocessor-face)
  (:foreground "blue" :underline t)
  (:foreground "cyan" :underline t)
  "Hooks.")

(sweeprolog-defface
  module
  (:inherit font-lock-type-face)
  (:foreground "darkslateblue")
  (:foreground "lightslateblue")
  "Module names.")

(sweeprolog-defface
  singleton
  (:inherit font-lock-warning-face)
  (:foreground "red4" :weight bold)
  (:foreground "orangered1" :weight bold)
  "Singletons.")

(sweeprolog-defface
  fullstop
  (:inherit font-lock-negation-char-face)
  (:inherit font-lock-negation-char-face)
  (:inherit font-lock-negation-char-face)
  "Fullstops.")

(sweeprolog-defface
  nil
  (:inherit font-lock-keyword-face)
  (:inherit font-lock-keyword-face)
  (:inherit font-lock-keyword-face)
  "The empty list.")

(sweeprolog-defface
  variable-at-point
  (:underline t)
  (:underline t)
  (:underline t)
  "Variables.")

(sweeprolog-defface
  variable
  (:inherit font-lock-variable-name-face)
  (:foreground "red4")
  (:foreground "orangered1")
  "Variables.")

(sweeprolog-defface
  ext-quant
  (:inherit font-lock-keyword-face)
  (:inherit font-lock-keyword-face)
  (:inherit font-lock-keyword-face)
  "Existential quantifiers.")

(sweeprolog-defface
  control
  (:inherit font-lock-keyword-face)
  (:inherit font-lock-keyword-face)
  (:inherit font-lock-keyword-face)
  "Control constructs.")

(sweeprolog-defface
  atom
  (:inherit font-lock-constant-face)
  (:inherit font-lock-constant-face)
  (:inherit font-lock-constant-face)
  "Atoms.")

(sweeprolog-defface
  int
  (:inherit font-lock-constant-face)
  (:inherit font-lock-constant-face)
  (:inherit font-lock-constant-face)
  "Integers.")

(sweeprolog-defface
  float
  (:inherit font-lock-constant-face)
  (:inherit font-lock-constant-face)
  (:inherit font-lock-constant-face)
  "Floats.")

(sweeprolog-defface
  codes
  (:inherit font-lock-constant-face)
  (:inherit font-lock-constant-face)
  (:inherit font-lock-constant-face)
  "Codes.")

(sweeprolog-defface
  error
  (:inherit font-lock-warning-face)
  (:background "orange")
  (:background "orange")
  "Unspecified errors.")

(sweeprolog-defface
  type-error
  (:inherit font-lock-warning-face)
  (:background "orange")
  (:background "orange")
  "Type errors.")

(sweeprolog-defface
  instantiation-error
  (:inherit font-lock-warning-face)
  (:background "orange")
  (:background "orange")
  "Instantiation errors.")

(sweeprolog-defface
  syntax-error
  (:inherit error)
  (:background "orange")
  (:background "orange")
  "Syntax errors.")

(sweeprolog-defface
  around-syntax-error
  (:inherit default)
  (:inherit default)
  (:inherit default)
  "Text around a syntax error.")

(sweeprolog-defface
  clause
  (:inherit default)
  (:inherit default)
  (:inherit default)
  "Predicate clauses.")

(sweeprolog-defface
  grammar-rule
  (:inherit default)
  (:inherit default)
  (:inherit default)
  "DCG grammar rules.")

(sweeprolog-defface
  term
  (:inherit default)
  (:inherit default)
  (:inherit default)
  "Top terms.")

(sweeprolog-defface
  directive
  (:inherit default)
  (:inherit default)
  (:inherit default)
  "Directives.")

(sweeprolog-defface
  structured-comment
  (:inherit font-lock-doc-face)
  (:inherit font-lock-doc-face :foreground "darkgreen")
  (:inherit font-lock-doc-face :foreground "green")
  "Structured comments.")

(defvar-local sweeprolog--variable-at-point nil)
(defvar-local sweeprolog--diagnostics nil)
(defvar-local sweeprolog--diagnostics-report-fn nil)
(defvar-local sweeprolog--diagnostics-changes-beg nil)
(defvar-local sweeprolog--diagnostics-changes-end nil)

(defun sweeprolog-diagnostic-function (report-fn &rest rest)
  (setq sweeprolog--diagnostics nil
        sweeprolog--diagnostics-report-fn report-fn
        sweeprolog--diagnostics-changes-beg (plist-get rest :changes-start)
        sweeprolog--diagnostics-changes-end (plist-get rest :changes-end)))

(defun sweeprolog--colour-term-to-faces (beg end arg)
  (pcase arg
    (`("comment" . "structured")
     (list (list beg end nil)
           (list beg end (sweeprolog-structured-comment-face))))
    (`("comment" . ,_)
     (list (list beg end nil)
           (list beg end (sweeprolog-comment-face))))
    (`("head" "unreferenced" ,f ,a)
     (when sweeprolog-enable-flymake
       (push
        (flymake-make-diagnostic (current-buffer) beg end
                                 :note (format "Unreferenced definition for %s/%s" f a))
        sweeprolog--diagnostics))
     (list (list beg end (sweeprolog-head-unreferenced-face))))
    (`("head" "meta" . ,_)
     (list (list beg end (sweeprolog-head-meta-face))))
    (`("head" "iso" . ,_)
     (list (list beg end (sweeprolog-head-iso-face))))
    (`("head" "exported" . ,_)
     (list (list beg end (sweeprolog-head-exported-face))))
    (`("head" "hook" . ,_)
     (list (list beg end (sweeprolog-head-hook-face))))
    (`("head" "built_in" . ,_)
     (list (list beg end (sweeprolog-head-built-in-face))))
    (`("head" ,(rx "imported(") . ,_)
     (list (list beg end (sweeprolog-head-imported-face))))
    (`("head" ,(rx "extern(") . ,_)
     (list (list beg end (sweeprolog-head-extern-face))))
    (`("head" ,(rx "public(") . ,_)
     (list (list beg end (sweeprolog-head-public-face))))
    (`("head",(rx "dynamic ") . ,_)
     (list (list beg end (sweeprolog-head-dynamic-face))))
    (`("head",(rx "multifile ") . ,_)
     (list (list beg end (sweeprolog-head-multifile-face))))
    (`("head" ,(rx "local(") . ,_)
     (list (list beg end (sweeprolog-head-local-face))))
    (`("goal" "recursion" . ,_)
     (list (list beg end (sweeprolog-recursion-face))))
    (`("goal" "meta"      . ,_)
     (list (list beg end (sweeprolog-meta-face))))
    (`("goal" "built_in"  . ,_)
     (list (list beg end (sweeprolog-built-in-face))))
    (`("goal" "undefined" ,f ,a)
     (when sweeprolog-enable-flymake
       (push
        (flymake-make-diagnostic (current-buffer) beg end
                                 :warning (format "Undefined predicate %s/%s" f a))
        sweeprolog--diagnostics))
     (list (list beg end (sweeprolog-undefined-face))))
    (`("goal" "global" . ,_)
     (list (list beg end (sweeprolog-global-face))))
    (`("goal",(rx "dynamic ") . ,_)
     (list (list beg end (sweeprolog-dynamic-face))))
    (`("goal",(rx "multifile ") . ,_)
     (list (list beg end (sweeprolog-multifile-face))))
    (`("goal",(rx "thread_local ") . ,_)
     (list (list beg end (sweeprolog-thread-local-face))))
    (`("goal",(rx "extern(") . ,_)
     (list (list beg end (sweeprolog-extern-face))))
    (`("goal",(rx "autoload(") . ,_)
     (list (list beg end (sweeprolog-autoload-face))))
    (`("goal",(rx "imported(") . ,_)
     (list (list beg end (sweeprolog-imported-face))))
    (`("goal",(rx "global(") . ,_)
     (list (list beg end (sweeprolog-global-face))))
    (`("goal",(rx "local(") . ,_)
     (list (list beg end (sweeprolog-local-face))))
    ("instantiation_error"
     (when sweeprolog-enable-flymake
       (push
        (flymake-make-diagnostic (current-buffer) beg end :warning "Instantiation error")
        sweeprolog--diagnostics))
     (list (list beg end (sweeprolog-instantiation-error-face))))
    ("type_error"
     (when sweeprolog-enable-flymake
       (push
        (flymake-make-diagnostic (current-buffer) beg end :warning "Type error")
        sweeprolog--diagnostics))
     (list (list beg end (sweeprolog-type-error-face))))
    (`("syntax_error" ,message ,eb ,ee)
     (when sweeprolog-enable-flymake
       (push
        (flymake-make-diagnostic (current-buffer) beg end :error message)
        sweeprolog--diagnostics))
     (list (list eb ee nil)
           (list eb ee (sweeprolog-around-syntax-error-face))
           (list beg end (sweeprolog-syntax-error-face))))
    ("unused_import"
     (when sweeprolog-enable-flymake
       (push
        (flymake-make-diagnostic (current-buffer) beg end :note "Unused import")
        sweeprolog--diagnostics))
     (list (list beg end (sweeprolog-unused-import-face))))
    ("undefined_import"
     (when sweeprolog-enable-flymake
       (push
        (flymake-make-diagnostic (current-buffer) beg end :warning "Undefined import")
        sweeprolog--diagnostics))
     (list (list beg end (sweeprolog-undefined-import-face))))
    ("error"
     (when sweeprolog-enable-flymake
       (push
        (flymake-make-diagnostic (current-buffer) beg end :warning "Unspecified error")
        sweeprolog--diagnostics))
     (list (list beg end (sweeprolog-error-face))))
    ("html_attribute"
     (list (list beg end (sweeprolog-html-attribute-face))))
    ("html"
     (list (list beg end (sweeprolog-html-call-face))))
    ("dict_tag"
     (list (list beg end (sweeprolog-dict-tag-face))))
    ("dict_key"
     (list (list beg end (sweeprolog-dict-key-face))))
    ("dict_sep"
     (list (list beg end (sweeprolog-dict-sep-face))))
    ("meta"
     (list (list beg end (sweeprolog-meta-spec-face))))
    ("flag_name"
     (list (list beg end (sweeprolog-flag-name-face))))
    ("no_flag_name"
     (when sweeprolog-enable-flymake
       (push
        (flymake-make-diagnostic (current-buffer) beg end :warning "No such flag")
        sweeprolog--diagnostics))
     (list (list beg end (sweeprolog-flag-name-face))))
    ("ext_quant"
     (list (list beg end (sweeprolog-ext-quant-face))))
    ("atom"
     (list (list beg end (sweeprolog-atom-face))))
    ("float"
     (list (list beg end (sweeprolog-float-face))))
    ("int"
     (list (list beg end (sweeprolog-int-face))))
    ("singleton"
     (when sweeprolog-enable-flymake
       (push
        (flymake-make-diagnostic (current-buffer) beg end :note "Singleton variable")
        sweeprolog--diagnostics))
     (list (list beg end (sweeprolog-singleton-face))))
    ("option_name"
     (list (list beg end (sweeprolog-option-name-face))))
    ("no_option_name"
     (when sweeprolog-enable-flymake
       (push
        (flymake-make-diagnostic (current-buffer) beg end :warning "No such option")
        sweeprolog--diagnostics))
     (list (list beg end (sweeprolog-no-option-name-face))))
    ("control"
     (list (list beg end (sweeprolog-control-face))))
    ("var"
     (let ((var (buffer-substring-no-properties beg end)))
       (with-silent-modifications
         (put-text-property beg end 'cursor-sensor-functions
                            (sweeprolog-cursor-sensor-functions var)))
       (cons (list beg end (sweeprolog-variable-face))
             (and sweeprolog--variable-at-point
                  (string= sweeprolog--variable-at-point var)
                  (list (list beg end (sweeprolog-variable-at-point-face)))))))
    ("fullstop"
     (list (list beg
                 (save-excursion
                   (goto-char (min (1+ end) (point-max)))
                   (skip-chars-forward " \t\n")
                   (point))
                 nil)
           (list beg end (sweeprolog-fullstop-face))))
    ("functor"
     (list (list beg end (sweeprolog-functor-face))))
    ("arity"
     (list (list beg end (sweeprolog-arity-face))))
    ("predicate_indicator"
     (list (list beg end (sweeprolog-predicate-indicator-face))))
    ("string"
     (list (list beg end (sweeprolog-string-face))))
    ("module"
     (list (list beg end (sweeprolog-module-face))))
    ("neck"
     (list (list beg end (sweeprolog-neck-face))))
    ("hook"
     (list (list beg end (sweeprolog-hook-face))))
    (`("qq_content" . ,type)
     (let ((mode (cdr (assoc-string type sweeprolog-qq-mode-alist))))
       (if (and mode (fboundp mode))
           (let ((res nil)
                 (string (buffer-substring-no-properties beg end)))
             (with-current-buffer
                 (get-buffer-create
                  (format " *sweep-qq-content:%s*" type))
               (with-silent-modifications
                 (erase-buffer)
                 (insert string " "))
               (unless (eq major-mode mode) (funcall mode))
               (font-lock-ensure)
               (let ((pos (point-min)) next)
                 (while (setq next (next-property-change pos))
                   (dolist (prop '(font-lock-face face))
                     (let ((new-prop (get-text-property pos prop)))
                       (when new-prop
                         (push (list (+ beg (1- pos)) (1- (+ beg next)) new-prop)
                               res))))
                   (setq pos next)))
               (set-buffer-modified-p nil)
               res))
         (list (list beg end (sweeprolog-qq-content-face))))))
    ("qq_type"
     (list (list beg end (sweeprolog-qq-type-face))))
    ("qq_sep"
     (list (list beg end (sweeprolog-qq-sep-face))))
    ("qq_open"
     (list (list beg end (sweeprolog-qq-open-face))))
    ("qq_close"
     (list (list beg end (sweeprolog-qq-close-face))))
    ("identifier"
     (list (list beg end (sweeprolog-identifier-face))))
    ("file"
     (list (list beg end (sweeprolog-file-face))))
    ("file_no_depend"
     (when sweeprolog-enable-flymake
       (push
        (flymake-make-diagnostic (current-buffer) beg end :note "Unused dependency")
        sweeprolog--diagnostics))
     (list (list beg end (sweeprolog-file-no-depend-face))))
    ("nofile"
     (when sweeprolog-enable-flymake
       (push
        (flymake-make-diagnostic (current-buffer) beg end :warning "No such file")
        sweeprolog--diagnostics))
     (list (list beg end (sweeprolog-no-file-face))))
    ("op_type"
     (list (list beg end (sweeprolog-op-type-face))))
    ("directive"
     (list (list beg end nil) (list beg end (sweeprolog-directive-face))))
    ("clause"
     (list (list beg end nil) (list beg end (sweeprolog-clause-face))))
    ("term"
     (list (list beg end nil) (list beg end (sweeprolog-term-face))))
    ("grammar_rule"
     (list (list beg end nil) (list beg end (sweeprolog-grammar-rule-face))))
    ("method"
     (list (list beg end (sweeprolog-method-face))))
    ("class"
     (list (list beg end (sweeprolog-class-face))))))

(defun sweeprolog--colourise (args)
  "ARGS is a list of the form (BEG LEN . SEM)."
  (when-let ((beg (max (point-min) (car  args)))
             (end (min (point-max) (+ beg (cadr args))))
             (arg (cddr args))
             (fll (sweeprolog--colour-term-to-faces beg end arg)))
    (with-silent-modifications
      (dolist (ent fll)
        (let ((b (car ent))
              (e (cadr ent))
              (flf (caddr ent)))
          (if flf
              (font-lock--add-text-property b e
                                            'font-lock-face flf
                                            (current-buffer) nil)
            (remove-list-of-text-properties b e '(font-lock-face))))))))

(defun sweeprolog-colourise-buffer (&optional buffer)
  "Update cross-reference data and semantic highlighting in BUFFER."
  (interactive)
  (when sweeprolog-enable-flymake
    (flymake-start))
  (with-current-buffer (or buffer (current-buffer))
    (let* ((beg (point-min))
           (end (point-max))
           (contents (buffer-substring-no-properties beg end)))
      (with-silent-modifications
        (font-lock-unfontify-region beg end))
      (sweeprolog-open-query "user"
                             "sweep"
                             "sweep_colourise_buffer"
                             (cons contents (buffer-file-name)))
      (let ((sol (sweeprolog-next-solution)))
        (sweeprolog-close-query)
        (when sweeprolog--diagnostics-report-fn
          (funcall sweeprolog--diagnostics-report-fn sweeprolog--diagnostics)
          (setq sweeprolog--diagnostics-report-fn nil))
        sol))))

(defun sweeprolog-colourise-some-terms (beg0 end0 &optional _verbose)
  (when sweeprolog-enable-flymake
    (flymake-start))
  (let* ((beg (save-mark-and-excursion
                (goto-char (min beg0 (or sweeprolog--diagnostics-changes-beg beg0)))
                (sweeprolog-beginning-of-top-term)
                (max (1- (point)) (point-min))))
         (end (save-mark-and-excursion
                (goto-char (max end0 (or sweeprolog--diagnostics-changes-end end0)))
                (sweeprolog-end-of-top-term)
                (point)))
         (contents (buffer-substring-no-properties beg end)))
    (with-silent-modifications
      (font-lock-unfontify-region beg end))
    (sweeprolog-open-query "user"
                           "sweep"
                           "sweep_colourise_some_terms"
                           (list contents
                                 (buffer-file-name)
                                 beg))
    (let ((sol (sweeprolog-next-solution)))
      (sweeprolog-close-query)
      (when sweeprolog--diagnostics-report-fn
        (funcall sweeprolog--diagnostics-report-fn
                 sweeprolog--diagnostics
                 :region (cons beg end))
        (setq sweeprolog--diagnostics-report-fn nil))
      (when (sweeprolog-true-p sol)
        `(jit-lock-bounds ,beg . ,end)))))

(defun sweeprolog-colourise-query (buffer)
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when-let ((beg (cdr comint-last-prompt))
                 (end (point-max))
                 (query (buffer-substring-no-properties beg end)))
        (with-silent-modifications
          (font-lock-unfontify-region beg end))
        (sweeprolog-open-query "user"
                          "sweep"
                          "sweep_colourise_query"
                          (cons query (marker-position beg)))
        (let ((sol (sweeprolog-next-solution)))
          (sweeprolog-close-query)
          sol)))))

(defun sweeprolog-load-buffer (buffer)
  "Load the Prolog buffer BUFFER into the embedded SWI-Prolog runtime.

Interactively, if the major mode of the current buffer is
`sweeprolog-mode' and the command is called without a prefix argument,
load the current buffer.  Otherwise, prompt for a `sweeprolog-mode'
buffer to load."
  (interactive (list
                (if (and (not current-prefix-arg)
                         (eq major-mode 'sweeprolog-mode))
                    (current-buffer)
                  (read-buffer "Load buffer: "
                               (when (eq major-mode 'sweeprolog-mode)
                                 (buffer-name))
                               t
                               (lambda (b)
                                 (let ((n (or (and (consp b) (car b)) b)))
                                   (with-current-buffer n
                                     (eq major-mode 'sweeprolog-mode))))))))
  (with-current-buffer buffer
    (let* ((beg (point-min))
           (end (point-max))
           (contents (buffer-substring-no-properties beg end)))
      (sweeprolog-open-query "user"
                             "sweep"
                             "sweep_load_buffer"
                             (cons contents (buffer-file-name)))
      (let ((sol (sweeprolog-next-solution)))
        (sweeprolog-close-query)
        (if (sweeprolog-true-p sol)
            (message "Loaded %s." (buffer-name))
          (user-error "Loading %s failed!" (buffer-name)))))))

;;;###autoload
(defun sweeprolog-top-level (&optional buffer)
  "Run a Prolog top-level in BUFFER.
If BUFFER is nil, a buffer called \"*sweeprolog-top-level*\" is used
by default.

Interactively, a prefix arg means to prompt for BUFFER."
  (interactive
   (let* ((buffer
           (and current-prefix-arg
                (read-buffer "Top-level buffer: "
                             (if (and (eq major-mode 'sweeprolog-top-level-mode)
                                      (null (get-buffer-process
                                             (current-buffer))))
                                 (buffer-name)
                               (generate-new-buffer-name "*sweeprolog-top-level*"))))))
     (list buffer)))
  (let ((buf (get-buffer-create (or buffer "*sweeprolog-top-level*"))))
    (with-current-buffer buf
      (unless (eq major-mode 'sweeprolog-top-level-mode)
        (sweeprolog-top-level-mode)))
    (sweeprolog-open-query "user"
                           "sweep"
                           "sweep_accept_top_level_client"
                           (buffer-name buf))
    (let ((sol (sweeprolog-next-solution)))
      (sweeprolog-close-query)
      (unless (sweeprolog-true-p sol)
        (error "Failed to create new top-level!")))
    (with-current-buffer buf
      (make-comint-in-buffer "sweeprolog-top-level"
                             buf
                             (cons "localhost"
                                   sweeprolog-prolog-server-port))
      (unless comint-last-prompt
        (accept-process-output (get-buffer-process (current-buffer)) 1))
      (sweeprolog-top-level--populate-thread-id))
    (pop-to-buffer buf sweeprolog-top-level-display-action)))

(defun sweeprolog-top-level--post-self-insert-function ()
  (when-let ((pend (cdr comint-last-prompt)))
    (let* ((pstart (car comint-last-prompt))
           (prompt (buffer-substring-no-properties pstart pend)))
      (when (and (= (point) (1+ pend))
                 (not (string-empty-p  prompt))
                 (not (string= "?- "   (substring prompt
                                                  (- pend pstart 3)
                                                  (- pend pstart))))
                 (not (string= "|: "   prompt))
                 (not (string= "|    " prompt)))
        (comint-send-input)))))

(defvar-local sweeprolog-top-level-timer nil "Buffer-local timer.")
(defvar-local sweeprolog-top-level-thread-id nil
  "Prolog top-level thread ID corresponding to this buffer.")

(defun sweeprolog-top-level--populate-thread-id ()
  (sweeprolog-open-query "user"
                         "sweep"
                         "sweep_top_level_thread_buffer"
                         (buffer-name)
                         t)
  (let ((sol (sweeprolog-next-solution)))
    (sweeprolog-close-query)
    (when (sweeprolog-true-p sol)
      (setq sweeprolog-top-level-thread-id (cdr sol)))))

(defun sweeprolog-signal-thread (tid goal)
  (sweeprolog-open-query "user"
                         "sweep"
                         "sweep_thread_signal"
                         (cons tid goal))
  (let ((sol (sweeprolog-next-solution)))
    (sweeprolog-close-query)
    sol))

(defun sweeprolog-top-level-signal (buffer goal)
  "Signal the top-level thread corresponding to BUFFER to run GOAL."
  (interactive
   (list (read-buffer "Top-level buffer: "
                      nil t
                      (lambda (b)
                        (let ((bb (or (and (consp b) (car b)) b)))
                          (with-current-buffer bb
                            (and (derived-mode-p 'sweeprolog-top-level-mode)
                                 sweeprolog-top-level-thread-id)))))
         (read-string "Signal goal: ?- ")))
  (sweeprolog-signal-thread (buffer-local-value 'sweeprolog-top-level-thread-id
                                                (get-buffer buffer))
                            goal))

(defun sweeprolog-top-level-signal-current (goal)
  "Signal the current top-level thread to run GOAL."
  (interactive "MSignal goal: ?- " sweeprolog-top-level-mode)
  (sweeprolog-signal-thread sweeprolog-top-level-thread-id goal))

(defvar sweeprolog-top-level-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'sweeprolog-top-level-signal-current)
    map)
  "Keymap for `sweeprolog-top-level-mode'.")

;;;###autoload
(define-derived-mode sweeprolog-top-level-mode comint-mode "sweep Top-level"
  "Major mode for interacting with an inferior Prolog interpreter."
  :group 'sweeprolog-top-level
  (setq-local comint-prompt-regexp           (rx line-start "?- ")
              comint-input-ignoredups        t
              comint-prompt-read-only        t
              comint-input-filter            (lambda (s)
                                               (< sweeprolog-top-level-min-history-length
                                                  (length s)))
              comint-delimiter-argument-list '(?,)
              comment-start "%")
  (add-hook 'post-self-insert-hook #'sweeprolog-top-level--post-self-insert-function nil t)
  (setq sweeprolog-buffer-module "user")
  (add-hook 'completion-at-point-functions #'sweeprolog-completion-at-point-function nil t)
  (setq sweeprolog-top-level-timer (run-with-idle-timer 0.2 t #'sweeprolog-colourise-query (current-buffer)))
  (add-hook 'kill-buffer-hook
            (lambda ()
              (sweeprolog-top-level-signal (current-buffer)
                                           "thread_exit(0)"))
            nil t)
  (add-hook 'kill-buffer-hook
            (lambda ()
              (when (timerp sweeprolog-top-level-timer)
                (cancel-timer sweeprolog-top-level-timer)))
            nil t))

(sweeprolog--ensure-module)
(when sweeprolog-init-on-load (sweeprolog-init))

;;;###autoload
(defvar sweeprolog-prefix-map
  (let ((map (make-sparse-keymap)))
    (define-key map "F" #'sweeprolog-set-prolog-flag)
    (define-key map "P" #'sweeprolog-pack-install)
    (define-key map "R" #'sweeprolog-restart)
    (define-key map "T" #'sweeprolog-list-top-levels)
    (define-key map "e" #'sweeprolog-view-messages)
    (define-key map "l" #'sweeprolog-load-buffer)
    (define-key map "m" #'sweeprolog-find-module)
    (define-key map "p" #'sweeprolog-find-predicate)
    (define-key map "t" #'sweeprolog-top-level)
    map)
  "Keymap for `sweeprolog' global commands.")

;;;###autoload
(defun sweeprolog-file-name-handler (operation &rest args)
  (cond ((eq operation 'expand-file-name)
         (let ((fn (car  args))
               (dn (cadr args)))
           (sweeprolog-open-query "user"
                             "sweep"
                             "sweep_expand_file_name"
                             (cons fn dn))
           (let ((sol (sweeprolog-next-solution)))
             (sweeprolog-close-query)
             (if (sweeprolog-true-p sol)
                 (cdr sol)
               (let ((inhibit-file-name-handlers
                      (cons 'sweeprolog-file-name-handler
                            (and (eq inhibit-file-name-operation operation)
                                 inhibit-file-name-handlers)))
                     (inhibit-file-name-operation operation))
                 (apply operation args))))))
        (t (let ((inhibit-file-name-handlers
                  (cons 'sweeprolog-file-name-handler
                        (and (eq inhibit-file-name-operation operation)
                             inhibit-file-name-handlers)))
                 (inhibit-file-name-operation operation))
             (apply operation args)))))

(add-to-list 'file-name-handler-alist
             (cons (rx bol (one-or-more lower) "(")
                   #'sweeprolog-file-name-handler))

(defun sweeprolog-beginning-of-top-term (&optional arg)
  (let ((times (or arg 1)))
    (if (< 0 times)
        (let ((p (point)))
          (while (and (< 0 times) (not (bobp)))
            (setq times (1- times))
            (when-let ((safe-start (nth 8 (syntax-ppss))))
              (goto-char safe-start))
            (re-search-backward (rx bol graph) nil t)
            (let ((safe-start (or (nth 8 (syntax-ppss))
                                  (nth 8 (syntax-ppss (1+ (point)))))))
              (while (and safe-start (not (bobp)))
                (goto-char safe-start)
                (backward-char)
                (re-search-backward (rx bol graph) nil t)
                (setq safe-start (or (nth 8 (syntax-ppss))
                                     (nth 8 (syntax-ppss (1+ (point)))))))))
          (not (= p (point))))
      (sweeprolog-beginning-of-next-top-term (- times)))))

(defun sweeprolog-beginning-of-next-top-term (times)
  (let ((p (point)))
    (while (and (< 0 times) (not (eobp)))
      (setq times (1- times))
      (unless (eobp)
        (forward-char)
        (re-search-forward (rx bol graph) nil t))
      (while (and (nth 8 (syntax-ppss)) (not (eobp)))
        (forward-char)
        (re-search-forward (rx bol graph) nil t)))
    (not (= p (point)))))

(defun sweeprolog-end-of-top-term ()
  (unless (eobp)
    (while (and (nth 8 (syntax-ppss)) (not (eobp)))
      (forward-char))
    (or (re-search-forward (rx "." (or white "\n")) nil t)
        (goto-char (point-max)))
    (while (and (or (nth 8 (syntax-ppss))
                    (save-excursion
                      (nth 8 (syntax-ppss (max (point-min)
                                               (1- (point))))))
                    (save-match-data
                      (looking-back (rx "=.." (or white "\n"))
                                    (line-beginning-position))))
                (not (eobp)))
      (while (and (nth 8 (syntax-ppss)) (not (eobp)))
        (forward-char))
      (or (re-search-forward (rx "." (or white "\n")) nil t)
          (goto-char (point-max))))))

(defun sweeprolog-show-diagnostics (&optional proj)
  "Show diagnostics for the current project, or buffer if PROJ is nil.

Interactively, PROJ is the prefix argument."
  (interactive "P" sweeprolog-mode)
  (if (and sweeprolog-enable-flymake
           flymake-mode)
      (if proj
          (flymake-show-project-diagnostics)
        (flymake-show-buffer-diagnostics))
    (user-error "Flymake is not active in the current buffer")))

(defvar sweeprolog-mode-syntax-table
  (let ((table (make-syntax-table)))
    (modify-syntax-entry ?_ "_" table)
    (modify-syntax-entry ?+ "." table)
    (modify-syntax-entry ?- "." table)
    (modify-syntax-entry ?= "." table)
    (modify-syntax-entry ?< "." table)
    (modify-syntax-entry ?> "." table)
    (modify-syntax-entry ?| "." table)
    (modify-syntax-entry ?\' "\"" table)
    (modify-syntax-entry ?` "\"" table)
    (modify-syntax-entry ?% "<" table)
    (modify-syntax-entry ?\n ">" table)
    (modify-syntax-entry ?* ". 23b" table)
    (modify-syntax-entry ?/ ". 14" table)
    table))

(defvar sweeprolog-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-l") #'sweeprolog-load-buffer)
    (define-key map (kbd "C-c C-c") #'sweeprolog-colourise-buffer)
    (define-key map (kbd "C-c C-t") #'sweeprolog-top-level)
    (define-key map (kbd "C-c C-o") #'sweeprolog-find-file-at-point)
    (define-key map (kbd "C-c C-d") #'sweeprolog-document-predicate-at-point)
    (define-key map (kbd "C-c C-`")
                (if (fboundp 'flymake-show-buffer-diagnostics)  ;; Flymake 1.2.1+
                    #'sweeprolog-show-diagnostics
                  #'flymake-show-diagnostics-buffer))
    (define-key map (kbd "C-M-^")   #'kill-backward-up-list)
    map)
  "Keymap for `sweeprolog-mode'.")

(easy-menu-define sweeprolog-menu (list sweeprolog-mode-map
                                        sweeprolog-top-level-mode-map)
  "`sweep' menu."
  '("Sweep"
    [ "Set Prolog flag"        sweeprolog-set-prolog-flag t ]
    [ "Install Prolog package" sweeprolog-pack-install    t ]
    [ "Load Prolog buffer"     sweeprolog-load-buffer     t ]
    [ "Find Prolog module"     sweeprolog-find-module     t ]
    [ "Find Prolog predicate"  sweeprolog-find-predicate  t ]
    [ "Insert module template"
      auto-insert
      (eq major-mode 'sweeprolog-mode) ]
    [ "Document current predicate"
      sweeprolog-document-predicate-at-point
      (and (eq major-mode 'sweeprolog-mode)
           (sweeprolog-definition-at-point)) ]
    "--"
    [ "Open top-level"         sweeprolog-top-level       t ]
    [ "Signal top-level"
      sweeprolog-top-level-signal
      (seq-filter (lambda (b)
                    (with-current-buffer b
                      (and (derived-mode-p 'sweeprolog-top-level-mode)
                           sweeprolog-top-level-thread-id)))
                  (buffer-list)) ]
    [ "Open Top-level Menu"    sweeprolog-list-top-levels t ]
    "--"
    [ "Reset sweep"            sweeprolog-restart         t ]
    [ "View sweep messages"    sweeprolog-view-messages   t ]))

(defun sweeprolog-token-boundaries (&optional pos)
  (let ((point (or pos (point))))
    (save-excursion
      (goto-char point)
      (unless (eobp)
       (let ((beg (point))
             (syn (char-syntax (char-after))))
         (cond
          ((or (= syn ?w) (= syn ?_))
           (skip-syntax-forward "w_")
           (if (= (char-syntax (char-after)) ?\()
               (progn
                 (forward-char)
                 (list 'functor beg (point)))
             (list 'symbol beg (point))))
          ((= syn ?\")
           (forward-char)
           (while (and (not (eobp)) (nth 3 (syntax-ppss)))
             (forward-char))
           (list 'string beg (point)))
          ((= syn ?.)
           (skip-syntax-forward ".")
           (list 'operator beg (point)))
          ((= syn ?\()
           (list 'open beg (point)))
          ((= syn ?\))
           (list 'close beg (point)))
          ((= syn ?>) nil)
          (t (list 'else beg (point)))))))))

(defun sweeprolog-next-token-boundaries (&optional pos)
  (let ((point (or pos (point))))
    (save-excursion
      (goto-char point)
      (while (forward-comment 1))
      (unless (eobp)
        (let ((beg (point))
              (syn (char-syntax (char-after))))
          (cond
           ((or (= syn ?w) (= syn ?_))
            (skip-syntax-forward "w_")
            (if (= (char-syntax (char-after)) ?\()
                (progn
                  (forward-char)
                  (list 'functor beg (point)))
              (list 'symbol beg (point))))
           ((= syn ?\")
            (forward-char)
            (while (and (not (eobp)) (nth 3 (syntax-ppss)))
              (forward-char))
            (list 'string beg (point)))
           ((= syn ?.)
            (skip-syntax-forward ".")
            (list 'operator beg (point)))
           ((= syn ?\()
            (list 'open beg (point)))
           ((= syn ?\))
            (list 'close beg (point)))
           ((= syn ?>) nil)
           (t (list 'else beg (point)))))))))

(defun sweeprolog-last-token-boundaries (&optional pos)
  (let ((point (or pos (point)))
        (go t))
    (save-excursion
      (goto-char point)
      (while (and (not (bobp)) go)
        (skip-chars-backward " \t\n")
        (unless (bobp)
          (forward-char -1)
          (if (nth 4 (syntax-ppss))
              (goto-char (nth 8 (syntax-ppss)))
            (setq go nil))))
      (unless (bobp)
        (let ((end (1+ (point)))
              (syn (char-syntax (char-after))))
          (cond
           ((or (= syn ?w) (= syn ?_))
            (skip-syntax-backward "w_")
            (list 'symbol (point) end))
           ((= syn ?\")
            (list 'string (nth 8 (syntax-ppss)) end))
           ((and (= syn ?\()
                 (or (= (char-syntax (char-before)) ?w)
                     (= (char-syntax (char-before)) ?_)))
            (skip-syntax-backward "w_")
            (list 'functor (point) end))
           ((= syn ?.)
            (skip-syntax-backward ".")
            (list 'operator (point) end))
           ((= syn ?\()
            (list 'open (1- end) end))
           ((= syn ?\))
            (list 'close (1- end) end))
           (t (list 'else (1- end) end))))))))

(defun sweeprolog--forward-term (pre)
  (pcase (sweeprolog-next-token-boundaries)
    ('nil
     (signal 'scan-error
             (list "Cannot scan beyond end of buffer."
                   (point-max)
                   (point-max))))
    (`(close ,lbeg ,lend)
     (signal 'scan-error
             (list "Cannot scan beyond closing parenthesis or bracket."
                   lbeg
                   lend)))
    (`(open ,obeg ,_)
     (goto-char obeg)
     (goto-char (scan-lists (point) 1 0))
     (sweeprolog--forward-term pre))
    (`(functor ,_ ,oend)
     (goto-char (1- oend))
     (goto-char (scan-lists (point) 1 0))
     (sweeprolog--forward-term pre))
    (`(operator ,obeg ,oend)
     (if (and (string= "." (buffer-substring-no-properties obeg oend))
              (member (char-syntax (char-after (1+ obeg))) '(?> ? )))
         (signal 'scan-error
                 (list "Cannot scan beyond fullstop."
                       obeg
                       (1+ obeg)))
       (if-let ((opre (sweeprolog-op-infix-precedence
                       (buffer-substring-no-properties obeg oend))))
           (if (> opre pre)
               (signal 'scan-error
                       (list (format "Cannot scan beyond infix operator of higher precedence %s." opre)
                             obeg
                             oend))
             (goto-char oend)
             (sweeprolog--forward-term pre))
         (if-let ((ppre (sweeprolog-op-suffix-precedence
                         (buffer-substring-no-properties obeg oend))))
             (if (> ppre pre)
                 (signal 'scan-error
                         (list (format "Cannot scan beyond suffix operator of higher precedence %s." opre)
                               obeg
                               oend))
               (goto-char oend)
               (sweeprolog--forward-term pre))
           (goto-char oend)
           (sweeprolog--forward-term pre)))))
    (`(symbol ,obeg ,oend)
     (if-let ((opre (sweeprolog-op-infix-precedence
                     (buffer-substring-no-properties obeg oend))))
         (if (> opre pre)
             (signal 'scan-error
                     (list (format "Cannot scan backwards infix operator of higher precedence %s." opre)
                           obeg
                           oend))
           (goto-char oend)
           (sweeprolog--forward-term pre))
       (if-let ((ppre (sweeprolog-op-prefix-precedence
                       (buffer-substring-no-properties obeg oend))))
           (if (> ppre pre)
               (signal 'scan-error
                       (list (format "Cannot scan backwards beyond prefix operator of higher precedence %s." opre)
                             obeg
                             oend))
             (goto-char oend)
             (sweeprolog--forward-term pre))
         (goto-char oend)
         (sweeprolog--forward-term pre))))
    (`(,_ ,_ ,oend)
     (goto-char oend)
     (sweeprolog--forward-term pre))))

(defun sweeprolog-forward-term (pre)
  (condition-case _
      (sweeprolog--forward-term pre)
    (scan-error nil)))

(defun sweeprolog--backward-term (pre)
  (pcase (sweeprolog-last-token-boundaries)
    ('nil
     (signal 'scan-error
             (list "Cannot scan backwards beyond beginning of buffer."
                   (point-min)
                   (point-min))))
    (`(open ,obeg ,oend)
     (signal 'scan-error
             (list "Cannot scan backwards beyond opening parenthesis or bracket."
                   obeg
                   oend)))
    (`(functor ,obeg ,oend)
     (signal 'scan-error
             (list "Cannot scan backwards beyond functor."
                   obeg
                   oend)))
    (`(operator ,obeg ,oend)
     (if (and (string= "." (buffer-substring-no-properties obeg oend))
              (member (char-syntax (char-after (1+ obeg))) '(?> ? )))
         (signal 'scan-error
                 (list "Cannot scan backwards beyond fullstop."
                       obeg
                       (1+ obeg)))
       (if-let ((opre (sweeprolog-op-infix-precedence
                       (buffer-substring-no-properties obeg oend))))
           (if (> opre pre)
               (signal 'scan-error
                       (list (format "Cannot scan backwards beyond infix operator of higher precedence %s." opre)
                             obeg
                             oend))
             (goto-char obeg)
             (sweeprolog--backward-term pre))
         (if-let ((ppre (sweeprolog-op-prefix-precedence
                         (buffer-substring-no-properties obeg oend))))
             (if (> ppre pre)
                 (signal 'scan-error
                         (list (format "Cannot scan backwards beyond prefix operator of higher precedence %s." opre)
                               obeg
                               oend))
               (goto-char obeg)
               (sweeprolog--backward-term pre))
           (goto-char obeg)
           (sweeprolog--backward-term pre)))))
    (`(symbol ,obeg ,oend)
     (if-let ((opre (sweeprolog-op-infix-precedence
                     (buffer-substring-no-properties obeg oend))))
         (if (> opre pre)
             (signal 'scan-error
                     (list (format "Cannot scan backwards beyond infix operator of higher precedence %s." opre)
                           obeg
                           oend))
           (goto-char obeg)
           (sweeprolog--backward-term pre))
       (if-let ((ppre (sweeprolog-op-prefix-precedence
                       (buffer-substring-no-properties obeg oend))))
           (if (> ppre pre)
               (signal 'scan-error
                       (list (format "Cannot scan backwards beyond prefix operator of higher precedence %s." opre)
                             obeg
                             oend))
             (goto-char obeg)
             (sweeprolog--backward-term pre))
         (goto-char obeg)
         (sweeprolog--backward-term pre))))
    (`(close ,lbeg ,_lend)
     (goto-char (nth 1 (syntax-ppss lbeg)))
     (when (or (= (char-syntax (char-before)) ?w)
               (= (char-syntax (char-before)) ?_))
       (skip-syntax-backward "w_"))
     (sweeprolog--backward-term pre))
    (`(,_ ,lbeg ,_)
     (goto-char lbeg)
     (sweeprolog--backward-term pre))))

(defun sweeprolog-backward-term (pre)
  (condition-case _
      (sweeprolog--backward-term pre)
    (scan-error nil)))

(defvar-local sweeprolog--forward-sexp-first-call t)

(defun sweeprolog--backward-sexp ()
  (let ((point (point))
        (prec (pcase (sweeprolog-last-token-boundaries)
                (`(operator ,obeg ,oend)
                 (unless (and nil
                              (string= "." (buffer-substring-no-properties obeg oend))
                              (member (char-syntax (char-after (1+ obeg))) '(?> ? )))
                   (if-let ((pprec
                             (sweeprolog-op-infix-precedence
                              (buffer-substring-no-properties obeg oend))))
                       (progn (goto-char obeg) (1- pprec))
                     0)))
                (_ 0))))
    (condition-case error
        (sweeprolog--backward-term prec)
      (scan-error (when (= point (point))
                    (signal 'scan-error (cdr error)))))))

(defun sweeprolog--forward-sexp ()
  (let ((point (point))
        (prec (pcase (sweeprolog-next-token-boundaries)
                (`(operator ,obeg ,oend)
                 (unless (and nil
                              (string= "." (buffer-substring-no-properties obeg oend))
                              (member (char-syntax (char-after (1+ obeg))) '(?> ? )))
                   (if-let ((pprec
                             (sweeprolog-op-infix-precedence
                              (buffer-substring-no-properties obeg oend))))
                       (progn (goto-char oend) (1- pprec))
                     0)))
                (_ 0))))
    (condition-case error
        (sweeprolog--forward-term prec)
      (scan-error (when (= point (point))
                    (signal 'scan-error (cdr error)))))))

(defun sweeprolog-forward-sexp-function (arg)
  (let* ((times (abs arg))
         (func  (or (and (not (= arg 0))
                         (< 0 (/ times arg))
                         #'sweeprolog--forward-sexp)
                    #'sweeprolog--backward-sexp)))
    (while (< 0 times)
      (funcall func)
      (setq times (1- times)))))

(defun sweeprolog-op-suffix-precedence (token)
  (sweeprolog-open-query "user" "sweep" "sweep_op_info" (cons token (buffer-file-name)))
  (let ((res nil) (go t))
    (while go
      (if-let ((sol (sweeprolog-next-solution))
               (det (car sol))
               (fix (cadr sol))
               (pre (cddr sol)))
          (if (member fix '("xf" "yf"))
              (setq res pre go nil)
            (when (eq '! det)
              (setq go nil)))
        (setq go nil)))
    (sweeprolog-close-query)
    res))

(defun sweeprolog-op-prefix-precedence (token)
  (sweeprolog-open-query "user" "sweep" "sweep_op_info" (cons token (buffer-file-name)))
  (let ((res nil) (go t))
    (while go
      (if-let ((sol (sweeprolog-next-solution))
               (det (car sol))
               (fix (cadr sol))
               (pre (cddr sol)))
          (if (member fix '("fx" "fy"))
              (setq res pre go nil)
            (when (eq '! det)
              (setq go nil)))
        (setq go nil)))
    (sweeprolog-close-query)
    res))

(defun sweeprolog-op-infix-precedence (token)
  (sweeprolog-open-query "user" "sweep" "sweep_op_info" (cons token (buffer-file-name)))
  (let ((res nil) (go t))
    (while go
      (if-let ((sol (sweeprolog-next-solution))
               (det (car sol))
               (fix (cadr sol))
               (pre (cddr sol)))
          (if (member fix '("xfx" "xfy" "yfx"))
              (setq res pre go nil)
            (when (eq '! det)
              (setq go nil)))
        (setq go nil)))
    (sweeprolog-close-query)
    res))

(defun sweeprolog-indent-line-after-functor (fbeg _fend)
  (save-excursion
    (goto-char fbeg)
    (+ (current-column) sweeprolog-indent-offset)))

(defun sweeprolog-indent-line-after-open (fbeg _fend)
  (save-excursion
    (goto-char fbeg)
    (+ (current-column) sweeprolog-indent-offset)))

(defun sweeprolog-indent-line-after-prefix (fbeg _fend _pre)
  (save-excursion
    (goto-char fbeg)
    (+ (current-column) 4)))

(defun sweeprolog-indent-line-after-term ()
  (if-let ((open (nth 1 (syntax-ppss))))
      (save-excursion
        (goto-char open)
        (current-column))
    'noindent))

(defun sweeprolog-indent-line-after-neck (fbeg _fend)
  (save-excursion
    (goto-char fbeg)
    (sweeprolog-backward-term 1200)
    (+ (current-column) sweeprolog-indent-offset)))

(defun sweeprolog-indent-line-after-infix (fbeg _fend pre)
  (save-excursion
    (goto-char fbeg)
    (let ((lim (or (nth 1 (syntax-ppss)) (point-min)))
          (cur (point))
          (go t))
      (while go
        (setq cur (point))
        (sweeprolog-backward-term pre)
        (when (< (point) lim)
          (goto-char cur))
        (when (= (point) cur)
          (setq go nil))))
    (current-column)))

(defun sweeprolog-indent-line ()
  "Indent the current line in a `sweeprolog-mode' buffer."
  (interactive)
  (let ((pos (- (point-max) (point))))
    (back-to-indentation)
    (let ((indent (if (nth 8 (syntax-ppss))
                      'noindent
                    (if-let ((open (and (not (eobp))
                                        (= (char-syntax (char-after)) ?\))
                                        (nth 1 (syntax-ppss)))))
                        (save-excursion
                          (goto-char open)
                          (when (or (= (char-syntax (char-before)) ?w)
                                    (= (char-syntax (char-before)) ?_))
                            (when (save-excursion
                                    (forward-char)
                                    (skip-syntax-forward " " (line-end-position))
                                    (eolp))
                              (skip-syntax-backward "w_")))
                          (current-column))
                      (pcase (sweeprolog-last-token-boundaries)
                        ('nil 'noindent)
                        (`(functor ,lbeg ,lend)
                         (sweeprolog-indent-line-after-functor lbeg lend))
                        (`(open ,lbeg ,lend)
                         (sweeprolog-indent-line-after-open lbeg lend))
                        (`(symbol ,lbeg ,lend)
                         (let ((sym (buffer-substring-no-properties lbeg lend)))
                           (cond
                            ((pcase (sweeprolog-op-prefix-precedence sym)
                               ('nil (sweeprolog-indent-line-after-term))
                               (pre  (sweeprolog-indent-line-after-prefix lbeg lend pre)))))))
                        (`(operator ,lbeg ,lend)
                         (let ((op (buffer-substring-no-properties lbeg lend)))
                           (cond
                            ((string= op ".") 'noindent)
                            ((pcase (sweeprolog-op-infix-precedence op)
                               ('nil nil)
                               (1200 (sweeprolog-indent-line-after-neck lbeg lend))
                               (pre  (sweeprolog-indent-line-after-infix lbeg lend pre))))
                            ((pcase (sweeprolog-op-prefix-precedence op)
                               ('nil nil)
                               (pre  (sweeprolog-indent-line-after-prefix lbeg lend pre)))))))
                        (`(,_ltyp ,_lbeg ,_lend)
                         (sweeprolog-indent-line-after-term)))))))
      (when (numberp indent)
        (unless (= indent (current-column))
          (combine-after-change-calls
            (delete-horizontal-space)
            (insert (make-string indent ? )))))
      (when (> (- (point-max) pos) (point))
        (goto-char (- (point-max) pos)))
      indent)))

(defun sweeprolog-syntax-propertize (start end)
  (goto-char start)
  (let ((case-fold-search nil))
    (funcall
     (syntax-propertize-rules
      ((rx bow (group-n 1 "0'" anychar))
       (1 (unless (save-excursion (nth 8 (syntax-ppss (match-beginning 0))))
            (string-to-syntax "w"))))
      ((rx (group-n 1 "!"))
       (1 (unless (save-excursion (nth 8 (syntax-ppss (match-beginning 0))))
            (string-to-syntax "w")))))
     start end)))

(defun sweeprolog-at-beginning-of-top-term-p ()
  (and (looking-at-p (rx bol graph))
       (not (nth 8 (syntax-ppss)))))

(defun sweeprolog-definition-at-point (&optional point)
  (let* ((p (or point (point)))
         (beg (save-mark-and-excursion
                (goto-char p)
                (unless (sweeprolog-at-beginning-of-top-term-p)
                  (sweeprolog-beginning-of-top-term))
                (max (1- (point)) (point-min))))
         (end (save-mark-and-excursion
                (goto-char p)
                (sweeprolog-end-of-top-term)
                (point)))
         (contents (buffer-substring-no-properties beg end)))
    (sweeprolog-open-query "user"
                           "sweep"
                           "sweep_definition_at_point"
                           (cons contents
                                 (buffer-file-name)))
    (let ((sol (sweeprolog-next-solution)))
      (sweeprolog-close-query)
      (when (sweeprolog-true-p sol)
        (cons (+ beg (cadr sol)) (cddr sol))))))

(defun sweeprolog-insert-pldoc-for-predicate (functor arguments det summary)
  (insert "\n\n")
  (forward-char -2)
  (insert (format "%%!  %s%s is %s.\n%%\n%%   %s"
                  functor
                  (if arguments
                      (concat "(" (mapconcat #'identity arguments ", ") ")")
                    "")
                  det
                  summary))
  (fill-paragraph))

(defun sweeprolog-beginning-of-predicate-at-point (&optional point)
  "Find the beginning of the predicate definition at or above POINT.

Return a cons cell (FUN . ARI) where FUN is the functor name of
the defined predicate and ARI is its arity, or nil if there is no
predicate definition at or directly above POINT."
  (when-let* ((def (sweeprolog-definition-at-point point)))
    (unless (sweeprolog-at-beginning-of-top-term-p)
      (sweeprolog-beginning-of-top-term)
      (backward-char 1))
    (let ((point (point))
          (fun (cadr def))
          (ari (caddr def)))
      (while point
        (sweeprolog-beginning-of-top-term)
        (backward-char 1)
        (if-let* ((ndef (sweeprolog-definition-at-point (point)))
                  (nfun (cadr ndef))
                  (nari (caddr ndef))
                  (same (and (string= fun nfun)
                             (=       ari nari))))
            (progn (message "%s %s" ndef (point)) (setq point (point)))
          (goto-char point)
          (setq point nil)))
      (cons fun ari))))

(defun sweeprolog-document-predicate-at-point (point)
  "Insert PlDoc documentation for the predicate at or above POINT."
  (interactive "d" sweeprolog-mode)
  (when-let* ((pred (sweeprolog-beginning-of-predicate-at-point point))
              (fun  (car pred))
              (ari  (cdr pred)))
    (let ((cur 1)
          (arguments nil))
      (while (<= cur ari)
        (let ((num (pcase cur
                     (1 "First")
                     (2 "Second")
                     (3 "Third")
                     (_ (concat (number-to-string cur) "th")))))
          (push (read-string (concat num " argument: ")) arguments))
        (setq cur (1+ cur)))
      (setq arguments (reverse arguments))
      (let ((det (cadr (read-multiple-choice "Determinism: "
                                             '((?d "det"       "Succeeds exactly once")
                                               (?s "semidet"   "Succeeds at most once")
                                               (?f "failure"   "Always fails")
                                               (?n "nondet"    "Succeeds any number of times")
                                               (?m "multi"     "Succeeds at least once")
                                               (?u "undefined" "Undefined")))))
            (summary (read-string "Summary: ")))
        (sweeprolog-insert-pldoc-for-predicate fun arguments det summary)))))

(defun sweeprolog-file-at-point (&optional point)
  (let* ((p (or point (point)))
         (beg (save-mark-and-excursion
                (goto-char p)
                (unless (sweeprolog-at-beginning-of-top-term-p)
                  (sweeprolog-beginning-of-top-term))
                (max (1- (point)) (point-min))))
         (end (save-mark-and-excursion
                (goto-char p)
                (sweeprolog-end-of-top-term)
                (point)))
         (contents (buffer-substring-no-properties beg end)))
    (sweeprolog-open-query "user"
                      "sweep"
                      "sweep_file_at_point"
                      (list contents
                            (buffer-file-name)
                            (- p beg)))
    (let ((sol (sweeprolog-next-solution)))
      (sweeprolog-close-query)
      (when (sweeprolog-true-p sol)
        (cdr sol)))))

(defun sweeprolog-find-file-at-point (point)
  "Find file specificed by the Prolog file spec at POINT.

Interactively, POINT is set to the current point."
  (interactive "d" sweeprolog-mode)
  (if-let ((file (sweeprolog-file-at-point point)))
      (find-file file)
    (user-error "No file specification found at point!")))

(defun sweeprolog-identifier-at-point (&optional point)
  (let* ((p (or point (point)))
         (beg (save-mark-and-excursion
                (goto-char p)
                (unless (sweeprolog-at-beginning-of-top-term-p)
                  (sweeprolog-beginning-of-top-term))
                (max (1- (point)) (point-min))))
         (end (save-mark-and-excursion
                (goto-char p)
                (sweeprolog-end-of-top-term)
                (point)))
         (contents (buffer-substring-no-properties beg end)))
    (sweeprolog-open-query "user"
                      "sweep"
                      "sweep_identifier_at_point"
                      (list contents
                            (buffer-file-name)
                            (- p beg)))
    (let ((sol (sweeprolog-next-solution)))
      (sweeprolog-close-query)
      (when (sweeprolog-true-p sol)
        (cdr sol)))))

(defun sweeprolog--xref-backend ()
  "Hook for `xref-backend-functions'."
  'sweeprolog)

(cl-defmethod xref-backend-identifier-at-point ((_backend (eql sweeprolog)))
  (sweeprolog-identifier-at-point))

(cl-defmethod xref-backend-identifier-completion-table ((_backend (eql sweeprolog)))
  (completion-table-with-cache #'sweeprolog-predicates-collection))

(cl-defmethod xref-backend-identifier-completion-ignore-case ((_backend (eql sweeprolog)))
  "Case is always significant for Prolog identifiers, so return nil."
  nil)

(cl-defmethod xref-backend-definitions ((_backend (eql sweeprolog)) mfn)
  (when-let ((loc (sweeprolog-predicate-location mfn))
             (path (car loc))
             (line (or (cdr loc) 1)))
    (list (xref-make (concat path ":" (number-to-string line)) (xref-make-file-location path line 0)))))

(cl-defmethod xref-backend-references ((_backend (eql sweeprolog)) mfn)
  (let ((refs (sweeprolog-predicate-references mfn)))
    (seq-map (lambda (loc)
               (let ((by (car loc))
                     (path (cadr loc))
                     (line (or (cddr loc) 1)))
                 (xref-make by (xref-make-file-location path line 0))))
             refs)))

(cl-defmethod xref-backend-apropos ((_backend (eql sweeprolog)) pattern)
  (let ((matches (sweeprolog-predicate-apropos pattern)))
    (seq-map (lambda (match)
               (let ((mfn (car match))
                     (path (cadr match))
                     (line (or (cddr match) 1)))
                 (xref-make mfn
                            (xref-make-file-location path line 0))))
             matches)))

(defun sweeprolog-create-index-function ()
  (sweeprolog-open-query "user"
                    "sweep"
                    "sweep_imenu_index"
                    (buffer-file-name))
  (let ((sol (sweeprolog-next-solution)))
    (sweeprolog-close-query)
    (when (sweeprolog-true-p sol)
      (seq-map (lambda (entry)
                 (let ((car (car entry))
                       (line (cdr entry)))
                   (goto-char (point-min))
                   (forward-line (1- line))
                   (cons car (line-beginning-position))))
               (cdr sol)))))

(defun sweeprolog-highlight-variable (point &optional var)
  "Highlight occurences of the variable VAR in the clause at POINT.

If VAR is nil, clear variable highlighting in the current clause
instead.

Interactively, operate on the clause at point.  If a prefix
argument is specificed, clear variable highlighting in the
current clause.  Otherwise prompt for VAR, defaulting to the
variable at point, if any."
  (interactive (list (point)
                     (unless current-prefix-arg
                       (let ((v (symbol-at-point)))
                         (read-string "Highlight variable: "
                                      nil nil
                                      (and v
                                           (save-match-data
                                             (let ((case-fold-search nil))
                                               (string-match
                                                (rx bos upper)
                                                (symbol-name v))))
                                           (symbol-name v))))))
               sweeprolog-mode sweeprolog-top-level-mode)
  (let ((sweeprolog--variable-at-point var))
    (font-lock-fontify-region point point)))

(defun sweeprolog-cursor-sensor-functions (var)
  (list
   (lambda (_win old dir)
     (if (eq dir 'entered)
         (sweeprolog-highlight-variable (point) var)
       (sweeprolog-highlight-variable old)))))


(defun sweeprolog-predicate-modes-doc (cb)
  (when-let ((pi (sweeprolog-identifier-at-point)))
    (sweeprolog-open-query "user"
                           "sweep"
                           "sweep_documentation"
                           pi)
    (let ((sol (sweeprolog-next-solution)))
      (sweeprolog-close-query)
      (when (sweeprolog-true-p sol)
        (funcall cb (cadr sol) :thing pi :face font-lock-function-name-face)))))

(defvar-local sweeprolog--timer nil)
(defvar-local sweeprolog--colourise-buffer-duration 0.2)


(defun sweeprolog-align-spaces (&optional _)
  "Adjust in-line whitespace between the previous next Prolog tokens.

This command ensures that the next token starts at a column
distanced from the beginning of the previous by a multiple of
four columns, which accommodates the convetional alignment for
if-then-else constructs in SWI-Prolog."
  (interactive "" sweeprolog-mode)
  (let ((bol (line-beginning-position)))
    (pcase (sweeprolog-last-token-boundaries)
      (`(,_ ,lbeg ,lend)
       (when (<= bol lend)
         (let ((num (- 4 (% (- lend lbeg) 4))))
           (when (< 0 num)
             (goto-char lend)
             (combine-after-change-calls
               (delete-horizontal-space)
               (insert (make-string num ? ))))))))))

;;;###autoload
(define-derived-mode sweeprolog-mode prog-mode "sweep"
  "Major mode for reading and editing Prolog code."
  :group 'sweeprolog
  (setq-local comment-start "%")
  (setq-local comment-start-skip "\\(?:/\\*+ *\\|%+ *\\)")
  (setq-local parens-require-spaces nil)
  (setq-local imenu-create-index-function #'sweeprolog-create-index-function)
  (setq-local beginning-of-defun-function #'sweeprolog-beginning-of-top-term)
  (setq-local end-of-defun-function #'sweeprolog-end-of-top-term)
  (setq-local forward-sexp-function #'sweeprolog-forward-sexp-function)
  (setq-local syntax-propertize-function #'sweeprolog-syntax-propertize)
  (setq-local indent-line-function #'sweeprolog-indent-line)
  (setq-local font-lock-defaults
              '(nil
                nil
                nil
                nil
                nil
                (font-lock-fontify-region-function . sweeprolog-colourise-some-terms)))
  (when sweeprolog-enable-eldoc
    (setq-local eldoc-documentation-strategy #'eldoc-documentation-default)
    (add-hook 'eldoc-documentation-functions #'sweeprolog-predicate-modes-doc nil t))
  (when sweeprolog-enable-flymake
    (add-hook 'flymake-diagnostic-functions #'sweeprolog-diagnostic-function nil t)
    (flymake-mode)
    (setq-local next-error-function #'flymake-goto-next-error)
    (add-hook 'window-selection-change-functions
              (let ((buffer (current-buffer)))
                (lambda (win)
                  (when (equal buffer
                               (window-buffer win))
                    (next-error-select-buffer buffer))))
              nil t))
  (when (and (boundp 'cycle-spacing-actions)
             (consp cycle-spacing-actions)
             sweeprolog-enable-cycle-spacing
             (setq-local cycle-spacing-actions (cons #'sweeprolog-align-spaces cycle-spacing-actions))))
  (let ((time (current-time)))
    (sweeprolog-colourise-buffer)
    (setq sweeprolog--colourise-buffer-duration (float-time (time-since time))))
  (sweeprolog--set-buffer-module)
  (add-hook 'xref-backend-functions #'sweeprolog--xref-backend nil t)
  (add-hook 'file-name-at-point-functions #'sweeprolog-file-at-point nil t)
  (add-hook 'completion-at-point-functions #'sweeprolog-completion-at-point-function nil t)
  (when sweeprolog-colourise-buffer-on-idle
    (setq sweeprolog--timer
          (run-with-idle-timer
           (max sweeprolog-colourise-buffer-min-interval
                (* 10 sweeprolog--colourise-buffer-duration))
           t
           (let ((buffer (current-buffer)))
             (lambda ()
               (when (and (buffer-live-p buffer)
                          (not (< sweeprolog-colourise-buffer-max-size
                                  (buffer-size buffer)))
                          (get-buffer-window buffer))
                 (sweeprolog-colourise-buffer buffer))))))
    (add-hook 'kill-buffer-hook
              (lambda ()
                (when (timerp sweeprolog--timer)
                  (cancel-timer sweeprolog--timer)))))
  (when sweeprolog-enable-cursor-sensor
    (cursor-sensor-mode 1)))

(add-to-list 'auto-insert-alist
             '((sweeprolog-mode . "SWI-Prolog module header")
               (or (and (buffer-file-name)
                        (file-name-sans-extension (file-name-base (buffer-file-name))))
                   (read-string "Module name: "))
               "/*"
               "\n    Author:        "
               (progn user-full-name)
               "\n    Email:         "
               (progn user-mail-address)
               (progn sweeprolog-module-header-comment-skeleton)
               "\n*/"
               "\n\n:- module("
               str
               ", [])."
               "\n\n/** <module> "
               str
               "\n\n*/\n\n"))

(defun sweeprolog-top-level-menu--entries ()
  (sweeprolog-open-query "user"
                         "sweep"
                         "sweep_top_level_threads"
                         nil)
  (let ((sol (sweeprolog-next-solution)))
    (sweeprolog-close-query)
    (when (sweeprolog-true-p sol)
      (mapcar (lambda (th)
                (let ((id (nth 0 th))
                      (bn (nth 1 th))
                      (st (nth 2 th))
                      (sz (number-to-string (nth 3 th)))
                      (ct (number-to-string (nth 4 th))))
                  (list id (vector bn st sz ct))))
              (cdr sol)))))

(defun sweeprolog-top-level-menu--refresh ()
  (tabulated-list-init-header)
  (setq tabulated-list-entries (sweeprolog-top-level-menu--entries)))

(defun sweeprolog-top-level-menu-new (name)
  "Create and switch to a new Prolog top-level buffer named NAME."
  (interactive (list
                (read-string
                 "New top-level buffer name: "
                 nil nil
                 (generate-new-buffer-name "*sweeprolog-top-level*")))
               sweeprolog-top-level-menu-mode)
  (sweeprolog-top-level name))

(defun sweeprolog-top-level-menu-signal (goal)
  "Signal the thread of to Top-level Menu entry at point to run GOAL."
  (interactive (list (read-string "Signal goal: ?- "))
               sweeprolog-top-level-menu-mode)
  (if-let ((tid (tabulated-list-get-id)))
      (sweeprolog-signal-thread tid goal)
    (user-error "No top-level menu entry here")))

(defun sweeprolog-top-level-menu-kill ()
  "Kill the buffer of to the `sweep' Top-level Menu entry at point."
  (interactive "" sweeprolog-top-level-menu-mode)
  (if-let ((vec (tabulated-list-get-entry)))
      (let ((bn (seq-elt vec 0)))
        (kill-buffer bn))
    (user-error "No top-level menu entry here")))

(defun sweeprolog-top-level-menu-go-to ()
  "Go to the buffer of to the `sweep' Top-level Menu entry at point."
  (interactive "" sweeprolog-top-level-menu-mode)
  (if-let ((vec (tabulated-list-get-entry)))
      (let* ((bn (seq-elt vec 0))
             (buf (get-buffer bn)))
        (if (buffer-live-p buf)
            (pop-to-buffer buf sweeprolog-top-level-display-action)
          (message "Buffer %s is no longer availabe." bn)))
    (user-error "No top-level menu entry here")))

(defvar sweeprolog-top-level-menu-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'sweeprolog-top-level-menu-go-to)
    (define-key map (kbd "k")   #'sweeprolog-top-level-menu-kill)
    (define-key map (kbd "t")   #'sweeprolog-top-level-menu-new)
    (define-key map (kbd "s")   #'sweeprolog-top-level-menu-signal)
    map)
  "Local keymap for `sweeprolog-top-level-menu-mode' buffers.")

(define-derived-mode sweeprolog-top-level-menu-mode
  tabulated-list-mode "sweep Top-level Menu"
  "Major mode for browsing a list of active `sweep' top-levels."
  (setq tabulated-list-format [("Buffer"      32 t)
                               ("Status"      32 t)
                               ("Stacks Size" 20 t)
                               ("CPU Time"    20 t)])
  (setq tabulated-list-padding 2)
  (setq tabulated-list-sort-key (cons "Buffer" nil))
  (add-hook 'tabulated-list-revert-hook
            #'sweeprolog-top-level-menu--refresh nil t)
  (tabulated-list-init-header))

(defun sweeprolog-list-top-levels ()
  "Display a list of Prolog top-level threads."
  (interactive)
  (let ((buf (get-buffer-create "*sweep Top-levels*")))
    (with-current-buffer buf
      (sweeprolog-top-level-menu-mode)
      (sweeprolog-top-level-menu--refresh)
      (tabulated-list-print))
    (pop-to-buffer-same-window buf)))

(provide 'sweeprolog)

;;; sweeprolog.el ends here
