/*
    Author:        Eshel Yaron
    E-mail:        eshel@swi-prolog.org
    Copyright (c)  2022-2023, SWI-Prolog Solutions b.v.
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
    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
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

:- module(sweep,
          [ sweep_setup_message_hook/2,
            sweep_current_prolog_flags/2,
            sweep_set_prolog_flag/2,
            sweep_documentation/2,
            sweep_expand_file_name/2,
            sweep_path_module/2,
            sweep_load_buffer/2,
            sweep_colourise_query/2,
            sweep_predicate_references/2,
            sweep_predicate_location/2,
            sweep_predicate_apropos/2,
            sweep_predicates_collection/2,
            sweep_module_functor_arity_pi/2,
            sweep_modules_collection/2,
            sweep_packs_collection/2,
            sweep_pack_install/2,
            sweep_op_info/2,
            sweep_imenu_index/2,
            sweep_module_path/2,
            sweep_thread_signal/2,
            sweep_top_level_server/2,
            sweep_accept_top_level_client/2,
            sweep_local_predicate_export_comment/2,
            write_sweep_module_location/0,
            sweep_module_html_documentation/2,
            sweep_predicate_html_documentation/2,
            sweep_predicate_properties/2,
            sweep_analyze_region/2,
            sweep_xref_source/2,
            sweep_beginning_of_next_predicate/2,
            sweep_beginning_of_last_predicate/2,
            sweep_context_callable/2,
            sweep_heads_collection/2,
            sweep_exportable_predicates/2,
            sweep_interrupt/0,
            sweep_string_to_atom/2,
            sweep_file_path_in_library/2,
            sweep_file_missing_dependencies/2,
            sweep_format_head/2,
            sweep_format_term/2,
            sweep_current_functors/2,
            sweep_term_replace/2,
            sweep_terms_at_point/2,
            sweep_predicate_dependencies/2,
            sweep_async_goal/2,
            sweep_interrupt_async_goal/2,
            sweep_source_file_load_time/2,
            sweep_set_breakpoint/2,
            sweep_set_breakpoint_condition/2,
            sweep_delete_breakpoint/2,
            sweep_current_breakpoints/2,
            sweep_current_breakpoints_in_region/2,
            sweep_breakpoint_range/2,
            sweep_breakpoint_file/2,
            sweep_expand_macro/2,
            sweep_module_annotation/2,
            sweep_is_module/2,
            sweep_module_class/2,
            sweep_variable_start_code/2,
            sweep_head_functors_collection/2,
            sweep_functors_collection/2,
            sweep_compound_functors_collection/2,
            sweep_term_variable_names/2,
            sweep_goal_may_cut/2,
            sweep_top_level_start_pty/2,
            sweep_cleanup_threads/2,
            sweep_kill_thread/2,
            sweep_list_threads/2
          ]).

:- use_module(library(pldoc)).
:- use_module(library(listing)).
:- use_module(library(prolog_source)).
:- use_module(library(prolog_colour)).
:- use_module(library(pldoc/doc_process)).
:- use_module(library(pldoc/doc_wiki)).
:- use_module(library(pldoc/doc_modes)).
:- use_module(library(pldoc/doc_man)).
:- use_module(library(pldoc/doc_html)).
:- use_module(library(pldoc/man_index)).
:- use_module(library(lynx/html_text)).
:- use_module(library(http/html_write)).
:- use_module(library(prolog_pack)).
:- use_module(library(prolog_deps)).
:- use_module(library(dcg/high_order)).

:- if(exists_source(library(macros))).
:- use_module(library(macros)).
:- endif.

:- if(exists_source(library(help))).
:- use_module(library(help)).
:- endif.


:- meta_predicate with_buffer_stream(-, +, 0).

:- dynamic sweep_open_buffer/3,
           sweep_current_comment/3.

:- multifile prolog:xref_source_time/2,
             prolog:xref_open_source/2,
             prolog:xref_close_source/2,
             prolog:quasi_quotation_syntax/2.

:- thread_local sweep_main_thread/0.

prolog:quasi_quotation_syntax(graphql, library(http/graphql)).

prolog:xref_source_time(Source0, Time) :-
    sweep_main_thread,
    atom_string(Source0, Source),
    user:sweep_funcall("sweeprolog--buffer-last-modified-time",
                       Source, Time),
    Time \== [].

prolog:xref_open_source(Source0, Stream) :-
    sweep_main_thread,
    atom_string(Source0, Source),
    user:sweep_funcall("sweeprolog--buffer-string",
                       Source, String),
    String \== [],
    new_memory_file(H),
    insert_memory_file(H, 0, String),
    open_memory_file(H, read, Stream, [encoding(utf8)]),
    set_stream(Stream, encoding(utf8)),
    set_stream(Stream, file_name(Source)),
    asserta(sweep_open_buffer(Source0, Stream, H)).

prolog:xref_close_source(Source, Stream) :-
    retract(sweep_open_buffer(Source, Stream, H)),
    close(Stream),
    free_memory_file(H).

sweep_list_threads(IdBufferPairs, Ts) :-
    findall([Id, Buffer, Status, Stack, CPUTime],
            (   member([Buffer|Id], IdBufferPairs),
                thread_property(Id, status(Status0)),
                term_string(Status0, Status),
                thread_statistics(Id, stack, Stack),
                thread_statistics(Id, cputime, CPUTime)
            ),
            Ts).

sweep_current_prolog_flags(Sub, Flags) :-
    findall([Flag|Value],
            (current_prolog_flag(Flag0, Value0),
             atom_string(Flag0, Flag),
             once(sub_string(Flag, _, _, _, Sub)),
             term_string(Value0, Value)),
            Flags).

sweep_set_prolog_flag([Flag0|Value0], true) :-
    atom_string(Flag, Flag0),
    term_string(Value, Value0),
    set_prolog_flag(Flag, Value).

sweep_xref_source(Path0, _) :-
    atom_string(Path, Path0),
    xref_source(Path, [comments(store)]).

sweep_analyze_region([OneTerm,Offset,Contents,Path0], Result) :-
    atom_string(Path, Path0),
    with_buffer_stream(Stream,
                       Contents,
                       sweep_analyze_region_(OneTerm, Offset, Stream, Path, Result)).

sweep_analyze_region_(OneTerm, Offset, Stream, Path, _) :-
    set_stream(Stream, file_name(Path)),
    retractall(sweep_current_comment(_, _, _)),
    (   OneTerm == []
    ->  prolog_colourise_stream(Stream, Path,
                                sweep_handle_fragment(Offset))
    ;   prolog_colourise_term(Stream, Path,
                              sweep_handle_fragment(Offset), [])),
    forall(sweep_current_comment(Kind, Start, Len),
           ( atom_string(Kind, String),
             user:sweep_funcall("sweeprolog-analyze-fragment",
                                [Start,Len,"comment"|String], _)
           )).

sweep_handle_fragment(Offset, comment(Kind), Beg, Len) :-
    !,
    Start is Beg + Offset,
    assertz(sweep_current_comment(Kind, Start, Len)).
sweep_handle_fragment(Offset, Col, Beg, Len) :-
    sweep_handle_fragment_(Offset, Col, Beg, Len).

sweep_handle_fragment_(Offset, Col, Beg, Len) :-
    sweep_color_normalized(Offset, Col, Nom),
    Start is Beg + Offset,
    user:sweep_funcall("sweeprolog-analyze-fragment", [Start,Len|Nom], _).

sweep_documentation(PI0, Docs) :-
    term_string(PI1, PI0),
    (   PI1 = M:PI
    ->  true
    ;   PI=PI1
    ),
    findall(Doc, sweep_documentation_(M, PI, Doc), Docs).

sweep_documentation_(M, PI, Docs) :-
   doc_comment(M:PI, Pos, OneLiner, Comment),
   is_structured_comment(Comment, Prefixes),
   string_codes(Comment, Codes),
   indented_lines(Codes, Prefixes, Lines),
   pldoc_modes:mode_lines(Lines, ModeText, [], _),
   pldoc_modes:modes(ModeText, M, Pos, Modes),
   sweep_documentation_modes(Modes, OneLiner, Docs).
sweep_documentation_(_, PI, Docs) :-
    pldoc_man:load_man_object(PI, _, _, Dom),
    with_output_to(string(DomS), html_text(Dom, [])),
    sub_string(DomS, EOL, _, _, '\n'),
    sub_string(DomS, 0, EOL, _, FLine),
    sub_string(DomS, EOL, _, 0, Rest),
    (   sub_string(Rest, EOS, _, _, '. ')
    ->  sub_string(Rest, 0, EOS, _, OneLiner2)
    ;   OneLiner2=Rest
    ),
    format(string(Docs), '~w.    ~w.~n', [FLine, OneLiner2]),
    !.

sweep_documentation_modes([mode(Mode0, Args)|_], OneLiner, Docs) :-
    maplist([Name=Var]>>(Var='$VAR'(Name)), Args),
    (   Mode0=(Mode1 is Det)
    ->  true
    ;   Mode1=Mode0,
        Det=unspec
    ),
    format(string(Docs),
           '~W is ~w.~n    ~w~n',
           [ Mode1,
             [module(pldoc_modes), numbervars(true)],
             Det,
             OneLiner
           ]).
sweep_documentation_modes([_|T], OneLiner, Docs) :-
    sweep_documentation_modes(T, OneLiner, Docs).

sweep_module_class(M0, C) :-
    atom_string(M, M0),
    module_property(M, class(C0)),
    atom_string(C0, C).

sweep_module_path(ModuleName, Path) :-
    atom_string(Module, ModuleName),
    sweep_module_path_(Module, Path0),
    atom_string(Path0, Path).


sweep_module_path_(Module, Path) :-
    module_property(Module, file(Path)), !.
sweep_module_path_(Module, Path) :-
    xref_module(Path, Module), !.
sweep_module_path_(Module, Path) :-
    '$autoload':library_index(_, Module, Path0), atom_concat(Path0, '.pl', Path), !.
sweep_module_path_(user, _).


sweep_predicate_properties(P0, Props) :-
    term_string(P, P0),
    pi_head(P, Head),
    findall(Prop, predicate_property(Head, Prop), Props).

sweep_predicate_html_documentation(P0, D) :-
    term_string(P1, P0),
    (   P1 = M:PI
    ->  true
    ;   P1 = PI, M = system
    ),
    (   (   current_module(M)
        ;   xref_module(_, M)
        )
    ->  true
    ;   '$autoload':library_index(_, M, Path),
        xref_source(Path, [comments(store)])
    ),
    (   pldoc_man:load_man_object(M:PI, _, _, DOM)
    ;   pldoc_man:load_man_object(PI, _, _, DOM)
    ;   doc_comment(M:PI, Pos, _, Comment),
        pldoc_html:pred_dom(M:PI, [], Pos-Comment, DOM)
    ),
    phrase(pldoc_html:html(DOM), HTML),
    with_output_to(string(D), html_write:print_html(HTML)).

sweep_module_html_documentation(M0, D) :-
    atom_string(M, M0),
    (   (   current_module(M)
        ;   xref_module(_, M)
        )
    ->  true
    ;   '$autoload':library_index(_, M, Path),
        xref_source(Path, [comments(store)])
    ),
    doc_comment(M:module(Desc), Pos, _, Comment),
    pldoc_html:pred_dom(M:module(Desc), [], Pos-Comment, DOM),
    phrase(pldoc_html:html(DOM), HTML),
    with_output_to(string(D), html_write:print_html(HTML)).

sweep_modules_collection([Bef|Aft], Ms) :-
    setof(M, sweep_known_module(M), Ms0),
    include(sweep_matching_module(Bef,Aft), Ms0, Ms1),
    maplist(atom_string, Ms1, Ms).

sweep_matching_module([], Aft, Mod) :-
    !,
    sweep_matching_module_(Aft, 0, Mod).
sweep_matching_module(Bef, Aft, Mod) :-
    once(sub_atom(Mod, N, L, _, Bef)),
    M is N + L,
    sweep_matching_module_(Aft, M, Mod).

sweep_matching_module_([], _, _) :- !.
sweep_matching_module_(A, N, M) :-
    sub_atom(M, B, _, _, A),
    B >= N,
    !.

sweep_module_annotation(M0, [P|D]) :-
    atom_string(M, M0),
    (   sweep_module_path_(M, P0), nonvar(P0)
    ->  sweep_file_path_in_library(P0, P)
    ;   P = []
    ),
    (   sweep_module_description_(M, P0, D0)
    ->  atom_string(D0, D)
    ;   D = []
    ).

sweep_known_module(M) :-
    current_module(M).
sweep_known_module(M) :-
    xref_module(_, M).
sweep_known_module(M) :-
    '$autoload':library_index(_, M, _).

sweep_is_module(M0, _) :-
    atom_string(M, M0),
    once(sweep_known_module(M)).

sweep_module_description_(M, _, D) :-
    doc_comment(M:module(D), _,_,_).
sweep_module_description_(_, P, D) :-
    xref_comment(P, D, _).
sweep_module_description_(M, _, D) :-
    atom_concat('sec:', M, S),
    man_object_property(section(_, _, S, _), summary(D)).

sweep_predicate_references(MFN, Refs) :-
    term_string(M:PI, MFN),
    pi_head(PI, H),
    findall([B, Path, From, Len],
            ((   xref_called(Path0, H, B0, _, Line)
             ;   xref_called(Path0, M:H, B0, _, Line)
             ),
             pi_head(B1, B0),
             (   B1 = M2:F/N
             ->  true
             ;   B1 = F/N,
                 sweep_module_path_(M2, Path0)
             ),
             sweep_module_functor_arity_pi_(M2, F, N, B2),
             term_string(B2, B),
             atom_string(Path0, Path),
             reference_span(Path0, Line, H, From, Len)),
            Refs).

:- dynamic current_reference_span/2.

reference_span(Path, Line, Head, From, Len) :-
    retractall(current_reference_span(_, _)),
    setup_call_cleanup(prolog_open_source(Path, Stream),
                       (   prolog_source:seek_to_line(Stream, Line),
                           prolog_colourise_term(Stream, Path, reference_span_(Head), [])
                       ),
                       prolog_close_source(Stream)),
    !,
    current_reference_span(From, Len).

reference_span_(Head, goal_term(_, Goal), Beg0, Len) :-
    \+ \+ Head = Goal,
    Beg is Beg0 + 1,
    assertz(current_reference_span(Beg, Len)).
reference_span_(_, _, _, _) :- true.

sweep_predicate_location(MFN, [Path|Line]) :-
    term_string(M:PI, MFN),
    !,
    pi_head(PI, H),
    (   sweep_predicate_location_(M, H, Path, Line)
    ->  true
    ;   sweep_predicate_location_(H, Path, Line)
    ).
sweep_predicate_location(FN, [Path|Line]) :-
    term_string(PI, FN),
    pi_head(PI, H),
    sweep_predicate_location_(H, Path, Line).

sweep_predicate_apropos(Query0, Matches) :-
    atom_string(Query, Query0),
    findall([S,Path|Line],
            (prolog_help:apropos(Query, M:PI, _, P), P >= 0.3,
             format(string(S), '~W', [M:PI, [quoted(true), character_escapes(true)]]),
             catch(pi_head(PI, Head), _, fail),
             sweep_predicate_location_(M, Head, Path, Line)),
            Matches, Tail),
    findall([S,Path],
            (prolog_help:apropos(Query, PI, _, P), P >= 0.3,
             format(string(S), '~W', [PI, [quoted(true), character_escapes(true)]]),
             catch(pi_head(PI, Head), _, fail),
             sweep_predicate_location_(Head, Path, Line)),
            Tail).

sweep_predicate_location_(H, Path, Line) :-
    xref_defined(Path0, H, How0),
    xref_definition_line(How0, _),
    xref_source(Path0, [comments(store)]),
    xref_defined(Path0, H, How),
    xref_definition_line(How, Line),
    !,
    atom_string(Path0, Path).
sweep_predicate_location_(H, Path, Line) :-
    predicate_property(H, file(Path0)),
    predicate_property(H, line_count(Line)),
    atom_string(Path0, Path).

sweep_predicate_location_(M, H, Path, Line) :-
    (   xref_defined(Path0, M:H, How0),
        xref_definition_line(How0, _)
    ->  true
    ;   xref_defined(Path0, H, How0),
        xref_definition_line(How0, _),
        xref_module(Path0, M)
    ),
    xref_source(Path0, [comments(store)]),
    xref_defined(Path0, H, How),
    xref_definition_line(How, Line),
    !,
    atom_string(Path0, Path).
sweep_predicate_location_(M, H, P, L) :-
    '$autoload':library_index(H, M, P0),
    absolute_file_name(P0, P1, [extensions([pl])]),
    xref_source(P1, [comments(store)]),
    xref_defined(P1, H, How),
    xref_definition_line(How, L),
    !,
    atom_string(P1, P).
sweep_predicate_location_(M, H, Path, Line) :-
    predicate_property(M:H, file(Path0)),
    predicate_property(M:H, line_count(Line)),
    atom_string(Path0, Path).

sweep_matching_predicates(Bef, Aft, D, M, PIs) :-
    setof(M:F/A, sweep_matching_predicate(Bef, Aft, D, M, F, A), PIs).

sweep_matching_predicate(Bef, Aft, D, M, F, A) :-
    sweep_known_predicate(M, F, A),
    sweep_predicate_matches_(Bef, Aft, F),
    A >= D.

sweep_predicate_matches_([], Aft, F) :-
    !,
    sweep_predicate_matches_aft(Aft, 0, F).
sweep_predicate_matches_(Bef, Aft, F) :-
    once(sub_string(F, N, L, _, Bef)),
    M is N + L,
    sweep_predicate_matches_aft(Aft, M, F).

sweep_predicate_matches_aft([], _, _) :- !.
sweep_predicate_matches_aft(A, N, M) :-
    sub_atom(M, B, _, _, A),
    B >= N,
    !.

sweep_known_predicate(M, F, A) :-
    current_predicate(M:F/A),
    (   M == system
    ->  true
    ;   pi_head(F/A, H),
        \+ (predicate_property(M:H, imported_from(M1)), M \= M1)
    ).
sweep_known_predicate(M, F, A) :-
    '$autoload':library_index(H, M, _),
    pi_head(F/A, H).
sweep_known_predicate(M, F, A) :-
    xref_defined(SourceId, H, How),
    xref_definition_line(How, _),
    (   xref_module(SourceId, M)
    ->  true
    ;   M = user
    ),
    pi_head(F/A, H).

sweep_predicates_collection(S0, Ps) :-
    (   S0 == []
    ->  S = ""
    ;   S = S0
    ),
    sweep_matching_predicates([], S, 0, _, PIs),
    maplist(sweep_format_pi, PIs, Ps).

sweep_format_pi(M:F/N, [S|T]) :-
    sweep_module_functor_arity_pi_(M, F, N, MFA),
    format(string(S),
           '~W',
           [MFA, [quoted(true), character_escapes(true)]]),
    (   sweep_predicate_summary(MFA, Summary)
    ->  atom_string(Summary, T)
    ;   T = []
    ).

sweep_predicate_summary(MFA, D) :-
    doc_comment(MFA, _, D, _).
sweep_predicate_summary(MFA, D) :-
    man_object_property(MFA, summary(D)).
sweep_predicate_summary(_:FA, D) :-
    man_object_property(FA, summary(D)).

sweep_packs_collection(SearchString, Packs) :-
    prolog_pack:query_pack_server(search(SearchString), true(Packs0), []),
    maplist(sweep_pack_info, Packs0, Packs).

sweep_pack_info(pack(Name0, _, Desc0, Version0, URLS0), [Name, Desc, Version, URLS]) :-
    atom_string(Name0, Name),
    atom_string(Desc0, Desc),
    atom_string(Version0, Version),
    maplist(atom_string, URLS0, URLS).

sweep_pack_install(PackName, true) :-
    atom_string(Pack, PackName),
    pack_install(Pack, [silent(true), upgrade(true), interactive(false)]).

sweep_colourise_query([String|Offset], _) :-
    prolog_colourise_query(String, user, sweep_handle_fragment_(Offset)).

sweep_color_normalized(Offset, Col, Nom) :-
    Col =.. [Nom0|Rest],
    sweep_color_normalized_(Offset, Nom0, Rest, Nom).

sweep_color_normalized_(_, Goal0, [Kind0,Head|_], [Goal,Kind,F,N]) :-
    sweep_color_goal(Goal0),
    !,
    atom_string(Goal0, Goal),
    sweep_goal_kind_normalized(Kind0, Kind),
    (   callable(Head)
    ->  pi_head(F0/N, Head),
        atom_string(F0, F)
    ;   term_string(Head, F), N = 0
    ).
sweep_color_normalized_(Offset, syntax_error, [Message0,Start0-End0|_], ["syntax_error", Message, Start, End]) :-
    !,
    Start is Start0 + Offset,
    End   is End0   + Offset,
    atom_string(Message0, Message).
sweep_color_normalized_(_, comment, [Kind0|_], ["comment"|Kind]) :-
    !,
    atom_string(Kind0, Kind).
sweep_color_normalized_(_, dcg, [Kind0|_], ["dcg"|Kind]) :-
    !,
    atom_string(Kind0, Kind).
sweep_color_normalized_(_, hook, [Kind0|_], ["hook"|Kind]) :-
    !,
    atom_string(Kind0, Kind).
sweep_color_normalized_(_, module, [M0|_], ["module"|M]) :-
    !,
    term_string(M0, M).
sweep_color_normalized_(_, qq_content, [Type0|_], ["qq_content"|Type]) :-
    !,
    atom_string(Type0, Type).
sweep_color_normalized_(_, file, [File0|_], ["file"|File]) :-
    !,
    atom_string(File0, File).
sweep_color_normalized_(_, file_no_depend, [File0|_], ["file_no_depend"|File]) :-
    !,
    atom_string(File0, File).
sweep_color_normalized_(_, type_error, [Kind0|_], ["type_error"|Kind]) :-
    !,
    Kind0 =.. [Kind1|_],
    atom_string(Kind1, Kind).
sweep_color_normalized_(_, macro, [String|_], ["macro"|String]) :-
    !.
sweep_color_normalized_(_, decl_option, [Opt0|_], ["decl_option"|Opt]) :-
    !,
    term_string(Opt0, Opt).
sweep_color_normalized_(_, Nom0, _, Nom) :-
    atom_string(Nom0, Nom).

sweep_goal_kind_normalized(autoload(Path0), ["autoload"|Path]) :-
    !,
    absolute_file_name(Path0, Path1, [extensions([pl])]),
    atom_string(Path1, Path).
sweep_goal_kind_normalized(imported(Path0), ["imported"|Path]) :-
    !,
    absolute_file_name(Path0, Path1, [extensions([pl])]),
    atom_string(Path1, Path).
sweep_goal_kind_normalized(global(Kind0, _), ["global"|Kind]) :-
    !,
    atom_string(Kind0, Kind).
sweep_goal_kind_normalized(thread_local(_), "thread_local") :-
    !.
sweep_goal_kind_normalized(dynamic(_), "dynamic") :-
    !.
sweep_goal_kind_normalized(multifile(_), "multifile") :-
    !.
sweep_goal_kind_normalized(foreign(_), "foreign") :-
    !.
sweep_goal_kind_normalized(local(_), "local") :-
    !.
sweep_goal_kind_normalized(constraint(_), "constraint") :-
    !.
sweep_goal_kind_normalized(public(_), "public") :-
    !.
sweep_goal_kind_normalized(extern(Module0), ["extern",Module]) :-
    !,
    (   atom(Module0)
    ->  atom_string(Module0, Module)
    ;   Module = Module0
    ).
sweep_goal_kind_normalized(extern(Module0,Kind0), ["extern",Module,Kind]) :-
    !,
    (   atom(Module0)
    ->  atom_string(Module0, Module)
    ;   Module = Module0
    ),
    atom_string(Kind0, Kind).
sweep_goal_kind_normalized(Kind0, Kind) :-
    term_string(Kind0, Kind).

sweep_color_goal(goal).
sweep_color_goal(goal_term).
sweep_color_goal(head).
sweep_color_goal(head_term).
sweep_color_goal(predicate_indicator).

sweep_expand_file_name([String|Dir], Exp) :-
    term_string(Spec, String, [syntax_errors(quiet)]),
    sweep_expand_file_name_(Dir, Spec, Atom),
    (   exists_file(Atom)
    ->  true
    ;   exists_directory(Atom)
    ),
    atom_string(Atom, Exp).

sweep_expand_file_name_([], Spec, Atom) :-
    absolute_file_name(Spec, Atom, [file_errors(fail),
                                    solutions(all),
                                    extensions(['', '.pl'])]).
sweep_expand_file_name_(Dir, Spec, Exp) :-
    !,
    absolute_file_name(Spec, Exp, [file_errors(fail),
                                   relative_to(Dir),
                                   solutions(all),
                                   extensions(['', '.pl'])]).

sweep_path_module(Path0, Module) :-
    atom_string(Path, Path0),
    sweep_module_path_(Module0, Path),
    atom_string(Module0, Module).


sweep_setup_message_hook(_, _) :-
    asserta(sweep_main_thread),
    asserta((
             user:thread_message_hook(Term, Kind, Lines) :-
                 sweep_message_hook(Term, Kind, Lines)
            ),
            Ref),
    at_halt(erase(Ref)).

sweep_message_hook(Term, Kind0, _Lines) :-
    should_handle_message_kind(Kind0, Kind),
    !,
    message_to_string(Term, String),
    user:sweep_funcall("sweeprolog-message", [Kind|String], _).

should_handle_message_kind(error, "error").
should_handle_message_kind(warning, "warning").
should_handle_message_kind(informational, "informational").
should_handle_message_kind(debug(Topic0), ["debug"|Topic]) :- atom_string(Topic0, Topic).

sweep_op_info([Op0|Path0], Info) :-
    atom_string(Path, Path0),
    atom_string(Op, Op0),
    sweep_op_info_(Op, Path, Info).

sweep_op_info_(Op, Path, [Type|Pred]) :-
    xref_op(Path, op(Pred, Type0, Op)),
    atom_string(Type0, Type).
sweep_op_info_(Op, _Path, [Type|Pred]) :-
    current_op(Pred, Type0, Op),
    atom_string(Type0, Type).

sweep_source_file_load_time(Path0, Time) :-
    atom_string(Path, Path0),
    source_file_property(Path, modified(Time)).

sweep_load_buffer([String,Modified,Path0], _) :-
    atom_string(Path, Path0),
    with_buffer_stream(Stream,
                       String,
                       sweep_load_buffer_(Stream, Modified, Path)).

sweep_load_buffer_(Stream, Modified, Path) :-
    set_stream(Stream, file_name(Path)),
    @(load_files(Path, [modified(Modified), stream(Stream)]), user).

with_buffer_stream(Stream, String, Goal) :-
    setup_call_cleanup(( new_memory_file(H),
                         insert_memory_file(H, 0, String),
                         open_memory_file(H, read, Stream, [encoding(utf8)]),
                         set_stream(Stream, encoding(utf8))
                       ),
                       Goal,
                       ( close(Stream),
                         free_memory_file(H)
                       )).

sweep_imenu_index(Path, Index) :-
    atom_string(Atom, Path),
    findall([String|L],
            ( xref_defined(Atom, D, H),
              xref_definition_line(H, L),
              pi_head(PI, D),
              term_string(PI, String)
            ),
            Index).

:- if(exists_source(library(sweep_link))).
:- use_module(library(sweep_link), [write_sweep_module_location/0]).
:- else.
write_sweep_module_location :-
    format('V ~w~n', 1),
    absolute_file_name(foreign('sweep-module'),
                       Path,
                       [file_type(executable), access(read)]),
    (   current_prolog_flag(executable_format, elf)
    ->  current_prolog_flag(libswipl, Libpath),
        format('L ~w~n', Libpath)
    ;   true
    ),
    format('M ~w~n', Path).
:- endif.

sweep_top_level_start_pty(Name, Id) :-
    sweep_create_thread(sweep_top_level_pty_client(Name), T),
    thread_property(T, id(Id)).

sweep_top_level_pty_client(Name) :-
    open(Name, read, InStream, [eof_action(reset)]),
    open(Name, write, OutStream),
    sweep_top_level_client(InStream, OutStream, ip(127,0,0,1)).

sweep_top_level_server(_, Port) :-
    tcp_socket(ServerSocket),
    tcp_setopt(ServerSocket, reuseaddr),
    tcp_bind(ServerSocket, Port),
    tcp_listen(ServerSocket, 5),
    thread_self(Self),
    sweep_create_thread(sweep_top_level_server_start(Self, ServerSocket), _,
                  [ alias(sweep_top_level_server)
                  ]),
    thread_get_message(sweep_top_level_server_started).

sweep_top_level_server_start(Caller, ServerSocket) :-
    thread_send_message(Caller, sweep_top_level_server_started),
    sweep_top_level_server_loop(ServerSocket).

sweep_top_level_server_loop(ServerSocket) :-
    thread_get_message(Message),
    sweep_top_level_server_loop_(Message, ServerSocket).

sweep_top_level_server_loop_(accept(From), ServerSocket) :-
    !,
    tcp_accept(ServerSocket, Slave, Peer),
    tcp_open_socket(Slave, InStream, OutStream),
    set_stream(InStream, close_on_abort(false)),
    set_stream(OutStream, close_on_abort(false)),
    sweep_create_thread(sweep_top_level_client(InStream, OutStream, Peer), T),
    thread_property(T, id(Id)),
    thread_send_message(From, client(Id)),
    sweep_top_level_server_loop(ServerSocket).
sweep_top_level_server_loop_(_, _).

sweep_top_level_client(InStream, OutStream, ip(127,0,0,1)) :-
    !,
    set_prolog_IO(InStream, OutStream, OutStream),
    set_stream(InStream, tty(true)),
    set_prolog_flag(tty_control, false),
    current_prolog_flag(encoding, Enc),
    set_stream(user_input, encoding(Enc)),
    set_stream(user_output, encoding(Enc)),
    set_stream(user_error, encoding(Enc)),
    set_stream(user_input, newline(detect)),
    set_stream(user_output, newline(dos)),
    set_stream(user_error, newline(dos)),
    thread_at_exit(( catch(format("~nSweep top-level thread exited~n"),
                           _, true),
                     close(InStream, [force(true)]),
                     close(OutStream, [force(true)])
                   )),
    prolog.
sweep_top_level_client(InStream, OutStream, _) :-
    close(InStream),
    close(OutStream).

sweep_accept_top_level_client(_, Id) :-
    thread_self(S),
    thread_send_message(sweep_top_level_server, accept(S)),
    thread_get_message(client(Id)).

sweep_thread_signal([ThreadId|Goal0], _) :-
    is_thread(ThreadId),
    term_string(Goal, Goal0),
    thread_signal(ThreadId, Goal).

sweep_local_predicate_export_comment([Path0,F0,A,I0],Comm) :-
    atom_string(Path, Path0),
    atom_string(F, F0),
    atom_string(I, I0),
    compound_name_arguments(PI, I, [F,A]),
    doc_comment(_:PI, Path:_, _Summary, Comment),
    comment_modes(Comment, Modes),
    compound_name_arity(Head, F, A),
    member(ModeAndDet, Modes),
    strip_det(ModeAndDet, Head),
    Head =.. [_|Args],
    Head2 =.. ['DUMMY'|Args],
    term_string(Head2, Syn0,
                [ module(pldoc_modes),
                  quoted(false)
                ]),
    sub_string(Syn0, 6, _, 1, Comm).

strip_det(//(Mode) is _, Mode) :- !.
strip_det(Mode is _, Mode) :- !.
strip_det(//(Mode), Mode) :- !.
strip_det(Mode, Mode).

sweep_module_functor_arity_pi([M0,F0,A], PI) :-
    atom_string(M, M0),
    atom_string(F, F0),
    sweep_module_functor_arity_pi_(M, F, A, PI0),
    term_string(PI0, PI).

sweep_module_functor_arity_pi_(M, F, A, M:F//B) :-
    sweep_grammar_rule(M, F, A),
    !,
    B is A - 2.
sweep_module_functor_arity_pi_(M, F, A, M:F/A).

sweep_grammar_rule(M, F, A) :-
    xref_module(Source, M),
    pi_head(F/A, H),
    xref_defined(Source, H, dcg).
sweep_grammar_rule(M, F, A) :-
    pi_head(M:F/A, H),
    predicate_property(H, non_terminal).

sweep_current_module(Module) :-
    sweep_main_thread,
    user:sweep_funcall("buffer-file-name", String),
    (   string(String)
    ->  atom_string(Path, String),
        sweep_module_path_(Module, Path)
    ;   Module = user
    ).


sweep_beginning_of_last_predicate(Start, Next) :-
    sweep_source_id(Path),
    xref_source(Path, [comments(store)]),
    findall(L,
            (   xref_defined(Path, _, H),
                xref_definition_line(H, L),
                L < Start
            ),
            Ls),
    sort(Ls, Sorted),
    reverse(Sorted, [Next|_]).

sweep_beginning_of_next_predicate(Start, Next) :-
    sweep_source_id(Path),
    xref_source(Path, [comments(store)]),
    findall(L,
            (   xref_defined(Path, _, H),
                xref_definition_line(H, L),
                Start < L
            ),
            Ls),
    sort(Ls, [Next|_]).

sweep_source_id(Path) :-
    sweep_main_thread,
    user:sweep_funcall("buffer-file-name", Path0),
    string(Path0),
    atom_string(Path, Path0).

sweep_functors_collection([Bef|Aft], Ps) :-
    setof(F, sweep_matching_functor(Bef, Aft, F), Ps0),
    maplist(sweep_format_compound, Ps0, Ps).

sweep_format_compound(F/A, [S|SP]) :-
    pi_head(F/A, H),
    length(NamedArgs, A),
    maplist(=('$VAR'('_')), NamedArgs),
    H =.. [F|NamedArgs],
    term_string(H, S, [quoted(true),
                       character_escapes(true),
                       spacing(next_argument),
                       numbervars(true)]),
    term_string(_, S, [subterm_positions(SP)]),
    !.

sweep_matching_functor(Bef, Aft, F/A) :-
    current_functor(F, A),
    atom(F),
    term_string(F, S),
    sweep_matching_atom(Bef, Aft, S).

sweep_compound_functors_collection([Arity,Bef,Aft], Fs) :-
    setof(F, sweep_matching_functor(Bef, Aft, F/Arity), Fs0),
    maplist(term_string, Fs0, Fs).

sweep_matching_atom([], Aft, Atom) :-
    !,
    sweep_matching_atom_(Aft, 0, Atom).
sweep_matching_atom(Bef, Aft, Atom) :-
    once(sub_string(Atom, N, L, _, Bef)),
    M is N + L,
    sweep_matching_atom_(Aft, M, Atom).

sweep_matching_atom_([], _, _) :- !.
sweep_matching_atom_(A, N, M) :-
    sub_string(M, B, _, _, A),
    B >= N,
    !.

sweep_head_functors_collection([Arity,D,M0,Bef,Aft], Fs) :-
    (   M0 = []
    ->  true
    ;   term_string(M, M0)
    ),
    sweep_matching_predicates(Bef, Aft, D, M, PIs0),
    include({Arity}/[_:_/Arity]>>true, PIs0, PIs),
    maplist([_:Functor/_, Functor]>>true, PIs, Fs0),
    maplist(term_string, Fs0, Fs).

sweep_heads_collection([D,M0,Bef,Aft], Ps) :-
    (   M0 = []
    ->  true
    ;   term_string(M, M0)
    ),
    sweep_matching_predicates(Bef, Aft, D, M, PIs),
    maplist(sweep_format_head_(D), PIs, Ps).

sweep_format_head_(D, M:F/A, [S|SP]) :-
    N is A - D,
    length(NamedArgs, N),
    append(NamedArgs, _, OpenNamedArgs),
    (   predicate_argument_names(M:F/A, As, Extra)
    ->  maplist(name_variable, As, Vs),
        append(Vs, Extra, OpenNamedArgs)
    ;   maplist(=('$VAR'('_')), NamedArgs)
    ),
    !,
    H =.. [F|NamedArgs],
    term_string(H, S, [quoted(true),
                       character_escapes(true),
                       spacing(next_argument),
                       numbervars(true)]),
    term_string(_, S, [subterm_positions(SP)]).

name_variable(N, V) :- V = '$VAR'(N).

sweep_context_callable([H|T], R) :-
    H = [F0|_],
    atom_string(F, F0),
    op_is_neck(F),
    !,
    (   F == (-->)
    ->  R0 = 2
    ;   R0 = 0
    ),
    sweep_context_callable_(T, R0, 0, R).
sweep_context_callable([_|T], R) :-
    sweep_context_callable(T, R).

op_is_neck(F) :-
    (   xref_op(_, op(1200, _, F))
    ->  true
    ;   current_op(1200, _, F)
    ).

sweep_context_callable_([], R0, R1, R) :- R is R0 + R1, !.
sweep_context_callable_([[":"|2]], R0, R1, R) :- R is R0 + R1, !.
sweep_context_callable_([["("|_]|T], R0, R1, R) :-
    !,
    sweep_context_callable_(T, R0, R1, R).
sweep_context_callable_([["{"|_]|T], 2, R1, R) :-
    !,
    sweep_context_callable_(T, 0, R1, R).
sweep_context_callable_([H|T], R0, _, R) :-
    H = [F0|N],
    atom_string(F, F0),
    sweep_context_callable_arg(F, N, R1),
    sweep_context_callable_(T, R0, R1, R).

sweep_context_callable_arg((-->), _, 2) :- !.
sweep_context_callable_arg(^, _, 0) :- !.
sweep_context_callable_arg(Neck, _, 0) :-
    op_is_neck(Neck),
    !.
sweep_context_callable_arg(F, N, R) :-
    sweep_current_module(Mod),
    (   @(predicate_property(Head, visible), Mod)
    ;   xref_defined(_, Head, _)
    ),
    pi_head(F/M,Head),
    M >= N,
    (   @(predicate_property(Head, meta_predicate(Spec)), Mod)
    ;   catch(infer_meta_predicate(Head, Spec),
              error(permission_error(access, private_procedure, _),
                    context(system:clause/2, _)),
              false)
    ),
    arg(N, Spec, A),
    callable_arg(A, R).

callable_arg(N,    N) :- integer(N), !.
callable_arg((^),  0) :- !.
callable_arg((//), 2) :- !.
callable_arg((:),  0) :- !.

sweep_exportable_predicates(Path0, Preds) :-
    atom_string(Path, Path0),
    findall(D,
            (   xref_defined(Path, D0, _),
                \+ xref_exported(Path, D0),
                \+ D0 = _:_,
                pi_head(F/A, D0),
                (   xref_defined(Path, D0, dcg)
                ->  B is A - 2, D1 = F//B
                ;   D1 = F/A
                ),
                term_string(D1, D)
            ),
            Preds).

:- if(current_predicate(prolog_interrupt/0)).
sweep_interrupt :- prolog_interrupt.
:- else.
sweep_interrupt :- trace.
:- endif.

sweep_string_to_atom(String, AtomString) :-
    atom_string(Atom, String),
    format(string(AtomString),
           "~W",
           [Atom, [quoted(true), character_escapes(true)]]).

sweep_file_path_in_library(Path, Spec) :-
    file_name_on_path(Path, Spec0),
    prolog_deps:segments(Spec0, Spec1),
    (   string(Spec1)
    ->  Spec = Spec1
    ;   term_string(Spec1, Spec)
    ).


predicate_argument_names(M:F/A, Args, Extra) :-
    (   sweep_grammar_rule(M, F, A)
    ->  Extra = [_,_]
    ;   Extra = []
    ),
    sweep_module_functor_arity_pi_(M, F, A, M:PI),
    (   predicate_argument_names_from_man(M, PI, Args0)
    ->  true
    ;   predicate_argument_names_from_pldoc(M, PI, Args0)),
    arg(2, PI, N),
    predicate_argument_names_(N, Args0, Args).


predicate_argument_names_from_man(M, PI, Args) :-
    (   pldoc_man:load_man_object(M:PI, _, _, DOM0)
    ->  true
    ;   pldoc_man:load_man_object(PI, _, _, DOM0)
    ),
    memberchk(element(dt, _, DOM1), DOM0),
    memberchk(element(a, _, DOM2), DOM1),
    catch(findall(Arg,
                  (   member(element(var, _, Vars), DOM2),
                      member(ArgsSpec, Vars),
                      term_string(CommaSeparatedArgs,
                                  ArgsSpec,
                                  [module(pldoc_modes),
                                   variable_names(VN)]),
                      maplist(call, VN),
                      comma_list(CommaSeparatedArgs, ArgsList),
                      member(Arg, ArgsList)
                  ),
                  Args),
          error(syntax_error(_),_),
          fail).

predicate_argument_names_from_pldoc(M, PI, Args) :-
    doc_comment(M:PI, _, _, C),
    comment_modes(C, ModeAndDets),
    member(ModeAndDet, ModeAndDets),
    strip_det(ModeAndDet, Head),
    Head =.. [_|Args].

predicate_argument_names_(Arity, Args0, Args) :-
    length(Args0, Arity),
    maplist(strip_mode_and_type, Args0, Args).

strip_mode_and_type(S, N), compound(S) => arg(1, S, N0), strip_type(N0, N).
strip_mode_and_type(S, N) => strip_type(S, N).

strip_type(N:_, N) :- !.
strip_type(N, N).

sweep_file_missing_dependencies(File0, Deps) :-
    atom_string(File, File0),
    file_autoload_directives(File, Directives, [missing(true)]),
    phrase(dep_directives(Directives), Deps).

dep_directives(Directives) --> sequence(dep_directive, Directives).

dep_directive(:- use_module(Spec)) -->
    !,
    {      absolute_file_name(Spec, Path0,
                           [ file_type(prolog),
                             access(read)
                           ]),
           atom_string(Path0, Path)
    },
    [[Path, [], "use_module"]].
dep_directive(:- Directive) -->
    {   compound_name_arguments(Directive, Kind0, [Spec, ImportList]),
        atom_string(Kind0, Kind),
        absolute_file_name(Spec, Path0,
                           [ file_type(prolog),
                             access(read)
                           ]),
        atom_string(Path0, Path)
    },
    sequence(dep_import(Path, Kind), ImportList).

dep_import(Path, Kind, PI0) -->
    {   term_string(PI0, PI)
    },
    [[Path, PI, Kind]].


sweep_format_head([M0,F0,A,D], R) :-
    atom_string(M, M0),
    atom_string(F, F0),
    sweep_format_head_(D, M:F/A, R).

sweep_format_term([F0,N,P], [S|SP]) :-
    atom_string(F, F0),
    pi_head(F/N, H),
    length(NamedArgs, N),
    maplist(=('$VAR'('_')), NamedArgs),
    H =.. [F|NamedArgs],
    term_string(H, S, [quoted(true),
                       character_escapes(true),
                       spacing(next_argument),
                       numbervars(true),
                       priority(P)]),
    term_string(_, S, [subterm_positions(SP)]).

sweep_current_functors(A0, Col) :-
    (   A0 == []
    ->  true
    ;   A = A0
    ),
    findall([F|A],
            (   current_functor(F0, A),
                atom(F0),
                term_string(F0, F)
            ),
            Col).

sweep_term_replace([FileName0,BodyIndent,TemplateString,GoalString,FinalString,RepString], Res) :-
    term_string(Template, TemplateString, [variable_names(TemplateVarNames)]),
    term_string(Goal, GoalString, [variable_names(GoalVarNames)]),
    maplist(term_string, Final, FinalString),
    term_string(Rep, RepString, [variable_names(VarNames0)]),
    maplist({GoalVarNames}/[VarName]>>ignore(memberchk(VarName, GoalVarNames)),
            TemplateVarNames),
    maplist({VarNames0}/[VarName]>>ignore(memberchk(VarName, VarNames0)),
            TemplateVarNames),
    atom_string(FileName, FileName0),
    xref_source(FileName),
    sweep_module_path_(Module, FileName),
    setup_call_cleanup(prolog_open_source(FileName, Stream),
                       sweep_replace_stream(Stream, FileName, Module, BodyIndent, Final, Template-Goal, Rep-VarNames0, Res),
                       prolog_close_source(Stream)).

sweep_anon_var_names(Term, VarNames, AnonVars) :-
    term_variables(Term, TermVars),
    convlist({VarNames}/[Var,'_'=Var]>>(   \+ (   member(_=VV, VarNames),
                                                  Var == VV
                                              )
                                       ),
             TermVars, AnonVars).

sweep_replace_stream(Stream, FileName, Module, BodyIndent, Final, TemplateGoal, Rep-VarNames0, Res) :-
    read_clause(Stream, Term, [subterm_positions(Pos), variable_names(VarNames1), syntax_errors(dec10)]),
    !,
    sweep_anon_var_names(Rep, VarNames0, AnonVars0),
    sweep_anon_var_names(Term, VarNames1, AnonVars1),
    maplist({VarNames1}/[Name0=Var,Name=Var]>>(   member(Name0=_, VarNames1)
                                              ->  atom_concat(Name0, 'Fresh', Name)
                                              ;   Name = Name0
                                              ),
            VarNames0, VarNames2),
    append(AnonVars1, AnonVars0, AnonVars),
    append(VarNames2, AnonVars, VarNames3),
    append(VarNames1, VarNames3, VarNames),
    sweep_replace_stream_(Term, Pos, Stream, FileName, Module, BodyIndent, Final, TemplateGoal, Rep-VarNames, Res).
sweep_replace_stream(Stream, FileName, Module, BodyIndent, Final, TemplateGoal, RepVarNames, Res) :-
    sweep_replace_stream(Stream, FileName, Module, BodyIndent, Final, TemplateGoal, RepVarNames, Res).

sweep_replace_stream_(end_of_file, _, _, _, _, _, _, _, _, []) :- !.
sweep_replace_stream_(Term, Pos, Stream, FileName, Module, BodyIndent, Final, TemplateGoal, RepVarNames, Res) :-
    (   var(Term)
    ->  State = clause
    ;   memberchk(Term, [(_:-_),(_=>_),(_-->_)])
    ->  State = clause
    ;   Term = (:-_)
    ->  State = directive
    ;   State = head
    ),
    findall(Result,
            sweep_replace_term(Pos, Term, FileName, Module, BodyIndent, 0, 1200, State, Final, TemplateGoal, RepVarNames,Result),
            Res,
            Tail),
    sweep_replace_stream(Stream, FileName, Module, BodyIndent, Final, TemplateGoal, RepVarNames, Tail).



%!  sweep_replace_term(Pos, Term, FileName, Module, BodyIndent, CurrentIndent, Precedence, State, Final, TemplateGoal, RepVarNames, Result) is nondet.

sweep_replace_term(Pos, Term, FileName, Module, BodyIndent, CurrentIndent, Precedence, State, Final, TemplateGoal, RepVarNames, Result) :-
    (   sweep_replace_term_(Pos, Term, FileName, Module, BodyIndent, CurrentIndent, Precedence, State, Final, TemplateGoal, RepVarNames, Result)
    ;   sweep_replace_term_r(Pos, Term, FileName, Module, BodyIndent, CurrentIndent, Precedence, State, Final, TemplateGoal, RepVarNames, Result)
    ).

sweep_replace_term_r(brace_term_position(_, _, Pos), {Term}, FileName, Module, BodyIndent, CurrentIndent0, _Precedence, State0, Final, TemplateGoal, RepVarNames, Result) :-
    CurrentIndent is CurrentIndent0 + BodyIndent,
    (   State0 == data
    ->  State = data
    ;   State0 == goal(2)
    ->  State = goal(0)
    ;   State = State0
    ),
    sweep_replace_term(Pos, Term, FileName, Module, BodyIndent, CurrentIndent, 1200, State, Final, TemplateGoal, RepVarNames, Result).
sweep_replace_term_r(list_position(_, _, Elms, Tail), List, FileName, Module, BodyIndent, CurrentIndent0, _Precedence, _State, Final, TemplateGoal, RepVarNames, Result) :-
    CurrentIndent is CurrentIndent0 + BodyIndent,
    (   nth0(I, Elms, Pos),
        nth0(I, List, Term),
        sweep_replace_term(Pos, Term, FileName, Module, BodyIndent, CurrentIndent, 999, data, Final, TemplateGoal, RepVarNames, Result)
    ;   Tail == none
    ->  false
    ;   list_tail(List, Term),
        sweep_replace_term(Tail, Term, FileName, Module, BodyIndent, CurrentIndent, 999, data, Final, TemplateGoal, RepVarNames, Result)
    ).
sweep_replace_term_r(term_position(From, To, _, _, ArgsPos), Term, FileName, Module0, BodyIndent, CurrentIndent0, _, State0, Final, TemplateGoal, RepVarNames, Result) :-
    CurrentIndent is CurrentIndent0 + BodyIndent,
    compound_name_arguments(Term, Functor, Arguments),
    length(Arguments, Arity),
    (   Arguments == []         % nullary compound, e.g. foo()
    ->  true
    ;   Arguments = [Arg]
    ->  ArgsPos = [ArgPos],
        arg(1, ArgPos, ArgBeg),
        arg(2, ArgPos, ArgEnd),
        Module = Module0,
        (   ArgBeg == From,
            (   xref_op(FileName, op(Precedence0, Assoc, Functor))
            ;   current_op(Precedence0, Assoc, Functor)
            ),
            memberchk(Assoc, [xf,yf])
        ->  (   Assoc == xf
            ->  Precedence is Precedence0 - 1
            ;   Precedence = Precedence0
            )
        ;   ArgEnd == To,
            (   xref_op(FileName, op(Precedence0, Assoc, Functor))
            ;   current_op(Precedence0, Assoc, Functor)
            ),
            memberchk(Assoc, [fx,fy])
        ->  (   Assoc == fx
            ->  Precedence is Precedence0 - 1
            ;   Precedence = Precedence0
            )
        ;   Precedence = 999
        ),
        sweep_replace_update_state(FileName, Module, Functor, Arity, 1, State0, State),
        sweep_replace_term(ArgPos, Arg, FileName, Module, BodyIndent, CurrentIndent, Precedence, State, Final, TemplateGoal, RepVarNames, Result)
    ;   Arguments = [Left, Right]
    ->  ArgsPos = [LeftPos, RightPos],
        arg(2, RightPos, ArgEnd),
        (   ArgEnd == To,        % infix operator
            (   xref_op(FileName, op(Precedence0, Assoc, Functor))
            ;   current_op(Precedence0, Assoc, Functor)
            ),
            memberchk(Assoc, [xfx, xfy, yfy, yfx])
        ->  (   Assoc == xfx
            ->  LeftPrecedence is Precedence0 - 1,
                RightPrecedence is Precedence0 - 1
            ;   Assoc == xfy
            ->  LeftPrecedence is Precedence0 - 1,
                RightPrecedence = Precedence0
            ;   Assoc == yfx
            ->  LeftPrecedence = Precedence0,
                RightPrecedence is Precedence0 - 1
            ;   Assoc == yfy
            ->  LeftPrecedence = Precedence0,
                RightPrecedence = Precedence0
            )
        ;   LeftPrecedence = 999,
            RightPrecedence = 999
        ),
        (   Functor = ':',
            atom(Left),
            member(State0, [goal(_),head])
        ->  Module = Left,
            LeftState = module,
            RightState = State0
        ;   Module = Module0,
            sweep_replace_update_state(FileName, Module, Functor, Arity, 1, State0, LeftState),
            sweep_replace_update_state(FileName, Module, Functor, Arity, 2, State0, RightState)
        ),
        (   sweep_replace_term(LeftPos, Left, FileName, Module, BodyIndent, CurrentIndent, LeftPrecedence, LeftState, Final, TemplateGoal, RepVarNames, Result)
        ;   sweep_replace_term(RightPos, Right, FileName, Module, BodyIndent, CurrentIndent, RightPrecedence, RightState, Final, TemplateGoal, RepVarNames, Result)
        )
    ;   nth1(I, ArgsPos, ArgPos),
        nth1(I, Arguments, Arg),
        Module = Module0,
        sweep_replace_update_state(FileName, Module, Functor, Arity, I, State0, ArgState),
        sweep_replace_term(ArgPos, Arg, FileName, Module, BodyIndent, CurrentIndent, 999, ArgState, Final, TemplateGoal, RepVarNames, Result)
    ).
sweep_replace_term_r(dict_position(_, _, _, _, KeyValuePosList), Term, FileName, Module, BodyIndent, CurrentIndent0, _, _, Final, TemplateGoal, RepVarNames, Result) :-
    CurrentIndent is CurrentIndent0 + BodyIndent,
    member(key_value_position(_, _, _, _, Key, _, ValuePos), KeyValuePosList),
    get_dict(Key, Term, Value),
    sweep_replace_term(ValuePos, Value, FileName, Module, BodyIndent, CurrentIndent, 999, data, Final, TemplateGoal, RepVarNames, Result).
sweep_replace_term_r(parentheses_term_position(_, _, Pos), Term, FileName, Module, BodyIndent, CurrentIndent, _, State, Final, TemplateGoal, RepVarNames, Result) :-
    sweep_replace_term(Pos, Term, FileName, Module, BodyIndent, CurrentIndent, 1200, State, Final, TemplateGoal, RepVarNames, Result).
sweep_replace_term_r(quasi_quotation_position(_, _, Term, Pos, _), _, FileName, Module, BodyIndent, CurrentIndent0, _, _, Final, TemplateGoal, RepVarNames, Result) :-
    CurrentIndent is CurrentIndent0 + BodyIndent,
    sweep_replace_term(Pos, Term, FileName, Module, BodyIndent, CurrentIndent, 999, syntax, Final, TemplateGoal, RepVarNames, Result).

sweep_replace_update_state(_, _, _, _, _, data, data) :- !.
sweep_replace_update_state(_, _, _, _, _, syntax, data) :- !.
sweep_replace_update_state(_, _, _, _, _, module, data) :- !.
sweep_replace_update_state(_FileName, _Module, ':-', 1, 1, directive, goal(0)) :- !.
sweep_replace_update_state(_FileName, _Module, ':-', 2, 1, clause, head) :- !.
sweep_replace_update_state(_FileName, _Module, ':-', 2, 2, clause, goal(0)) :- !.
sweep_replace_update_state(_FileName, _Module, '=>', 2, 1, clause, head) :- !.
sweep_replace_update_state(_FileName, _Module, '=>', 2, 2, clause, goal(0)) :- !.
sweep_replace_update_state(_FileName, _Module, '-->', 2, 1, clause, head) :- !.
sweep_replace_update_state(_FileName, _Module, '-->', 2, 2, clause, goal(2)) :- !.
sweep_replace_update_state(_FileName, _Module, _Functor, _Arity, _I, clause, data) :- !.
sweep_replace_update_state(_FileName, _Module, ',', 2, 1, head, head) :- !.     %  SSU head
sweep_replace_update_state(_FileName, _Module, ',', 2, 2, head, goal(0)) :- !.  %  SSU guard
sweep_replace_update_state(_FileName, _Module, _Functor, _Arity, _I, head, data) :- !.
sweep_replace_update_state(_FileName, Module, Functor, Arity, I, goal(N0), State) :-
    pi_head(Functor/Arity,Head),
    (   (   (   @(predicate_property(Head, meta_predicate(Spec)), Module)
            ;   catch(infer_meta_predicate(Head, Spec),
                      error(permission_error(access, private_procedure, _),
                            context(system:clause/2, _)),
                  false)
            )
        ->  arg(I, Spec, A),
            callable_arg(A, M)
        )
    ->  N is N0 + M,
        State = goal(N)
    ;   State = data
    ).

:- dynamic sweep_match_replacement/1.

sweep_replace_term_(Pos, Term, _FileName, Module, _BodyIndent, CurrentIndent, Precedence, State, Final, Template-Goal, Rep-VarNames, replace(Beg, End, New)) :-
    compound(Pos),
    Pos \= parentheses_term_position(_, _, _),
    subsumes_term(Template, Term),
    member(FS, Final),
    subsumes_term(FS, State),
    \+ \+ (   Template = Term,
              catch(Goal, _, false),
              with_output_to(
                  string(New0),
                  (   State = goal(_)
                  ->  prolog_listing:portray_body(Rep, CurrentIndent, noindent, Precedence, current_output,
                                                  [module(Module), variable_names(VarNames)])
                  ;   prolog_listing:pprint(current_output, Rep, Precedence,
                                            [module(Module), variable_names(VarNames)])
                  )
              ),
              asserta(sweep_match_replacement(New0))
          ),
    retract(sweep_match_replacement(New)),
    arg(1, Pos, Beg),
    arg(2, Pos, End).

list_tail([_|T0], T) :- nonvar(T0), T0 = [_|_], !, list_tail(T0, T).
list_tail([_|T], T).

sweep_terms_at_point([String, Start, Point], Res) :-
    (   sweep_source_id(Path),
        findall(Op, xref_op(Path, Op), Ops),
        (   xref_module(Path, Module)
        ->  true
        ;   Module = user
        )
    ->  true
    ;   Module = user, Ops = []
    ),
    with_buffer_stream(
        Stream,
        String,
        (   ignore((   nonvar(Path),
                       set_stream(Stream, file_name(Path))
                   )),
            read_source_term_at_location(Stream, _,
                                         [module(Module),
                                          operators(Ops),
                                          subterm_positions(SubPos)]),
            findall([Beg|End],
                    sweep_terms_at_point_(SubPos, Start, Point, Beg, End),
                    Res)
        )).

sweep_terms_at_point_(SubPos, Start, Point, Beg, End) :-
    SubPos \= parentheses_term_position(_, _, _),
    arg(1, SubPos, Beg0),
    arg(2, SubPos, End0),
    Beg0 =< Point,
    Point =< End0,
    Beg is Beg0 + Start,
    End is End0 + Start.
sweep_terms_at_point_(list_position(_, _, Elms, _), Start, Point, Beg, End) :-
    member(SubPos, Elms),
    sweep_terms_at_point_(SubPos, Start, Point, Beg, End).
sweep_terms_at_point_(list_position(_, _, _, SubPos), Start, Point, Beg, End) :-
    SubPos \== none,
    sweep_terms_at_point_(SubPos, Start, Point, Beg, End).
sweep_terms_at_point_(term_position(_, _, _, _, Args), Start, Point, Beg, End) :-
    member(SubPos, Args),
    sweep_terms_at_point_(SubPos, Start, Point, Beg, End).
sweep_terms_at_point_(dict_position(_, _, _, _, KeyValuePosList), Start, Point, Beg, End) :-
    member(key_value_position(_, _, _, _, _, _, SubPos), KeyValuePosList),
    sweep_terms_at_point_(SubPos, Start, Point, Beg, End).
sweep_terms_at_point_(parentheses_term_position(_, _, SubPos), Start, Point, Beg, End) :-
    sweep_terms_at_point_(SubPos, Start, Point, Beg, End).
sweep_terms_at_point_(quasi_quotation_position(_, _, _, SubPos, _), Start, Point, Beg, End) :-
    sweep_terms_at_point_(SubPos, Start, Point, Beg, End).

sweep_predicate_dependencies([To0|From0], Deps) :-
    atom_string(To, To0),
    atom_string(From, From0),
    setof(PI,
          PI0^Head^By^(
                          xref_defined(To, Head, imported(From)),
                          xref_called(To, Head, By),
                          pi_head(PI0, Head),
                          term_string(PI0, PI)
                      ),
          Deps).

sweep_cleanup_threads(_,_) :-
    sweep_cleanup_threads.

sweep_cleanup_threads :-
    is_thread(sweep_supervisor),
    !,
    thread_send_message(sweep_supervisor, cleanup),
    thread_join(sweep_supervisor, _).
sweep_cleanup_threads.

:- meta_predicate sweep_create_thread(0, -).
:- meta_predicate sweep_create_thread(0, -, +).

sweep_create_thread(Goal, T) :-
    sweep_create_thread(Goal, T, []).

sweep_create_thread(Goal, T, Options) :-
    (   is_thread(sweep_supervisor)
    ->  true
    ;   thread_self(S),
        thread_create(sweep_supervisor_start(S), _, [alias(sweep_supervisor)]),
        thread_get_message(sweep_supervisor_started)
    ),
    thread_create((sweep_thread_start, Goal), T,
                  [at_exit(sweep_thread_at_exit)|Options]).

sweep_thread_start :-
    thread_self(T),
    thread_send_message(sweep_supervisor, new(T)).

sweep_thread_at_exit :-
    (   is_thread(sweep_supervisor)
    ->  thread_self(T),
        catch(thread_send_message(sweep_supervisor, exit(T)), _, true)
    ;   true
    ).

sweep_supervisor_start(Caller) :-
    thread_send_message(Caller, sweep_supervisor_started),
    sweep_supervisor_loop([]).

sweep_supervisor_loop(Threads) :-
    thread_get_message(Message),
    sweep_supervisor_loop_(Message, Threads).

sweep_supervisor_loop_(cleanup, Ts) =>
    maplist(cleanup_thread, Ts).
sweep_supervisor_loop_(new(T), Ts) =>
    sweep_supervisor_loop([T|Ts]).
sweep_supervisor_loop_(exit(T), Ts0) =>
    cleanup_thread(T),
    select(T, Ts0, Ts),
    sweep_supervisor_loop(Ts).
sweep_supervisor_loop_(_, Ts) =>
    sweep_supervisor_loop(Ts).

sweep_kill_thread(T, _) :-
    cleanup_thread(T).

cleanup_thread(T) :-
    is_thread(T),
    !,
    catch(cleanup_thread_(T), _, true).
cleanup_thread(_).

cleanup_thread_(T) :-
    thread_property(T, detached(false)),
    !,
    thread_detach(T),
    (   thread_property(T, status(running))
    ->  thread_signal(T, thread_exit(0))
    ;   true
    ).
cleanup_thread_(T) :-
    thread_signal(T, thread_exit(0)).

sweep_async_goal([GoalString|FD], TId) :-
    term_string(Goal, GoalString),
    random_between(1, 1024, Cookie),
    thread_self(Self),
    sweep_create_thread(sweep_start_async_goal(Self, Cookie, Goal, FD), T),
    thread_get_message(sweep_async_goal_started(Cookie)),
    thread_property(T, id(TId)).

sweep_start_async_goal(Caller, Cookie, Goal, FD) :-
    thread_send_message(Caller, sweep_async_goal_started(Cookie)),
    setup_call_cleanup((   sweep_fd_open(FD, Out),
                           set_prolog_IO(current_input, Out, Out)
                       ),
                       once(Goal),
                       (   format("~nSweep async goal finished~n"),
                           close(Out)
                       )).

sweep_interrupt_async_goal(TId, TId) :-
    thread_signal(TId, throw(interrupted)).

sweep_set_breakpoint([File0,Line,Char], Id) :-
    atom_string(File, File0),
    set_breakpoint(File, Line, Char, Id).

sweep_set_breakpoint_condition([Id|Cond], _) :-
    set_breakpoint_condition(Id, Cond).

sweep_delete_breakpoint(Id, _) :-
    delete_breakpoint(Id).

sweep_current_breakpoints(_, BPs) :-
    findall(BP-Claue,
            breakpoint_property(BP, clause(Claue)),
            BPs0),
    maplist(format_breakpoint, BPs0, BPs).

format_breakpoint(Id-Clause, [["id"|Id],["predicate"|Pred],["clause"|ClauseNum]|BP]) :-
    clause_property(Clause, predicate(Pred0)),
    term_string(Pred0, Pred),
    pi_head(Pred0, Head),
    nth_clause(Head, ClauseNum, Clause),
    findall(Prop, breakpoint_property(Id, Prop), Props),
    convlist(format_breakpoint_property, Props, BP).

format_breakpoint_property(file(File0), ["file"|File]) :-
    atom_string(File0, File).
format_breakpoint_property(line_count(Line), ["line"|Line]).
format_breakpoint_property(character_range(Start0, Len), ["range",Start,End]) :-
    Start is Start0 + 1, End is Start + Len.
format_breakpoint_property(condition(Cond), ["condition"|Cond]).

sweep_current_breakpoints_in_region([Path0, Beg, End], BPs) :-
    atom_string(Path, Path0),
    findall([BPBeg|BPEnd],
            (   breakpoint_property(BPId, file(Path)),
                breakpoint_property(BPId, character_range(BPBeg0, Len)),
                BPBeg is BPBeg0 + 1,
                Beg =< BPBeg,
                BPBeg =< End,
                BPEnd is BPBeg + Len
            ),
            BPs).

sweep_breakpoint_range(Id, [Beg|End]) :-
    breakpoint_property(Id, character_range(Beg0, Len)),
    Beg is Beg0 + 1,
    End is Beg + Len.

sweep_breakpoint_file(Id, File) :-
    breakpoint_property(Id, file(File0)),
    atom_string(File0, File).

sweep_expand_macro(String0, String) :-
    sweep_current_module(M),
    term_string(Term0, String0, [variable_names(Vs),
                                 subterm_positions(Pos0),
                                 module(M)]),
    functor(Term0, '#', 1),
    macros:expand_macros(M, Term0, Term, Pos0, _, _, _),
    term_string(Term, String, [variable_names(Vs), module(M)]).

sweep_variable_start_code(C, _) :- code_type(C, prolog_var_start).

sweep_term_variable_names(String, Names) :-
    term_string(_, String, [variable_names(VarNames)]),
    maplist([Atom=_,Name]>>atom_string(Atom, Name), VarNames, Names).

sweep_goal_may_cut(String, _) :-
    term_string(Goal, String),
    sweep_goal_may_cut_(Goal),
    !.

sweep_goal_may_cut_((_->A;B)) =>
    (   sweep_goal_may_cut_(A)
    ;   sweep_goal_may_cut_(B)
    ).
sweep_goal_may_cut_(A;B) =>
    (   sweep_goal_may_cut_(A)
    ;   sweep_goal_may_cut_(B)
    ).
sweep_goal_may_cut_((A,B)) =>
    (   sweep_goal_may_cut_(A)
    ;   sweep_goal_may_cut_(B)
    ).
sweep_goal_may_cut_(!) =>
    true.
sweep_goal_may_cut_(_) =>
    false.
