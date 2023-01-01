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
            sweep_functor_arity_pi/2,
            sweep_modules_collection/2,
            sweep_packs_collection/2,
            sweep_pack_install/2,
            sweep_op_info/2,
            sweep_imenu_index/2,
            sweep_module_path/2,
            sweep_thread_signal/2,
            sweep_top_level_server/2,
            sweep_top_level_threads/2,
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
            sweep_atom_collection/2,
            sweep_context_callable/2,
            sweep_predicate_completion_candidates/2,
            sweep_exportable_predicates/2,
            sweep_interrupt/0,
            sweep_string_to_atom/2,
            sweep_file_path_in_library/2,
            sweep_file_missing_dependencies/2,
            sweep_format_head/2,
            sweep_format_term/2,
            sweep_current_functors/2
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

:- if(exists_source(library(help))).
:- use_module(library(help)).
:- endif.


:- meta_predicate with_buffer_stream(-, +, 0).

:- dynamic sweep_top_level_thread_buffer/2,
           sweep_open_buffer/3,
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

sweep_top_level_threads(_, Ts) :-
    findall([Id, Buffer, Status, Stack, CPUTime],
            (   sweep_top_level_thread_buffer(Id, Buffer),
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

sweep_set_prolog_flag([Flag0|Value0], []) :-
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
    asserta(sweep_current_comment(Kind, Start, Len)).
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


sweep_module_path(ModuleName, Path) :-
    atom_string(Module, ModuleName),
    sweep_module_path_(Module, Path0),
    atom_string(Path0, Path).


sweep_module_path_(Module, Path) :-
    module_property(Module, file(Path)), !.
sweep_module_path_(Module, Path) :-
    xref_module(Path, Module), !.
sweep_module_path_(Module, Path) :-
    '$autoload':library_index(_, Module, Path0), atom_concat(Path0, '.pl', Path).

sweep_predicate_properties(P0, Props) :-
    term_string(P, P0),
    pi_head(P, Head),
    findall(Prop, predicate_property(Head, Prop), Props).

sweep_predicate_html_documentation(P0, D) :-
    term_string(P1, P0),
    (   P1 = M:F/N
    ->  true
    ;   P1 = F/N, M = system
    ),
    (   (   current_module(M)
        ;   xref_module(_, M)
        )
    ->  true
    ;   '$autoload':library_index(_, M, Path),
        xref_source(Path, [comments(store)])
    ),
    (   M == system
    ->  pldoc_man:load_man_object(F/N, _, _, DOM)
    ;   doc_comment(M:F/N, Pos, _, Comment),
        pldoc_html:pred_dom(M:F/N, [], Pos-Comment, DOM)
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

sweep_modules_collection([], Modules) :-
    findall([M|P], ( module_property(M, file(P0)), atom_string(P0, P) ), Modules0, Tail),
    setof([M|P], P0^N^('$autoload':library_index(N, M, P0), string_concat(P0, ".pl", P) ), Tail),
    list_to_set(Modules0, Modules1),
    maplist(sweep_module_description, Modules1, Modules).

sweep_module_description([M0|P], [M|[P|D]]) :-
   doc_comment(M0:module(D0), _, _, _),
   atom_string(M0, M),
   atom_string(D0, D).
sweep_module_description([M0|P], [M|[P]]) :- atom_string(M0, M).

sweep_predicate_references(MFN, Refs) :-
    term_string(M:F/N, MFN),
    pi_head(F/N, H),
    findall([B,Path|Line],
            (xref_called(Path0, H, B0, _, Line),
             pi_head(B1, B0),
             term_string(B1, B),
             atom_string(Path0, Path)),
            Refs,
            Tail),
    findall([B,Path|Line],
            (xref_called(Path0, M:H, B0, _, Line),
             pi_head(B1, B0),
             term_string(B1, B),
             atom_string(Path0, Path)),
            Tail).


sweep_predicate_location(MFN, [Path|Line]) :-
    term_string(M:F/N, MFN),
    !,
    pi_head(F/N, H),
    (   sweep_predicate_location_(M, H, Path, Line)
    ->  true
    ;   sweep_predicate_location_(H, Path, Line)
    ).
sweep_predicate_location(FN, [Path|Line]) :-
    term_string(F/N, FN),
    !,
    pi_head(F/N, H),
    sweep_predicate_location_(H, Path, Line).

sweep_predicate_apropos(Query0, Matches) :-
    atom_string(Query, Query0),
    findall([S,Path|Line],
            (prolog_help:apropos(Query, M:F/N, _, P), P >= 0.3,
             format(string(S), '~W', [M:F/N, [quoted(true), character_escapes(true)]]),
             pi_head(F/N, Head),
             sweep_predicate_location_(M, Head, Path, Line)),
            Matches, Tail),
    findall([S,Path],
            (prolog_help:apropos(Query, F/N, _, P), P >= 0.3,
             format(string(S), '~W', [F/N, [quoted(true), character_escapes(true)]]),
             pi_head(F/N, Head),
             sweep_predicate_location_(Head, Path, Line)),
            Tail).

sweep_predicate_location_(H, Path, Line) :-
    xref_defined(Path0, H, How),
    xref_definition_line(How, Line),
    !,
    atom_string(Path0, Path).
sweep_predicate_location_(H, Path, Line) :-
    predicate_property(H, file(Path0)),
    predicate_property(H, line_count(Line)),
    atom_string(Path0, Path).

sweep_predicate_location_(M, H, Path, Line) :-
    (   xref_defined(Path0, M:H, How),
        xref_definition_line(How, Line)
    ->  true
    ;   xref_defined(Path0, H, How),
        xref_definition_line(How, Line),
        xref_module(Path0, M)
    ),
    !,
    atom_string(Path0, Path).
sweep_predicate_location_(M, H, Path, Line) :-
    predicate_property(M:H, file(Path0)),
    predicate_property(M:H, line_count(Line)),
    atom_string(Path0, Path).


sweep_predicates_collection(Sub, Preds) :-
    findall(M:F/N,
            ( current_predicate(M:F/N),
              pi_head(F/N, H),
              (   M == system
              ->  true
              ;   \+ (predicate_property(M:H, imported_from(M1)), M \= M1)
              )
            ),
            Preds0,
            Tail0),
    findall(M:F/N,
            ( '$autoload':library_index(H, M, _),
              pi_head(F/N, H)
            ),
            Tail0,
            Tail1),
    findall(M:F/N,
            ( xref_defined(SourceId, H, local(_)),
              (   xref_module(SourceId, M)
              ->  true
              ;   M = user
              ),
              \+ (predicate_property(M:H, imported_from(M1)), M \= M1),
              pi_head(F/N, H)
            ),
            Tail1,
            Tail),
    findall(M:F/N,
            ( xref_defined(_, H, imported(SourceId)),
              (   xref_module(SourceId, M)
              ->  true
              ;   M = user
              ),
              pi_head(F/N, H)
            ),
            Tail),
    list_to_set(Preds0, Preds1),
    maplist(sweep_predicate_description, Preds1, Preds2),
    include(sweep_predicate_non_hidden, Preds2, Preds3),
    (   Sub == []
    ->  Preds = Preds3
    ;   include(sweep_predicate_matches(Sub), Preds3, Preds)
    ).

sweep_predicate_matches(Sub, [String|_]) :-
    sub_string(String, _, _, _, Sub).

sweep_predicate_non_hidden([String|_]) :-
    \+ sub_string(String, _, _, _, ":'$").

sweep_predicate_description(M:F/N, [S|T]) :-
    sweep_predicate_description_(M, F, N, T),
    format(string(S),
           '~W',
           [M:F/N, [quoted(true), character_escapes(true)]]).

sweep_predicate_description_(M, F, N, [D]) :-
    doc_comment(M:F/N, _, D0, _), !, atom_string(D0, D).
sweep_predicate_description_(_M, F, N, [D]) :-
    man_object_property(F/N, summary(D0)), !, atom_string(D0, D).
sweep_predicate_description_(_, _, _, []).

sweep_packs_collection(SearchString, Packs) :-
    prolog_pack:query_pack_server(search(SearchString), true(Packs0), []),
    maplist(sweep_pack_info, Packs0, Packs).

sweep_pack_info(pack(Name0, _, Desc0, Version0, URLS0), [Name, Desc, Version, URLS]) :-
    atom_string(Name0, Name),
    atom_string(Desc0, Desc),
    atom_string(Version0, Version),
    maplist(atom_string, URLS0, URLS).

sweep_pack_install(PackName, []) :-
    atom_string(Pack, PackName), pack_install(Pack, [silent(true), upgrade(true), interactive(false)]).

sweep_colourise_query([String|Offset], _) :-
    prolog_colourise_query(String, module(sweep), sweep_handle_fragment_(Offset)).

sweep_color_normalized(Offset, Col, Nom) :-
    Col =.. [Nom0|Rest],
    sweep_color_normalized_(Offset, Nom0, Rest, Nom).

sweep_color_normalized_(_, Goal0, [Kind0,Head|_], [Goal,Kind,F,N]) :-
    sweep_color_goal(Goal0),
    !,
    atom_string(Goal0, Goal),
    sweeprolog_goal_kind_normalized(Kind0, Kind),
    (   (   var(Head)
        ->  true
        ;   Head == []
        )
    ->  F = Head, N = 0
    ;   pi_head(F0/N, Head),
        atom_string(F0, F)
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
sweep_color_normalized_(_, Nom0, _, Nom) :-
    atom_string(Nom0, Nom).

sweeprolog_goal_kind_normalized(autoload(Path0), ["autoload"|Path]) :-
    !,
    absolute_file_name(Path0, Path1, [extensions([pl])]),
    atom_string(Path1, Path).
sweeprolog_goal_kind_normalized(Kind0, Kind) :-
    term_string(Kind0, Kind).

sweep_color_goal(goal).
sweep_color_goal(goal_term).
sweep_color_goal(head).
sweep_color_goal(head_term).

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

sweep_path_module([], "user")    :- !.
sweep_path_module(Path0, Module) :-
    atom_string(Path, Path0),
    xref_module(Path, Module0),
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

sweep_load_buffer([String|Path0], Result) :-
    atom_string(Path, Path0),
    with_buffer_stream(Stream,
                       String,
                       sweep_load_buffer_(Stream, Path, Result)).

sweep_load_buffer_(Stream, Path, true) :-
    set_stream(Stream, file_name(Path)),
    @(load_files(Path, [stream(Stream)]), user).

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

sweep_top_level_server(_, Port) :-
    tcp_socket(ServerSocket),
    tcp_setopt(ServerSocket, reuseaddr),
    tcp_bind(ServerSocket, Port),
    tcp_listen(ServerSocket, 5),
    thread_self(Self),
    thread_create(sweep_top_level_server_start(Self, ServerSocket), T,
                  [ alias(sweep_top_level_server)
                  ]),
    at_halt((   is_thread(T),
                thread_property(T, status(running))
            ->  thread_signal(T, thread_exit(0)),
                thread_join(T, _)
            ;   true
            )),
    thread_get_message(sweep_top_level_server_started).

sweep_top_level_server_start(Caller, ServerSocket) :-
    thread_send_message(Caller, sweep_top_level_server_started),
    sweep_top_level_server_loop(ServerSocket).

sweep_top_level_server_loop(ServerSocket) :-
    thread_get_message(Message),
    sweep_top_level_server_loop_(Message, ServerSocket).

sweep_top_level_server_loop_(accept(Buffer), ServerSocket) :-
    !,
    tcp_accept(ServerSocket, Slave, Peer),
    tcp_open_socket(Slave, InStream, OutStream),
    set_stream(InStream, close_on_abort(false)),
    set_stream(OutStream, close_on_abort(false)),
    thread_create(sweep_top_level_client(InStream, OutStream, Peer), T, [detached(true)]),
    thread_property(T, id(Id)),
    asserta(sweep_top_level_thread_buffer(Id, Buffer)),
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
    thread_self(Self),
    thread_property(Self, id(Id)),
    thread_at_exit(retractall(sweep_top_level_thread_buffer(Id, _))),
    call_cleanup(prolog,
                 ( close(InStream, [force(true)]),
                   close(OutStream, [force(true)])
                 )).
sweep_top_level_client(InStream, OutStream, _) :-
    close(InStream),
    close(OutStream),
    thread_self(Self),
    thread_property(Self, id(Id)),
    retractall(sweep_top_level_thread_buffer(Id, _)).

%!  sweep_accept_top_level_client(+Buffer, -Result) is det.
%
%   Signal the top-level server thread to accept a new TCP connection
%   from buffer Buffer.

sweep_accept_top_level_client(Buffer, _) :-
    thread_send_message(sweep_top_level_server, accept(Buffer)).

sweep_thread_signal([ThreadId|Goal0], _) :-
    term_string(Goal, Goal0),
    thread_signal(ThreadId, Goal).

sweep_local_predicate_export_comment([Path0,F0,A],Comm) :-
    atom_string(Path, Path0),
    atom_string(F, F0),
    doc_comment(_:F/A, Path:_, _Summary, Comment),
    comment_modes(Comment, Modes),
    pi_head(F/A, Head),
    member(ModeAndDet, Modes),
    strip_det(ModeAndDet, Head),
    Head =.. [_|Args],
    Head2 =.. ['DUMMY'|Args],
    term_string(Head2, Syn0,
                [ module(pldoc_modes),
                  quoted(false)
                ]),
    sub_string(Syn0, 6, _, 1, Comm).

strip_det(Mode is _, Mode) :- !.
strip_det(//(Mode), Mode) :- !.
strip_det(Mode, Mode).

sweep_functor_arity_pi([M,F0,A|_], PI) :-
    !, atom_string(F, F0), term_string(M:F/A, PI).
sweep_functor_arity_pi([F0,A|Path0], PI) :-
    atom_string(F, F0),
    pi_head(F/A, Head),
    sweep_current_module(M0),
    (   @(predicate_property(M:Head, visible), M0),
        \+ @(predicate_property(M:Head, imported_from(_)), M0)
    ->  T = M:F/A
    ;   xref_defined(_, Head, imported(Other)), xref_module(Other, M)
    ->  T = M:F/A
    ;   string(Path0),
        atom_string(Path, Path0),
        xref_defined(Path, Head, _)
    ->  T = M0:F/A
    ;   T = F/A
    ),
    term_string(T, PI).

sweep_current_module(Module) :-
    sweep_main_thread,
    user:sweep_funcall("buffer-file-name", String),
    string(String),
    atom_string(Path, String),
    sweep_module_path_(Module, Path).
sweep_current_module(user).

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
    user:sweep_funcall("buffer-file-name", Path),
    string(Path).

sweep_atom_collection(Sub, Col) :-
    findall(S,
            (   current_atom(A),
                atom_string(A, S),
                sub_string(S, _, _, _, Sub)
            ),
            Col).

sweep_predicate_completion_candidates(D, Ps) :-
    integer(D),
    sweep_current_module(M),
    findall(H,
            (   (   @(predicate_property(H, visible), M)
                ;   xref_defined(_, H, _)
                ),
                pi_head(_/N, H),
                N - D >= 0
            ),
            Hs),
    maplist(sweep_format_predicate(M, D), Hs, Ps).

sweep_format_predicate(M0, D, H0, [S|SP]) :-
    pi_head(F/N0, H0),
    N is N0 - D,
    length(NamedArgs, N),
    append(NamedArgs, _, OpenNamedArgs),
    (   @(predicate_property(H0, implementation_module(M)), M0),
        predicate_argument_names(M:F/N0, As)
    ->  maplist(name_variable, As, Vs), OpenNamedArgs = Vs
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
    (   xref_op(_, op(1200, _, F))
    ->  true
    ;   current_op(1200, _, F)
    ),
    !,
    (   F == (-->)
    ->  R0 = 2
    ;   R0 = 0
    ),
    sweep_context_callable_(T, R0, 0, R).
sweep_context_callable([_|T], R) :-
    sweep_context_callable(T, R).

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
sweep_context_callable_arg(Neck, _, 0) :-
    (   xref_op(_, op(1200, _, Neck))
    ->  true
    ;   current_op(1200, _, Neck)
    ),
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
                pi_head(D1, D0),
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
    term_string(Spec1, Spec).

predicate_argument_names(M:F/A, Args) :-
    doc_comment(M:F/A, _, _, C),
    comment_modes(C, ModeAndDets),
    member(ModeAndDet, ModeAndDets),
    strip_det(ModeAndDet, Head),
    Head =.. [_|Args0],
    length(Args0, A),
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


sweep_format_head([F0|A], R) :-
    atom_string(F, F0),
    pi_head(F/A, H),
    sweep_current_module(M),
    sweep_format_predicate(M, 0, H, R).

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
                atom_string(F0, F)
            ),
            Col).
