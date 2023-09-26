;;; sweeprolog-tests.el --- ERT suite for sweep  -*- lexical-binding:t -*-

(require 'sweeprolog)

(remove-hook 'flymake-diagnostic-functions
             #'flymake-proc-legacy-flymake)

(add-hook 'sweeprolog-mode-hook (lambda ()
                                  (setq-local indent-tabs-mode nil
                                              inhibit-message t)))

(defmacro sweeprolog-deftest (name _ doc text &rest body)
  "Define Sweep test NAME with docstring DOC.

The test runs BODY in a `sweeprolog-mode' buffer with initial
contents TEXT.

The second argument is ignored."
  (declare (doc-string 3) (indent 2))
  `(ert-deftest ,(intern (concat "sweeprolog-tests-" (symbol-name name))) ()
     ,doc
     (let ((temp (make-temp-file "sweeprolog-test"
                                 nil
                                 "pl"
                                 ,text))
           (enable-flymake-flag sweeprolog-enable-flymake)
           (inhibit-message t))
       (setq-default sweeprolog-enable-flymake nil)
       (find-file-literally temp)
       (sweeprolog-mode)
       (goto-char (point-min))
       (when (search-forward "-!-" nil t)
         (delete-char -3))
       (unwind-protect
           (progn . ,body)
         (set-buffer-modified-p nil)
         (kill-buffer)
         (sweeprolog-restart)
         (setq-default sweeprolog-enable-flymake enable-flymake-flag)))))

(defconst sweeprolog-tests-greeting
  "Hello from Elisp from Prolog from Elisp from Prolog from Elisp!")

(defun sweeprolog-tests-greet ()
  (sweeprolog--open-query "user" "user"
                          "sweep_funcall"
                          "sweeprolog-tests-greet-1")
  (let ((sol (sweeprolog-next-solution)))
    (sweeprolog-cut-query)
    (cdr sol)))

(defun sweeprolog-tests-greet-1 ()
  sweeprolog-tests-greeting)

(ert-deftest elisp->prolog->elisp->prolog->elisp ()
  "Tests calling Elisp from Prolog from Elisp from Prolog from Elisp."
  (should (equal (sweeprolog--open-query "user" "user"
                                         "sweep_funcall"
                                         "sweeprolog-tests-greet")
                 t))
  (should (equal (sweeprolog-next-solution) (cons '! sweeprolog-tests-greeting)))
  (should (equal (sweeprolog-cut-query) t)))

(ert-deftest lists:member/2 ()
  "Tests calling the Prolog predicate permutation/2 from Elisp."
  (should (equal (sweeprolog--open-query "user" "lists" "member" (list 1 2 3) t) t))
  (should (equal (sweeprolog-next-solution) (cons t 1)))
  (should (equal (sweeprolog-next-solution) (cons t 2)))
  (should (equal (sweeprolog-next-solution) (cons '! 3)))
  (should (equal (sweeprolog-cut-query) t)))

(ert-deftest lists:permutation/2 ()
  "Tests calling the Prolog predicate permutation/2 from Elisp."
  (should (equal (sweeprolog--open-query "user" "lists" "permutation" (list 1 2 3)) t))
  (should (equal (sweeprolog-next-solution) (list t 1 2 3)))
  (should (equal (sweeprolog-next-solution) (list t 1 3 2)))
  (should (equal (sweeprolog-next-solution) (list t 2 1 3)))
  (should (equal (sweeprolog-next-solution) (list t 2 3 1)))
  (should (equal (sweeprolog-next-solution) (list t 3 1 2)))
  (should (equal (sweeprolog-next-solution) (list t 3 2 1)))
  (should (equal (sweeprolog-next-solution) nil))
  (should (equal (sweeprolog-cut-query) t)))

(ert-deftest system:=/2 ()
  "Tests unifying Prolog terms with =/2 from Elisp."
  (should (equal (sweeprolog--open-query "user" "system" "=" (list 1 nil (list "foo" "bar") 3.14)) t))
  (should (equal (sweeprolog-next-solution) (list '! 1 nil (list "foo" "bar") 3.14)))
  (should (equal (sweeprolog-next-solution) nil))
  (should (equal (sweeprolog-cut-query) t)))

(sweeprolog-deftest beginning-of-next-top-term ()
  "Test finding the beginning of the next top term."
  "
foo(Bar) :- bar.
foo(Baz) :- baz.
"
  (should (sweeprolog-beginning-of-next-top-term))
  (should (= (point) 2))
  (should (sweeprolog-beginning-of-next-top-term))
  (should (= (point) 19))
  (should (not (sweeprolog-beginning-of-next-top-term)))
  (should (= (point) 19)))

(sweeprolog-deftest help-echo-for-dependency ()
  "Test that the `help-echo' property is set correctly."
  "
:- use_module(library(lists)).

foo(Foo, Bar) :- flatten(Bar, Baz), member(Foo, Baz).
"
  (goto-char 24)
  (should (string-match "Dependency on .*, resolves calls to flatten/2, member/2"
                        (help-at-pt-kbd-string))))

(sweeprolog-deftest terms-at-point ()
  "Test `sweeprolog-terms-at-point'."
  "
recursive(Var) :-
    (   true
    ->  recursive(Bar)
    ;   var(Baz)
    *-> Bar is foo
    ).
"
  (should (equal (sweeprolog-terms-at-point 81)
                 '("Bar"
                   "Bar is foo"
                   "var(Baz)
    *-> Bar is foo" "true
    ->  recursive(Bar)
    ;   var(Baz)
    *-> Bar is foo"
                   "recursive(Var) :-
    (   true
    ->  recursive(Bar)
    ;   var(Baz)
    *-> Bar is foo
    )"))))

(ert-deftest predicate-location ()
  "Test `sweeprolog-predicate-location'."
  (should (sweeprolog-predicate-location "memory_file:new_memory_file/1")))

(sweeprolog-deftest term-search ()
  "Test `sweeprolog-term-search'."
  "
bar(bar(bar), bar{bar:bar}, [bar,bar|bar]).
foo([Bar|Baz]).
"
  (goto-char (point-min))
  (let ((unread-command-events (listify-key-sequence (kbd "RET"))))
    (sweeprolog-term-search "bar"))
  (should (= (point) 13))
  (let ((unread-command-events (listify-key-sequence (kbd "RET"))))
    (sweeprolog-term-search "bar"))
  (should (= (point) 27))
  (let ((unread-command-events (listify-key-sequence (kbd "RET"))))
    (sweeprolog-term-search "bar"))
  (should (= (point) 34))
  (let ((unread-command-events (listify-key-sequence (kbd "RET"))))
    (sweeprolog-term-search "bar"))
  (should (= (point) 38))
  (let ((unread-command-events (listify-key-sequence (kbd "RET"))))
    (sweeprolog-term-search "bar"))
  (should (= (point) 42)))

(sweeprolog-deftest beginning-of-next-top-term-header ()
  "Test finding the beginning of the first top term."
  "/*
    Author:        Eshel Yaron
    E-mail:        eshel@swi-prolog.org
    Copyright (c)  2022, SWI-Prolog Solutions b.v.
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions
    are met:

    1. Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.

    2. Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in
       the documentation and/or other materials provided with the
       distribution.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
    \"AS IS\" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
    FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
    COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
    BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
    LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
    CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
    LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
    ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
    POSSIBILITY OF SUCH DAMAGE.
*/

/*
foobar :- baz.
*/

:- module(mod"
  (goto-char (point-min))
  (should (sweeprolog-beginning-of-next-top-term))
  (should (= (point) 1509))
  (should (not (sweeprolog-beginning-of-next-top-term)))
  (should (= (point) 1509)))

(sweeprolog-deftest font-lock ()
  "Test semantic highlighting of Prolog code."
  ":- module(foo, [foo/1]).

foo(Foo) :- bar.
"
  (should (equal (get-text-property (+ (point-min) 1)
                                    'font-lock-face)
                 '(sweeprolog-neck
                   sweeprolog-directive)))
  (should (equal (get-text-property (+ (point-min) 2)
                                    'font-lock-face)
                 '(sweeprolog-directive)))
  (should (equal (get-text-property (+ (point-min) 3)
                                    'font-lock-face)
                 '(sweeprolog-built-in
                   sweeprolog-body)))
  (should (equal (get-text-property (+ (point-min) 9)
                                    'font-lock-face)
                 '(sweeprolog-body)))
  (should (equal (get-text-property (+ (point-min) 10)
                                    'font-lock-face)
                 '(sweeprolog-identifier
                   sweeprolog-body)))
  (should (equal (get-text-property (+ (point-min) 13)
                                    'font-lock-face)
                 '(sweeprolog-body)))
  (should (equal (get-text-property (+ (point-min) 16)
                                    'font-lock-face)
                 '(sweeprolog-local
                   sweeprolog-body)))
  (should (equal (get-text-property (+ (point-min) 23)
                                    'font-lock-face)
                 '(sweeprolog-fullstop)))
  (should (equal (get-text-property (+ (point-min) 26)
                                    'font-lock-face)
                 '(sweeprolog-head-exported
                   sweeprolog-clause)))
  (should (equal (get-text-property (+ (point-min) 31)
                                    'font-lock-face)
                 '(sweeprolog-singleton
                   sweeprolog-clause)))
  (should (equal (get-text-property (+ (point-min) 39)
                                    'font-lock-face)
                 '(sweeprolog-undefined
                   sweeprolog-body))))

(sweeprolog-deftest yank-hole ()
  "Test killing and yanking a hole as a plain variable."
  ""
  (sweeprolog-insert-term-with-holes ":-" 2)
  (should (get-text-property (point-min) 'sweeprolog-hole))
  (call-interactively #'kill-region)
  (call-interactively #'yank)
  (should (not (get-text-property (point-min) 'sweeprolog-hole))))

(sweeprolog-deftest insert-term-with-holes ()
  "Test `sweeprolog-insert-term-with-holes'."
  ""
  (sweeprolog-insert-term-with-holes ":-" 2)
  (call-interactively #'kill-region)
  (sweeprolog-insert-term-with-holes "foo" 3)
  (call-interactively #'kill-region)
  (sweeprolog-insert-term-with-holes "bar" 0)
  (call-interactively #'kill-region)
  (sweeprolog-insert-term-with-holes ";" 2)
  (call-interactively #'kill-region)
  (sweeprolog-insert-term-with-holes "->" 2)
  (should (string= (buffer-string)
                   "foo(bar, (_->_;_), _):-_.")))

(sweeprolog-deftest rename-variable ()
  "Tests renaming varialbes."
  "foo(Bar,Baz) :- spam(Baz,Bar)."
  (goto-char (point-min))
  (sweeprolog-rename-variable "Bar" "Spam")
  (sweeprolog-rename-variable "Baz" "Bar")
  (sweeprolog-rename-variable "Spam" "Baz")
  (should (string= (buffer-string)
                   "foo(Baz,Bar) :- spam(Bar,Baz).")))

(sweeprolog-deftest increment-variable ()
  "Tests renaming varialbes."
  "
foo(Bar0,Bar) :-
    spam(Bar0,Bar1),
    bar(Bar1,Bar2),
    baz(Bar2, Bar).
"
  (goto-char (1+ (point-min)))
  (sweeprolog-increment-numbered-variables 1 (point) "Bar1")
  (should (string= (buffer-string)
                   "
foo(Bar0,Bar) :-
    spam(Bar0,Bar2),
    bar(Bar2,Bar3),
    baz(Bar3, Bar).
")))

(sweeprolog-deftest find-references ()
  "Tests `sweeprolog-predicate-references'."
  ":- module(test_sweep_find_references, [caller/0]).

caller :- callee, baz, callee.
caller :- baz, callee, baz.

callee.

baz.
"
  (should (equal (sweeprolog-predicate-references "test_sweep_find_references:callee/0")
                 (list (list "test_sweep_find_references:caller/0" temp 63 6)
                       (list "test_sweep_find_references:caller/0" temp 76 6)
                       (list "test_sweep_find_references:caller/0" temp 99 6)))))

(sweeprolog-deftest forward-many-holes ()
  "Tests jumping over holes with `sweeprolog-forward-hole'."
  "\n"
  (goto-char (point-min))
  (sweeprolog-insert-term-with-holes ":-" 2)
  (deactivate-mark)
  (goto-char (point-max))
  (sweeprolog-insert-term-with-holes ":-" 2)
  (goto-char (point-min))
  (should (= (sweeprolog-count-holes) 4))
  (sweeprolog-forward-hole 2)
  (should (= (point) 5))
  (sweeprolog-forward-hole -1)
  (should (= (point) 2))
  (sweeprolog-forward-hole -2)
  (should (= (point) 8)))

(sweeprolog-deftest plunit-testset-skeleton ()
  "Tests inserting PlUnit test-set blocks."
  ""
  (sweeprolog-plunit-testset-skeleton "foo")
  (should (string= (buffer-string)
                   ":- begin_tests(foo).

test() :- TestBody.

:- end_tests(foo).
"
                   )))

(sweeprolog-deftest auto-insert-module-header ()
  "Tests inserting Prolog module header with `auto-insert'."
  ""
  (let ((auto-insert-query nil))
    (call-interactively #'auto-insert))
  (let ((end (point)))
    (beginning-of-line -1)
    (should (string= (buffer-substring-no-properties (point) end)
                     (concat ":- module("
                             (sweeprolog-format-string-as-atom (file-name-base (buffer-file-name)))
                             ", []).

/** <module> ")))))

(sweeprolog-deftest complete-compound ()
  "Tests completing atoms."
  "
baz(Baz) :- Baz = opa
"
  (goto-char (point-max))
  (backward-char)
  (call-interactively #'completion-at-point)
  (should (string= (buffer-string)
                   "
baz(Baz) :- Baz = opaque(_)
"
                   )))

(sweeprolog-deftest complete-non-terminal ()
  "Tests completing DCG non-terminals."
  "
barbaz --> foo.

foo --> barb"
  (goto-char (point-max))
  (call-interactively #'completion-at-point)
  (should (string= (buffer-string)
                   "
barbaz --> foo.

foo --> barbaz"

                   ))
  (insert ".\n\nfoo => barb")
  (call-interactively #'completion-at-point)
  (should (string= (buffer-string)
                   "
barbaz --> foo.

foo --> barbaz.

foo => barbaz(_, _)"

                   )))

(sweeprolog-deftest complete-predicate-with-args ()
  "Tests completing predicate calls."
  "
:- module(foobarbaz, []).

%!  foobarbaz(:Bar, ?Baz:integer) is det.

foobarbaz(_, 5) :- spam.

spam :- foobarb
"
  (goto-char (point-max))
  (backward-char)
  (call-interactively #'completion-at-point)
  (should (string= (buffer-string)
                   "
:- module(foobarbaz, []).

%!  foobarbaz(:Bar, ?Baz:integer) is det.

foobarbaz(_, 5) :- spam.

spam :- foobarbaz(Bar, Baz)
"
                   )))

(sweeprolog-deftest complete-predicate ()
  "Tests completing predicate calls."
  "
baz(Baz) :- findall(X, b_g
"
  (goto-char (point-max))
  (backward-char)
  (call-interactively #'completion-at-point)
  (should (string= (buffer-string)
                   "
baz(Baz) :- findall(X, b_getval(Name, Value)
"
                   )))

(sweeprolog-deftest complete-variable ()
  "Tests completing variable names."
  "
baz(Baz) :- bar(B).
"
  (goto-char (point-max))
  (backward-word)
  (forward-word)
  (call-interactively #'completion-at-point)
  (should (string= (buffer-string)
                   "
baz(Baz) :- bar(Baz).
"
                   )))

(sweeprolog-deftest cap-variable ()
  "Completion at point for variable names."
  "baz(Baz) :- bar(B-!-)."
  (should (pcase (sweeprolog-completion-at-point)
            (`(17 18 ("Baz") . ,_) t))))

(sweeprolog-deftest cap-local-predicate ()
  "Completion at point for local predicates."
  "%!  foobar(+Baz) is det.

foobar(Baz) :- baz(Baz).
baz(Baz) :- fooba-!-"
  (let ((cap (sweeprolog-completion-at-point)))
    (should (= 64 (nth 0 cap)))
    (should (= 69 (nth 1 cap)))
    (should (equal '(("foobar(Baz)" compound "term_position" 0 11 0 6 ((compound "-" 7 10))))
                   (nth 2 cap)))))

(sweeprolog-deftest cap-autoloaded-predicate ()
  "Completion at point for remote predicates."
  "%!  foobar(+Baz) is det.

foobar(Baz) :- baz(Baz).
baz(Baz) :- lists:memberc-!-"
  (let ((cap (sweeprolog-completion-at-point)))
    (should (= 70 (nth 0 cap)))
    (should (= 77 (nth 1 cap)))
    (should (equal '(("memberchk(Elem, List)" compound "term_position" 0 21 0 9 ((compound "-" 10 14) (compound "-" 16 20))))
                   (nth 2 cap)))))

(sweeprolog-deftest cap-compound ()
  "Completion at point for compound terms."
  "foobar(bar).

foobar(Baz) :- Baz = foob-!-"
  (let ((cap (sweeprolog-completion-at-point)))
    (should (= 36 (nth 0 cap)))
    (should (= 40 (nth 1 cap)))
    (should (equal '(("foobar(_)" compound "term_position" 0 9 0 6 ((compound "-" 7 8))))
                   (nth 2 cap)))))

(sweeprolog-deftest cap-compound-with-arity ()
  "Completion at point for compound terms of a given arity."
  "foobar(Baz) :- Baz = tabl-!-tate(a,b,c)"
  (let ((cap (sweeprolog-completion-at-point)))
    (should (= 22 (nth 0 cap)))
    (should (= 30 (nth 1 cap)))
    (should (equal '("table_cell_state" "table_state") (nth 2 cap)))))

(sweeprolog-deftest cap-local-predicate-functor ()
  "Completion at point for predicate functors."
  "%!  foobar(+Baz) is det.

foobar(Baz) :- baz(Baz).
baz(Baz) :- fooba-!-("
  (let ((cap (sweeprolog-completion-at-point)))
    (should (= 64 (nth 0 cap)))
    (should (= 69 (nth 1 cap)))
    (should (equal '("foobar") (nth 2 cap)))))

(sweeprolog-deftest cap-compound-functor ()
  "Completion at point for compound term functors."
  "foobar(bar).

foobar(Baz) :- Baz = foob-!-("
  (let ((cap (sweeprolog-completion-at-point)))
    (should (= 36 (nth 0 cap)))
    (should (= 40 (nth 1 cap)))
    (should (equal '("foobar") (nth 2 cap)))))

(sweeprolog-deftest cap-quoted-compound-functor ()
  "Completion at point for quoted functors."
  "foobar('Baz baz'(bar)).

foobar(Baz) :- Baz = 'Baz -!-'("
  (let ((cap (sweeprolog-completion-at-point)))
    (should (= 47 (nth 0 cap)))
    (should (= 53 (nth 1 cap)))
    (should (equal '("'Baz baz'") (nth 2 cap)))))

(sweeprolog-deftest cap-quoted-compound ()
  "Completion at point for compounds with a quoted functor."
  "foobar('Baz baz'(bar)).

foobar(Baz) :- Baz = 'Baz -!-"
  (let ((cap (sweeprolog-completion-at-point)))
    (should (= 47 (nth 0 cap)))
    (should (= 52 (nth 1 cap)))
    (should (equal '(("'Baz baz'(_)" compound "term_position" 0 12 0 9 ((compound "-" 10 11))))
                   (nth 2 cap)))))

(sweeprolog-deftest mark-predicate ()
  "Test marking predicate definition."
  "
:- module(baz, []).


%!  baz(-Baz) is semidet.
%
%   Foobar.

baz(Baz) :- bar(Baz).
baz(_) :- false.

%!  bar(-Bar) is semidet.
%
%   Spam.

bar(Bar) :- baz(Bar).
"
  (call-interactively #'sweeprolog-mark-predicate)
  (should (= (point) 24))
  (should (= (mark) 104)))

(sweeprolog-deftest export-predicate-with-comment-header ()
  "Test exporting a predicate after a comment header."
  "/*
Sed id ligula quis est convallis tempor.  Nam vestibulum accumsan
nisl.  Sed diam.  Pellentesque tristique imperdiet tortor.  Fusce
sagittis, libero non molestie mollis, magna orci ultrices dolor,
at vulputate neque nulla lacinia eros.
*/
:- module(sweeprolog_test_export_predicate, []).

%!  foo(+Bar) is det.

foo(Bar) :- bar(Bar).
"
  (goto-char (point-max))
  (backward-word)
  (call-interactively #'sweeprolog-export-predicate)
  (should (equal (buffer-string)
                 "/*
Sed id ligula quis est convallis tempor.  Nam vestibulum accumsan
nisl.  Sed diam.  Pellentesque tristique imperdiet tortor.  Fusce
sagittis, libero non molestie mollis, magna orci ultrices dolor,
at vulputate neque nulla lacinia eros.
*/
:- module(sweeprolog_test_export_predicate, [foo/1  % +Bar
                                            ]).

%!  foo(+Bar) is det.

foo(Bar) :- bar(Bar).
")))

(sweeprolog-deftest export-predicate ()
  "Test exporting a predicate."
  "
:- module(sweeprolog_test_export_predicate, []).

%!  foo(+Bar) is det.

foo(Bar) :- bar(Bar).
"
  (goto-char (point-max))
  (backward-word)
  (call-interactively #'sweeprolog-export-predicate)
  (should (equal (buffer-string)
                 "
:- module(sweeprolog_test_export_predicate, [foo/1  % +Bar
                                            ]).

%!  foo(+Bar) is det.

foo(Bar) :- bar(Bar).
")))

(sweeprolog-deftest export-predicate-with-op ()
  "Test exporting a predicate in presence of an exported operator."
  "
:- module(tester,
          [ instantiate_test_template/4,  % +In,+Replacement,-Dict,-Map
            op(200, fy, @)		  % @name
          ]).

%!  foo(+Bar) is det.

foo(Bar).
"
  (goto-char (point-max))
  (backward-word)
  (call-interactively #'sweeprolog-export-predicate)
  (should (equal (buffer-string)
                 "
:- module(tester,
          [ instantiate_test_template/4, % +In,+Replacement,-Dict,-Map
            foo/1,                       % +Bar
            op(200, fy, @)		 % @name
          ]).

%!  foo(+Bar) is det.

foo(Bar).
"
                 )))

(sweeprolog-deftest export-predicate-with-only-op ()
  "Test exporting a predicate in presence of only exported operators."
  "
:- module(tester,
          [ op(200, fy, @)		  % @name
          ]).

%!  foo(+Bar) is det.

foo(Bar).
"
  (goto-char (point-max))
  (backward-word)
  (call-interactively #'sweeprolog-export-predicate)
  (should (equal (buffer-string)
                 "
:- module(tester,
          [ foo/1,         % +Bar
            op(200, fy, @) % @name
          ]).

%!  foo(+Bar) is det.

foo(Bar).
"
                 )))

(sweeprolog-deftest identifier-at-point ()
  "Test recognizing predicate invocations."
  "foo(Bar) :- bar(Bar)."
  (goto-char (point-max))
  (backward-word)
  (should (equal (sweeprolog-identifier-at-point)
                 "user:bar/1")))

(sweeprolog-deftest dcg-identifier-at-point ()
  "Test recognizing DCG grammar rule definitions."
  ":- module(foobarbaz, []).
foo(Bar) --> bar(Bar)."
  (goto-char (point-max))
  (beginning-of-line)
  (should (equal (sweeprolog-identifier-at-point)
                 "foobarbaz:foo//1")))

(sweeprolog-deftest dcg-completion-at-point ()
  "Test completing DCG grammar rule invocation."
  ":- use_module(library(dcg/high_order)).
foo(Bar) --> optiona"
  (goto-char (point-max))
  (complete-symbol nil)
  (should (string= (buffer-string)
                   ":- use_module(library(dcg/high_order)).
foo(Bar) --> optional(Match, Default)")))

(sweeprolog-deftest definition-at-point ()
  "Test recognizing predicate definitions."
  "foo(Bar) :- bar(Bar)."
  (goto-char (point-max))
  (backward-word)
  (should (equal (sweeprolog-definition-at-point)
                 '(1 "foo" 1 21 ":-" nil))))

(sweeprolog-deftest syntax-errors ()
  "Test clearing syntax error face after errors are fixed."
  "
:- module(baz, []).


%!  baz(-Baz) is semidet.
%
%   Foobar.

baz(Baz) :- bar(Baz).
baz(Baz) :- Bar, Baz.

%!  bar(-Bar) is semidet.
%
%   Spam.

bar(Bar) :- baz(Bar).

% comment before eob...
"
  (goto-char (point-min))
  (search-forward ".\n" nil t)
  (replace-match ",,\n" nil t)
  (delete-char -3)
  (redisplay)
  (insert ".")
  (redisplay)
  (should (= (point-max)
             (prop-match-end
              (text-property-search-forward
               'font-lock-face
               '(sweeprolog-syntax-error
                 sweeprolog-around-syntax-error))))))

(sweeprolog-deftest file-at-point ()
  "Test recognizing file specifications."
  ":- use_module(library(lists))."
  (goto-char (point-max))
  (backward-word)
  (let ((fsap (sweeprolog-file-at-point)))
    (should fsap)
    (should (string= "lists" (file-name-base fsap)))))

(sweeprolog-deftest dwim-next-clause-fact ()
  "Tests inserting a new clause after a fact."
  "
foo.-!-"
  (sweeprolog-insert-term-dwim)
  (should (string= (buffer-string)
                   "
foo.
foo :- Body.
")))

(sweeprolog-deftest dwim-next-clause-module-qualified-dcg ()
  "Tests inserting new module-qualified DCG non-terminal."
  "
spam:foo --> bar.
"
  (goto-char (point-max))
  (sweeprolog-insert-term-dwim)
  (should (string= (buffer-string)
                   "
spam:foo --> bar.
spam:foo --> Body.

"
                   )))

(sweeprolog-deftest dwim-next-clause-args ()
  "Tests inserting new clause with arguments."
  "
%!  foo(+Bar) is det.

foo(bar) :- bar.
"
  (goto-char (point-max))
  (sweeprolog-insert-term-dwim)
  (should (string= (buffer-string)
                   "
%!  foo(+Bar) is det.

foo(bar) :- bar.
foo(Bar) :- Body.

")))

(sweeprolog-deftest dwim-next-clause-module-qualified ()
  "Tests inserting new module-qualified clause."
  "
spam:foo :- bar.
"
  (goto-char (point-max))
  (sweeprolog-insert-term-dwim)
  (should (string= (buffer-string)
                   "
spam:foo :- bar.
spam:foo :- Body.

"
                   )))

(sweeprolog-deftest dwim-next-clause-prolog-message ()
  "Tests inserting new `prolog:message/1' clause."
  "
prolog:message(foo(bar, Baz, Spam)) -->
    [ 'baz: ~D spam: ~w'-[Baz, Spam] ].
"
  (goto-char (point-max))
  (sweeprolog-insert-term-dwim)
  (should (string= (buffer-string)
                   "
prolog:message(foo(bar, Baz, Spam)) -->
    [ 'baz: ~D spam: ~w'-[Baz, Spam] ].
prolog:message(_) --> Body.

"
                   )))

(sweeprolog-deftest dwim-next-clause-dcg ()
  "Tests inserting a non-terminal with `sweeprolog-insert-term-dwim'."
  "
foo --> bar.-!-"
  (sweeprolog-insert-term-dwim)
  (should (string= (buffer-string)
                   "
foo --> bar.
foo --> Body.
")))


(sweeprolog-deftest dwim-next-clause-dcg-with-pldoc ()
  "Test completing DCG grammar rule invocation."
  "
:- module(dcg_completion_at_point_with, []).

%!  foo(+Bar)// is det.

foo(bar) --> baz(bar).
"
  (goto-char (point-max))
  (sweeprolog-insert-term-dwim)
  (should (string= (buffer-string)
                   "
:- module(dcg_completion_at_point_with, []).

%!  foo(+Bar)// is det.

foo(bar) --> baz(bar).
foo(Bar) --> Body.

")))

(sweeprolog-deftest dwim-next-clause-ssu ()
  "Tests inserting an SSU rule with `sweeprolog-insert-term-dwim'."
  "
foo => bar.-!-"
  (sweeprolog-insert-term-dwim)
  (should (string= (buffer-string)
                   "
foo => bar.
foo => Body.
")))

(sweeprolog-deftest dwim-next-clause ()
  "Tests inserting a new clause with `sweeprolog-insert-term-dwim'."
  "
foo :- bar.-!-"
  (sweeprolog-insert-term-dwim)
  (should (string= (buffer-string)
                   "
foo :- bar.
foo :- Body.
")))

(sweeprolog-deftest update-dependencies-no-autoload ()
  "Tests adding a use_module/2 directive."
  "
:- module(foo, [bar/1]).

/** <module> Foo

*/

bar(X) :- arithmetic_function(X).
"
  (call-interactively #'sweeprolog-update-dependencies)
  (should (string= (buffer-string)
                   "
:- module(foo, [bar/1]).
:- use_module(library(arithmetic), [arithmetic_function/1]).

/** <module> Foo

*/

bar(X) :- arithmetic_function(X).
")))

(sweeprolog-deftest append-dependencies ()
  "Tests making implicit autoloads explicit with existing directive."
  "
:- module(foo, [bar/1]).

/** <module> Foo

*/

:- use_module(library(lists), [ member/2
                              ]).

bar(X) :- member(X, [1,2,3]).
bar(X) :- permutation(X, [1,2,3]).
"
  (call-interactively #'sweeprolog-update-dependencies)
  (should (string= (buffer-string)
                   "
:- module(foo, [bar/1]).

/** <module> Foo

*/

:- use_module(library(lists), [ member/2,
                                permutation/2
                              ]).

bar(X) :- member(X, [1,2,3]).
bar(X) :- permutation(X, [1,2,3]).
"
                   )))

(sweeprolog-deftest update-dependencies-without-inference ()
  "Tests setting `sweeprolog-dependency-directive' to `autoload'."
  "
:- module(foo, [bar/1]).

/** <module> Foo

*/

:- use_module(library(lists), [ member/2
                              ]).

bar(X) :- member(X, [1,2,3]).
bar(X) :- maplist(X, [1,2,3]).
"
  (let ((sweeprolog-dependency-directive 'autoload))
    (call-interactively #'sweeprolog-update-dependencies))
  (should (string= (buffer-string)
                   "
:- module(foo, [bar/1]).

/** <module> Foo

*/

:- use_module(library(lists), [ member/2
                              ]).
:- autoload(library(apply), [maplist/2]).

bar(X) :- member(X, [1,2,3]).
bar(X) :- maplist(X, [1,2,3]).
"
                   )))

(sweeprolog-deftest update-dependencies-without-inference-2 ()
  "Tests setting `sweeprolog-dependency-directive' to `use-module'."
  "
:- module(foo, [bar/1]).

/** <module> Foo

*/

bar(X) :- member(X, [1,2,3]).
bar(X) :- maplist(X, [1,2,3]).
"
  (let ((sweeprolog-dependency-directive 'use-module))
    (call-interactively #'sweeprolog-update-dependencies))
  (should (string= (buffer-string)
                   "
:- module(foo, [bar/1]).
:- use_module(library(apply), [maplist/2]).
:- use_module(library(lists), [member/2]).

/** <module> Foo

*/

bar(X) :- member(X, [1,2,3]).
bar(X) :- maplist(X, [1,2,3]).
"
                   )))

(sweeprolog-deftest update-dependencies-with-use-module ()
  "Tests updating dependencies in presence of use_module directives."
  "
:- module(foo, [bar/1]).

/** <module> Foo

*/

:- use_module(library(lists), [ member/2
                              ]).

bar(X) :- member(X, [1,2,3]).
bar(X) :- maplist(X, [1,2,3]).
"
  (call-interactively #'sweeprolog-update-dependencies)
  (should (string= (buffer-string)
                   "
:- module(foo, [bar/1]).

/** <module> Foo

*/

:- use_module(library(lists), [ member/2
                              ]).
:- use_module(library(apply), [maplist/2]).

bar(X) :- member(X, [1,2,3]).
bar(X) :- maplist(X, [1,2,3]).
"
                   )))

(sweeprolog-deftest update-dependencies-autoload-from-package ()
  "Tests making implicit autoloads from a package explicit."
  "
:- module(foo, [bar/1]).

/** <module> Foo

*/

bar(X) :- http_open(X, X, X).
"
  (call-interactively #'sweeprolog-update-dependencies)
  (should (string= (buffer-string)
                   "
:- module(foo, [bar/1]).
:- autoload(library(http/http_open), [http_open/3]).

/** <module> Foo

*/

bar(X) :- http_open(X, X, X).
")))

(sweeprolog-deftest update-dependencies ()
  "Tests making implicit autoloads explicit."
  "
:- module(foo, [bar/1]).

/** <module> Foo

*/

bar(X) :- member(X, [1,2,3]).
"
  (call-interactively #'sweeprolog-update-dependencies)
  (should (string= (buffer-string)
                   "
:- module(foo, [bar/1]).
:- autoload(library(lists), [member/2]).

/** <module> Foo

*/

bar(X) :- member(X, [1,2,3]).
"

                   ))
  (goto-char (point-max))
  (insert "bar(X) :- permutation(X, [1,2,3]).")
  (call-interactively #'sweeprolog-update-dependencies)
  (should (string= (buffer-string)
                   "
:- module(foo, [bar/1]).
:- autoload(library(lists), [member/2, permutation/2]).

/** <module> Foo

*/

bar(X) :- member(X, [1,2,3]).
bar(X) :- permutation(X, [1,2,3]).")))

(sweeprolog-deftest dwim-define-nested-phrase ()
  "Tests complex undefined predicate scenario."
  "
foo --> {baz, phrase(bar, Baz)}.
"
  (goto-char (point-max))
  (backward-word 2)
  (sweeprolog-insert-term-dwim)
  (call-interactively #'kill-region)
  (insert "foo")
  (should (string= (buffer-string)
                   "
foo --> {baz, phrase(bar, Baz)}.

bar --> foo.
"
                   )))

(sweeprolog-deftest dwim-define-phrase-non-terminal ()
  "Tests defining an undefined DCG non-terminal from a clause."
  "
foo :- phrase(bar, Baz).
"
  (goto-char (point-max))
  (backward-word 2)
  (sweeprolog-insert-term-dwim)
  (call-interactively #'kill-region)
  (insert "foo")
  (should (string= (buffer-string)
                   "
foo :- phrase(bar, Baz).

bar --> foo.
"
                   )))

(sweeprolog-deftest dwim-define-braces-predicate ()
  "Tests defining an undefined predicate from a DCG non-terminal."
  "
foo --> {bar}.
-!-"
  (backward-word)
  (sweeprolog-insert-term-dwim)
  (call-interactively #'kill-region)
  (insert "foo")
  (should (string= (buffer-string)
                   "
foo --> {bar}.

bar :- foo.
"
                   )))

(sweeprolog-deftest document-predicate ()
  "Tests documenting a predicate."
  "foo(Bar) :- baz(Bar).
"
  (goto-char (point-max))
  (let ((sweeprolog-read-predicate-documentation-function
         #'sweeprolog-read-predicate-documentation-with-holes))
    (sweeprolog-document-predicate-at-point (point)))
  (should (string= (buffer-string)
                   "%!  foo(_) is Det.

foo(Bar) :- baz(Bar).
")))

(sweeprolog-deftest document-non-terminal ()
  "Tests documenting a DCG non-terminal."
  "foo(Bar) --> baz(Bar).
"
  (goto-char (point-max))
  (let ((sweeprolog-read-predicate-documentation-function
         #'sweeprolog-read-predicate-documentation-with-holes))
    (sweeprolog-document-predicate-at-point (point)))
  (should (string= (buffer-string)
                   "%!  foo(_)// is Det.

foo(Bar) --> baz(Bar).
")))

(sweeprolog-deftest dwim-define-non-terminal ()
  "Tests defining an undefined DCG non-terminal."
  "
foo --> bar.
-!-"
  (backward-word)
  (sweeprolog-insert-term-dwim)
  (call-interactively #'kill-region)
  (insert "foo")
  (should (string= (buffer-string)
                   "
foo --> bar.

bar --> foo.
"
                   )))

(sweeprolog-deftest dwim-define-predicate ()
  "Tests defining a new predicate with `sweeprolog-insert-term-dwim'."
  "
foo :- bar.
-!-"
  (backward-word)
  (sweeprolog-insert-term-dwim)
  (call-interactively #'kill-region)
  (insert "foo")
  (should (string= (buffer-string)
                   "
foo :- bar.

bar :- foo.
"
                   )))


(sweeprolog-deftest dwim-define-predicate-above ()
  "Tests adherence to `sweeprolog-new-predicate-location-function'."
  "
%!  foo is det.

foo :- bar.
-!-"
  (backward-word)
  (let ((sweeprolog-new-predicate-location-function
         #'sweeprolog-new-predicate-location-above-current))
    (sweeprolog-insert-term-dwim))
  (call-interactively #'kill-region)
  (insert "foo")
  (should (string= (buffer-string)
                   "
bar :- foo.

%!  foo is det.

foo :- bar.
"
                   )))

(sweeprolog-deftest end-of-top-term-with-univ ()
  "Tests detecting the fullstop in presence of `=..'."
  "
html_program_section(Section, Dict) -->
    { _{module:M, options:Options} :< Dict,
      Content = Dict.get(Section),
      Content \= [],
      scasp_code_section_title(Section, Default, Title),
      Opt =.. [Section,true],
      option(Opt, Options, Default)
    },
    !,
    html(h2(Title)),
    (   {Section == query}
    ->  {ovar_set_bindings(Dict.bindings)},
        html_query(M:Content, Options)
    ;   sequence(predicate_r(M:Options), Content)
    ).
"
  (goto-char (point-min))
  (sweeprolog-end-of-top-term)
  (should (= (point) 466)))

(sweeprolog-deftest fullstop-detection ()
  "Tests detecting the fullstop in presence of confusing comments."
  "
scasp_and_show(Q, Model, Tree) :-
    scasp_mode(M0, T0),
    setup_call_cleanup(
        set_scasp_mode(Model, Tree),
        (   scasp(Q, [])
        ;   false                       % make always nondet.
        ),
        set_scasp_mode(M0, T0)).
"
  (goto-char (point-min))
  (sweeprolog-end-of-top-term)
  (should (= (point) 252)))

(sweeprolog-deftest beginning-of-predicate-definition-near-bob ()
  "Test finding the beginning of the first predicate definition."
  "foo :- bar."
  (goto-char (point-min))
  (sweeprolog-beginning-of-predicate-at-point)
  (should (= (point) (point-min))))

(sweeprolog-deftest align-spaces-in-line-comment ()
  "Test using `sweeprolog-align-spaces' in a line comment."
  "
%!  foo is det.
%
%-!-"
  (sweeprolog-align-spaces)
  (should (string= (buffer-string)
                   "
%!  foo is det.
%
%   ")))

(sweeprolog-deftest auto-fill-pldoc-comments ()
  "Test writing PlDoc comments with `auto-fill-mode' enable."
  ""
  (auto-fill-mode)
  (seq-do (lambda (c)
            (let ((last-command-event c))
              (call-interactively #'self-insert-command)))
          "
%!  foobar is det.
%
%   Nam vestibulum accumsan nisl.  Donec pretium posuere tellus.  Aenean in sem ac leo mollis blandit.  Nam a sapien.  Proin quam nisl, tincidunt et, mattis eget, convallis nec, purus.
"
          )
  (should (string= (buffer-string)
                   "
%!  foobar is det.
%
%   Nam vestibulum accumsan nisl.  Donec pretium posuere tellus.
%   Aenean in sem ac leo mollis blandit.  Nam a sapien.  Proin quam
%   nisl, tincidunt et, mattis eget, convallis nec, purus.
")))

(sweeprolog-deftest electric-layout ()
  "Test `sweeprolog-electric-layout-mode'."
  ""
  (sweeprolog-electric-layout-mode)
  (seq-do (lambda (c)
            (let ((last-command-event c))
              (call-interactively #'self-insert-command)))
          "
foobar :-
(bar
;baz
->spam
).
")
  (should (string= (buffer-string)
                   "
foobar :-
    (   bar
    ;   baz
    ->  spam
    ).
"
                   )))

(sweeprolog-deftest end-of-top-term-with-other-symbols ()
  "Tests detecting the fullstop in presence of `.=.'."
  "
loop_term(I, Arity, Goal1, Goal2) :-
    I =< Arity,
    arg(I, Goal1, A),
    arg(I, Goal2, B),
    (   loop_var_disequality(A,B)
    ->  true
    ;   A .=. B,
        I2 is I+1,
        loop_term(I2, Arity, Goal1, Goal2)
    ).
"
  (goto-char (point-min))
  (sweeprolog-end-of-top-term)
  (should (= (point) 232)))

(sweeprolog-deftest beginning-of-next-top-term-at-last-clause ()
  "Test finding the beginning of next top term when there isn't one."
  "
test_bindings(Name-Value) -->
    ['    '~w = ~p'-[Name-Value] ]..
"
  (goto-char 43)
  (backward-delete-char 1)
  (end-of-line)
  (backward-delete-char 1)
  (should (string= (buffer-string) "
test_bindings(Name-Value) -->
    ['    ~w = ~p'-[Name-Value] ].
"
                   )))

(sweeprolog-deftest infer-indent-style ()
  "Test inferring indentation style from buffer contents."
  "
foo :-
  bar.-!-"
  (sweeprolog-infer-indent-style)
  (should (= sweeprolog-indent-offset 2))
  (should (not indent-tabs-mode)))

(sweeprolog-deftest infer-indent-style-tab ()
  "Test inferring tab indentation from buffer contents."
  "
foo :-
\tbar.-!-"
  (sweeprolog-infer-indent-style)
  (should (= sweeprolog-indent-offset tab-width))
  (should indent-tabs-mode))

(sweeprolog-deftest custom-indentation ()
  "Test forcefully setting custom indentation levels."
  "
foo :-
    repeat,
      bar,
      baz-!-"
  (call-interactively #'indent-for-tab-command)
  (should (string= (buffer-substring-no-properties (point-min) (point-max))
                   "
foo :-
    repeat,
      bar,
      baz")))

(defun sweeprolog-test-indentation (given expected)
  (with-temp-buffer
    (sweeprolog-mode)
    (insert given)
    (let ((inhibit-message t))
      (indent-region-line-by-line (point-min) (point-max)))
    (should (string= (buffer-substring-no-properties (point-min) (point-max))
                     expected))))

(defun sweeprolog-test-context-callable-p (given expected)
  (with-temp-buffer
    (sweeprolog-mode)
    (insert given)
    (should (equal expected (sweeprolog-context-callable-p)))))

(ert-deftest context-callable ()
  "Test recognizing callable contexts."
  (sweeprolog-test-context-callable-p "foo(Bar) :- include( " 1)
  (sweeprolog-test-context-callable-p "foo(Bar) --> " 2)
  (sweeprolog-test-context-callable-p "foo(Bar) --> {include(" 1)
  (sweeprolog-test-context-callable-p "foo(Bar) --> {include(phrase(" 2)
  (sweeprolog-test-context-callable-p "foo" nil)
  (sweeprolog-test-context-callable-p "foo(" nil)
  (sweeprolog-test-context-callable-p "foo(bar)" nil)
  (sweeprolog-test-context-callable-p "foo(bar) :- " 0)
  (sweeprolog-test-context-callable-p "foo(bar) :- baz(" nil)
  (sweeprolog-test-context-callable-p "foo(bar) :- baz(bar" nil)
  (sweeprolog-test-context-callable-p "foo(bar) :- baz(bar), " 0)
  (sweeprolog-test-context-callable-p "foo(bar) :- baz(bar), findall(" nil)
  (sweeprolog-test-context-callable-p "foo(bar) :- baz(bar), findall(X" nil)
  (sweeprolog-test-context-callable-p "foo(bar) :- baz(bar), findall(X," 0)
  (sweeprolog-test-context-callable-p "foo(bar) :- baz(bar), findall(X, false" 0)
  (sweeprolog-test-context-callable-p "foo(bar) :- baz(bar), findall(X, false," nil)
  (sweeprolog-test-context-callable-p "foo(bar) :- baz(bar), findall(X, false, Xs). " nil))

(ert-deftest indentation ()
  "Tests indentation rules."
  (sweeprolog-test-indentation
   "
colourise_declaration(Module:Goal, table, TB,
                      term_position(_,_,QF,QT,
"
   "
colourise_declaration(Module:Goal, table, TB,
                      term_position(_,_,QF,QT,
")
  (sweeprolog-test-indentation
   "
some_functor(
arg1,
arg2,
)."
   "
some_functor(
    arg1,
    arg2,
)."
   )
  (sweeprolog-test-indentation
   "
asserta( some_functor(arg1, arg2) :-
body_term
).
"
   "
asserta( some_functor(arg1, arg2) :-
             body_term
       ).
"
   )
  (sweeprolog-test-indentation
   "
:- module(spam, [ foo,
bar,
baz
]
).
"
   "
:- module(spam, [ foo,
                  bar,
                  baz
                ]
         ).
"
   )
  (sweeprolog-test-indentation
   "
:- module(spam, [
foo,
bar,
baz
]
).
"
   "
:- module(spam, [
                    foo,
                    bar,
                    baz
                ]
         ).
"
   )
  (sweeprolog-test-indentation
   "
[
    ].
"
   "
[
].
"
   )
  (sweeprolog-test-indentation
   "
:-
use_module(foo),
use_module(bar).
"
   "
:-
    use_module(foo),
    use_module(bar).
"
   )
  (sweeprolog-test-indentation
   "
colourise_declaration(Module:PI, _, TB,
                      term_position(_,_,QF,QT,[PM,PG])) :-
    atom(Module), nonvar(PI), PI = Name/Arity,
    !,                                  % partial predicate indicators
    colourise_module(Module, TB, PM),
    colour_item(functor, TB, QF-QT),
    (   (var(Name) ; atom(Name)),
        (var(Arity) ; integer(Arity),
                      Arity >= 0)
    ->  colourise_term_arg(PI, TB, PG)
    ;   colour_item(type_error(predicate_indicator), TB, PG)
    ).
"
   "
colourise_declaration(Module:PI, _, TB,
                      term_position(_,_,QF,QT,[PM,PG])) :-
    atom(Module), nonvar(PI), PI = Name/Arity,
    !,                                  % partial predicate indicators
    colourise_module(Module, TB, PM),
    colour_item(functor, TB, QF-QT),
    (   (var(Name) ; atom(Name)),
        (var(Arity) ; integer(Arity),
                      Arity >= 0)
    ->  colourise_term_arg(PI, TB, PG)
    ;   colour_item(type_error(predicate_indicator), TB, PG)
    ).
")
  (sweeprolog-test-indentation
   "
A is 1 * 2 + 3 *
4.
"
   "
A is 1 * 2 + 3 *
             4.
")
  (sweeprolog-test-indentation
   "
A is 1 * 2 ^ 3 *
4.
"
   "
A is 1 * 2 ^ 3 *
     4.
")
  (sweeprolog-test-indentation
   "
(   if
    ->  (   iff1, iff2, iff3,
iff4
->  thenn
;   elsee
)
        ;   else
            )
"
   "
(   if
->  (   iff1, iff2, iff3,
        iff4
    ->  thenn
    ;   elsee
    )
;   else
)
")
  (sweeprolog-test-indentation
   "
(   if
    ->  (   iff
->  thenn
;   elsee
)
        ;   else
            )
"
   "
(   if
->  (   iff
    ->  thenn
    ;   elsee
    )
;   else
)
")
  (sweeprolog-test-indentation
   "
(   if
    ;   then
        ->  else
            )
"
   "
(   if
;   then
->  else
)
")
  (sweeprolog-test-indentation
   "
asserta(   foo(bar, baz) :-
true).
"
   "
asserta(   foo(bar, baz) :-
               true).
")
  (sweeprolog-test-indentation
   "
foo(bar, baz) :-
true.
"
   "
foo(bar, baz) :-
    true.
")

  (sweeprolog-test-indentation
   "
:- multifile
foo/2.
"
   "
:- multifile
       foo/2.
")

  (sweeprolog-test-indentation
   "
    %%%%
    %%%%
"
   "
    %%%%
    %%%%
")

  (sweeprolog-test-indentation
   "
(
foo"
   "
(
    foo")
  (sweeprolog-test-indentation
   "
functor(
foo"
   "
functor(
    foo")
  (sweeprolog-test-indentation
   "
replace_key_value(Replacement, Key - AtVar, Out, Used0, Used1),
atom_concat(@, Var, AtVar) =>
foo.
"
   "
replace_key_value(Replacement, Key - AtVar, Out, Used0, Used1),
  atom_concat(@, Var, AtVar) =>
    foo.
"
   )
  (sweeprolog-test-indentation
   "
head,
right_hand_context -->
body.
"
   "
head,
  right_hand_context -->
    body.
"))

(sweeprolog-deftest forward-sexp-with-adjacent-operators ()
  "Tests detecting the fullstop in presence of `.=.'."
  "a,+b."
  (goto-char (point-min))
  (sweeprolog--forward-sexp)
  (should (= (point) 2))
  (goto-char (point-max))
  (sweeprolog--backward-sexp)
  (should (= (point) 4)))

(sweeprolog-deftest usage-example-comment ()
  "Tests adding usage example comments."
  "\nfoo."
  (let ((source-buffer (current-buffer)))
    (sweeprolog-make-example-usage-comment (point-min))
    (insert "true; false.")
    (comint-send-input)
    (accept-process-output nil 1)
    (sweeprolog-top-level-example-done)
    (with-current-buffer source-buffer
      (should (string= (buffer-string)
                       "% ?- true; false.\n% true\u0020\nfoo.")))))

(sweeprolog-deftest add-log-current-defun ()
  "Tests getting the predicate indicator at point."
  "
foo(Bar) :-  baz(Bar).
foo(Bar) --> baz(Bar).
f:o(Bar) :-  baz(Bar).
f:o(Bar) --> baz(Bar)."
  (goto-char (point-min))
  (forward-word)
  (should (string= (add-log-current-defun) "foo/1"))
  (forward-line)
  (should (string= (add-log-current-defun) "foo//1"))
  (forward-line)
  (should (string= (add-log-current-defun) "f:o/1"))
  (forward-line)
  (should (string= (add-log-current-defun) "f:o//1")))

(sweeprolog-deftest up-list ()
  "Test `up-list' support."
  "
foo((A,B)) =>
    (   bar(-!-A)
    ;   baz(B)
    ).
"
  (call-interactively #'up-list)
  (should (= (point) 30))
  (call-interactively #'up-list)
  (should (= (point) 51)))

;;; sweeprolog-tests.el ends here
