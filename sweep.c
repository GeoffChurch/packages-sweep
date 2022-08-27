#include "sweep.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

int plugin_is_GPL_compatible;

term_t o = 0;

char*
estring_to_cstring(emacs_env *eenv, emacs_value estring, ptrdiff_t *len_p) {
  char * buf = NULL;
  ptrdiff_t len = 0;

  if (len_p == NULL) len_p = &len;

  if (!eenv->copy_string_contents(eenv, estring, NULL, len_p)) {
    ethrow(eenv, "Failed to get string length");
    return NULL;
  }
  if ((buf = (char*)malloc((*len_p))) == NULL) {
    ethrow(eenv, "malloc failed");
    return NULL;
  }
  memset(buf, 0, (*len_p));
  if (!eenv->copy_string_contents(eenv, estring, buf, len_p)) {
    ethrow(eenv, "Failed to copy string contents");
    free(buf);
    buf = NULL;
  }

  return buf;
}

int
estring_to_pstring(emacs_env *eenv, emacs_value estring, term_t t) {
  ptrdiff_t len = 0;
  char *buf = NULL;
  int i = 0;

  if ((buf = estring_to_cstring(eenv, estring, &len)) == NULL) return -1;

  i = PL_put_string_nchars(t, len - 1, buf);
  free(buf);
  return i;
}

static emacs_value
econs(emacs_env *env, emacs_value car, emacs_value cdr) {
  emacs_value args[2] = {car, cdr};
  return env->funcall (env, env->intern (env, "cons"), 2, args);
}

static emacs_value
ecar(emacs_env *env, emacs_value cons) {
  return env->funcall (env, env->intern (env, "car"), 1, &cons);
}

static emacs_value
ecdr(emacs_env *env, emacs_value cons) {
  return env->funcall (env, env->intern (env, "cdr"), 1, &cons);
}

void
ethrow(emacs_env *env, const char * message) {
  ptrdiff_t  len = strlen(message);

  emacs_value str = env->make_string(env, message, len);
  emacs_value arg = env->funcall (env, env->intern (env, "list"), 1, &str);
  env->non_local_exit_signal(env, env->intern(env, "error"), arg);
}

emacs_value
enil(emacs_env *env) { return env->intern(env, "nil"); }

emacs_value
et(emacs_env *env) { return env->intern(env, "t"); }

static emacs_value
term_to_value_list(emacs_env *eenv, term_t l) {
  term_t      ph = PL_new_term_ref();
  term_t      pt = PL_new_term_ref();

  if (PL_get_list(l, ph, pt)) {
    return econs(eenv, term_to_value(eenv, ph), term_to_value(eenv, pt));
  } else return NULL;
}

static emacs_value
term_to_value_integer(emacs_env *eenv, term_t t) {
  emacs_value v = NULL;
  int64_t     l = -1;
  if (PL_get_int64(t, &l)) {

    v = eenv->make_integer(eenv, l);
  }
  return v;
}

emacs_value
term_to_value_string(emacs_env *eenv, term_t t) {
  char * string = NULL;
  emacs_value v = NULL;
  size_t      l = -1;
  if (PL_get_string_chars(t, &string, &l)) {
    v = eenv->make_string(eenv, string, l);
  }
  return v;
}

emacs_value
term_to_value_atom(emacs_env *eenv, term_t t) {
  char * string = NULL;
  emacs_value v = NULL;
  emacs_value s = NULL;
  size_t      l = -1;

  if (PL_get_nchars(t, &l, &string, CVT_ATOM|REP_UTF8)) {
    s = eenv->make_string(eenv, string, l);
    v = econs(eenv, eenv->intern(eenv, "atom"), s);
  }
  return v;
}

emacs_value
term_to_value_variable(emacs_env *env, term_t t) {
  (void)t;
  return env->intern(env, "variable");
}

emacs_value
term_to_value_dict(emacs_env *env, term_t t) {
  (void)t;
  return env->intern(env, "dict");
}

emacs_value
term_to_value_blob(emacs_env *env, term_t t) {
  (void)t;
  return env->intern(env, "blob");
}

emacs_value
term_to_value_float(emacs_env *env, term_t t) {
  (void)t;
  return env->intern(env, "float");
}

emacs_value
term_to_value_compound(emacs_env *env, term_t t) {
  atom_t name = 0;
  size_t arity = 0;
  term_t arg = PL_new_term_ref();
  const char * chars = NULL;
  size_t len = 0;
  emacs_value * vals = NULL;
  size_t n = 0;
  (void)PL_get_compound_name_arity(t, &name, &arity);
  chars = PL_atom_nchars(name, &len);
  vals = (emacs_value*)malloc(sizeof(emacs_value)*arity + 1);
  if (vals == NULL) {
    ethrow(env, "malloc failed");
    return NULL;
  }
  memset(vals, 0, sizeof(emacs_value)*arity + 1);

  vals[0] = env->make_string(env, chars, len);

  for(n=1; n<=arity; n++) {

    (void)PL_get_arg(n, t, arg);
    vals[n] = term_to_value(env, arg);
  }

  return econs(env, env->intern(env, "compound"), env->funcall(env, env->intern(env, "list"), arity + 1, vals));
}

emacs_value
term_to_value(emacs_env *env, term_t t) {
  switch (PL_term_type(t)) {
  case PL_VARIABLE:
    return term_to_value_variable(env, t);
  case PL_ATOM:
    return term_to_value_atom(env, t);
  case PL_STRING:
    return term_to_value_string(env, t);
  case PL_NIL:
    return enil(env);
  case PL_LIST_PAIR:
    return term_to_value_list(env, t);
  case PL_INTEGER:
    return term_to_value_integer(env, t);
  case PL_TERM:
    return term_to_value_compound(env, t);
  case PL_DICT:
    return term_to_value_dict(env, t);
  case PL_BLOB:
    return term_to_value_blob(env, t);
  case PL_FLOAT:
    return term_to_value_blob(env, t);
  default:
    /* ethrow(env, "Prolog to Elisp conversion failed"); */
    /* return NULL; */
    return env->intern(env, "unconvertable");
  }
}

int
value_to_term_string(emacs_env *env, emacs_value v, term_t t) {
  return estring_to_pstring(env, v, t);
}

int
value_to_term_integer(emacs_env *env, emacs_value v, term_t t) {
  intmax_t l = env->extract_integer(env, v);
  return PL_put_int64(t, l);
}

int
value_to_term_list(emacs_env *env, emacs_value v, term_t t) {
  int r = -1;
  term_t head = PL_new_term_ref();
  term_t tail = PL_new_term_ref();
  emacs_value car = ecar(env, v);
  emacs_value cdr = ecdr(env, v);
  if ((r = value_to_term(env, car, head)) < 0) {
    return r;
  }
  if ((r = value_to_term(env, cdr, tail)) < 0) {
    return r;
  }
  return PL_cons_list(t, head, tail);
}

int
value_to_term(emacs_env *env, emacs_value v, term_t t) {
  int r = -1;
  emacs_value vt = env->type_of(env, v);

  if (env->is_not_nil(env, v)) {
    if (env->eq(env, vt, env->intern(env, "string"))) {
      r = value_to_term_string(env, v, t);
    } else if (env->eq(env, vt, env->intern(env, "integer"))) {
      r = value_to_term_integer(env, v, t);
    } else if (env->eq(env, vt, env->intern(env, "cons"))) {
      r = value_to_term_list(env, v, t);
    } else r = -1;
  } else r = PL_put_nil(t);

  return r;
}

emacs_value
sweep_close_query(emacs_env *env, ptrdiff_t nargs, emacs_value *args, void *data)
{
  qid_t d = PL_current_query();

  (void)data;
  (void)nargs;
  (void)args;

  if (d == 0) {
    ethrow(env, "No current query");
    return NULL;
  }

  switch (PL_close_query(d)) {
  case FALSE:
    return term_to_value(env, PL_exception(d));
  default:
    return et(env);
  }
}

emacs_value
sweep_cut_query(emacs_env *env, ptrdiff_t nargs, emacs_value *args, void *data)
{
  qid_t d = PL_current_query();

  (void)data;
  (void)nargs;
  (void)args;

  if (d == 0) {
    ethrow(env, "No current query");
    return NULL;
  }

  switch (PL_cut_query(d)) {
  case FALSE:
    return term_to_value(env, PL_exception(d));
  default:
    return et(env);
  }
}

emacs_value
sweep_next_solution(emacs_env *env, ptrdiff_t nargs, emacs_value *args, void *data)
{
  qid_t d = PL_current_query();

  (void)data;
  (void)nargs;
  (void)args;

  if (d == 0) {
    ethrow(env, "No current query");
    return NULL;
  }

  switch (PL_next_solution(d)) {
  case PL_S_EXCEPTION:
    return econs(env, env->intern(env, "exception"), term_to_value(env, PL_exception(d)));
  case PL_S_FALSE:
    return enil(env);
  case PL_S_TRUE:
    return econs(env, et(env), term_to_value(env, o));
  case PL_S_LAST:
    return econs(env, env->intern(env, "!"), term_to_value(env, o));
  default:
    return NULL;
  }
}

emacs_value
sweep_open_query(emacs_env *env, ptrdiff_t nargs, emacs_value *args, void *data)
{
  predicate_t p = NULL;
  char *      m = NULL;
  module_t    n = NULL;
  char *      c = NULL;
  char *      f = NULL;
  term_t      a = PL_new_term_refs(2);

  (void)data;
  (void)nargs;

  if (PL_current_query() != 0) {
    ethrow(env, "Prolog is already executing a query");
    goto cleanup;
  }

  if ((c = estring_to_cstring(env, args[0], NULL)) == NULL) {
    goto cleanup;
  }

  n = PL_new_module(PL_new_atom(c));

  if ((m = estring_to_cstring(env, args[1], NULL)) == NULL) {
    goto cleanup;
  }

  if ((f = estring_to_cstring(env, args[2], NULL)) == NULL) {
    goto cleanup;
  }

  p = PL_predicate(f, 2, m);

  if (value_to_term(env, args[3], a+0) < 0) {
    goto cleanup;
  }
  PL_open_query(n, PL_Q_NODEBUG | PL_Q_EXT_STATUS | PL_Q_CATCH_EXCEPTION, p, a);

  o = a+1;

 cleanup:
  if (c != NULL) free(c);
  if (m != NULL) free(m);
  if (f != NULL) free(f);

  return et(env);
}

static emacs_value
sweep_initialize(emacs_env *env, ptrdiff_t nargs, emacs_value *args, void *data)
{
  (void)data;
  int i = 0, r = 0;
  char **argv = (char**)malloc(sizeof(char*)*nargs);
  if (argv == NULL) {
    ethrow(env, "malloc failed");
    return NULL;
  }
  for (i = 0; i < nargs; i++) {
    if ((argv[i] = estring_to_cstring(env, args[i], NULL)) == NULL) {
      free(argv);
      return NULL;
    }
  }
  r = PL_initialise(nargs, argv);
  for (i = 0; i < nargs; i++) {
    free(argv[i]);
  }
  free(argv);
  return env->intern(env, r ? "t" : "nil");
}


static emacs_value
sweep_is_initialized(emacs_env *env, ptrdiff_t nargs, emacs_value *args, void *data)
{
  (void)nargs;
  (void)args;
  (void)data;
  if (PL_is_initialised(NULL, NULL) == FALSE) {
    return enil(env);
  } else return et(env);
}

static emacs_value
sweep_cleanup(emacs_env *env, ptrdiff_t nargs, emacs_value *args, void *data)
{
  (void)nargs;
  (void)data;
  (void)args;
  return env->intern(env, (PL_cleanup(PL_CLEANUP_SUCCESS) ? "t" : "nil"));
}

static void provide(emacs_env *env, const char *feature) {
  emacs_value Qfeat = env->intern(env, feature);
  emacs_value Qprovide = env->intern(env, "provide");

  env->funcall(env, Qprovide, 1, (emacs_value[]){Qfeat});
}

int
emacs_module_init (struct emacs_runtime *runtime)
{
  emacs_env *env = runtime->get_environment (runtime);

  emacs_value symbol_initialize = env->intern (env, "sweep-initialize");
  emacs_value func_initialize =
    env->make_function(env,
                       1, emacs_variadic_function,
                       sweep_initialize,
                       "Initialize Prolog.\n\
ARG1 is passed as argv[0] to `PL_initialise()', which see.\n\
REST is passed as the rest of the command line arguments to Prolog.",
                       NULL);
  emacs_value args_initialize[] = {symbol_initialize, func_initialize};
  env->funcall (env, env->intern (env, "defalias"), 2, args_initialize);

  emacs_value symbol_is_initialized = env->intern (env, "sweep-initialized-p");
  emacs_value func_is_initialized =
    env->make_function(env,
                       0, 0,
                       sweep_is_initialized,
                       "Return t if Prolog is initialized, else return nil.",
                       NULL);
  emacs_value args_is_initialized[] = {symbol_is_initialized, func_is_initialized};
  env->funcall (env, env->intern (env, "defalias"), 2, args_is_initialized);

  emacs_value symbol_open_query = env->intern (env, "sweep-open-query");
  emacs_value func_open_query =
    env->make_function(env,
                       4, 4,
                       sweep_open_query,
                       "Query Prolog.\n\
ARG1 is a string denoting the context module for the query.\n\
ARG2 and ARG3 are strings designating the module and predicate name of the Prolog predicate to invoke, which must be of arity 2.\n\
ARG4 is any object that can be converted to a Prolog term, and will be passed as the first argument of the invoked predicate.\n\
The second argument of the predicate is left unbound and is assumed to treated by the invoked predicate as an output variable.\n\
Further instantiations of the output variable can be examined via `sweep-next-solution'.",
                       NULL);
  emacs_value args_open_query[] = {symbol_open_query, func_open_query};
  env->funcall (env, env->intern (env, "defalias"), 2, args_open_query);

  emacs_value symbol_next_solution = env->intern (env, "sweep-next-solution");
  emacs_value func_next_solution =
    env->make_function(env,
                       0, 0,
                       sweep_next_solution,
                       "Return the next solution from Prolog, or nil if there are none.\n\
See also `sweep-open-query'.",
                       NULL);
  emacs_value args_next_solution[] = {symbol_next_solution, func_next_solution};
  env->funcall (env, env->intern (env, "defalias"), 2, args_next_solution);

  emacs_value symbol_cut_query = env->intern (env, "sweep-cut-query");
  emacs_value func_cut_query =
    env->make_function(env,
                       0, 0,
                       sweep_cut_query,
                       "Finalize the current Prolog query.\n\
This function retains the current instantiation of the query variables.",
                       NULL);
  emacs_value args_cut_query[] = {symbol_cut_query, func_cut_query};
  env->funcall (env, env->intern (env, "defalias"), 2, args_cut_query);

  emacs_value symbol_close_query = env->intern (env, "sweep-close-query");
  emacs_value func_close_query =
    env->make_function(env,
                       0, 0,
                       sweep_close_query,
                       "Finalize the current Prolog query.\n\
This function drops the current instantiation of the query variables.",
                       NULL);
  emacs_value args_close_query[] = {symbol_close_query, func_close_query};
  env->funcall (env, env->intern (env, "defalias"), 2, args_close_query);


  emacs_value symbol_cleanup = env->intern (env, "sweep-cleanup");
  emacs_value func_cleanup = env->make_function (env, 0, 0, sweep_cleanup, "Cleanup Prolog.", NULL);
  emacs_value args_cleanup[] = {symbol_cleanup, func_cleanup};
  env->funcall (env, env->intern (env, "defalias"), 2, args_cleanup);

  provide(env, "sweep-module");

  return 0;
}
