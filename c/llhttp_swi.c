/* 1:1 SWI-Prolog <-> llhttp bindings. See adr/0002 and adr/0003.
 *
 * Every exported predicate maps to one llhttp call. Callbacks are ordinary
 * Prolog closures (atom, Module:Name, or a partially-applied compound)
 * recorded via PL_record() so they survive across the C boundary, and
 * invoked synchronously through uv_dispatch:uv_invoke/2 -- the exact same
 * trampoline c/uv_swi.c uses, copied verbatim below rather than shared via
 * a header, since it is tiny and this keeps llhttp_swi.c self-contained.
 *
 * Whoever REGISTERS a closure (llhttp_on_url/2 etc.) must module-qualify
 * it (e.g. worker:on_body), because uv_invoke/2 does
 * strip_module(Closure, M, Plain), ..., call(M:Goal) -- an unqualified
 * atom/compound resolves in whatever module happens to be current when
 * the callback later fires from inside llhttp_execute/3, not the module
 * that registered it. See llhttp_swi.pl's module doc for the same note.
 *
 * Only ever call llhttp_pause/1 between llhttp_execute/3 calls, never
 * from inside a registered callback -- llhttp.h says so explicitly.
 * Because a registered Prolog closure runs synchronously underneath
 * llhttp_execute() here, the callback trampolines below always return 0
 * (continue) to llhttp; adr/0008's pause/resume valve is driven by the
 * worker calling llhttp_pause/1 itself once llhttp_execute/3 returns,
 * based on how far behind its own consumer has fallen -- not by a
 * callback's return value.
 */

#include <SWI-Prolog.h>
#include <SWI-Stream.h>
#include "llhttp.h"
#include <string.h>
#include <stdlib.h>
#include <ctype.h>

typedef struct
{ llhttp_t          parser;
  llhttp_settings_t settings;
  record_t on_url;
  record_t on_header_field;
  record_t on_header_value;
  record_t on_headers_complete;
  record_t on_body;
  record_t on_message_complete;
} llhttp_swi_t;

		 /*******************************
		 *      BLOB TYPE (parser)     *
		 *******************************/

static int
release_llhttp_parser(atom_t a)
{ llhttp_swi_t **pp = PL_blob_data(a, NULL, NULL);
  llhttp_swi_t *p = *pp;
  if ( p )
  { if ( p->on_url )              PL_erase(p->on_url);
    if ( p->on_header_field )     PL_erase(p->on_header_field);
    if ( p->on_header_value )     PL_erase(p->on_header_value);
    if ( p->on_headers_complete ) PL_erase(p->on_headers_complete);
    if ( p->on_body )             PL_erase(p->on_body);
    if ( p->on_message_complete ) PL_erase(p->on_message_complete);
    free(p);
  }
  return TRUE;
}

static int
write_llhttp_parser(IOSTREAM *s, atom_t a, int flags)
{ llhttp_swi_t **pp = PL_blob_data(a, NULL, NULL);
  llhttp_swi_t *p = *pp;
  (void)flags;
  Sfprintf(s, "<llhttp_parser>(%p)", p);
  return TRUE;
}

static PL_blob_t llhttp_parser_blob =
{ .magic   = PL_BLOB_MAGIC,
  .flags   = PL_BLOB_UNIQUE,
  .name    = "llhttp_parser",
  .release = release_llhttp_parser,
  .compare = NULL,
  .write   = write_llhttp_parser,
  .acquire = NULL,
  .save    = NULL,
  .load    = NULL
};

static int
unify_parser(term_t t, llhttp_swi_t *p)
{ return PL_unify_blob(t, &p, sizeof(p), &llhttp_parser_blob);
}

static int
get_parser(term_t t, llhttp_swi_t **p)
{ void *data;
  size_t len;
  PL_blob_t *type;

  if ( !PL_get_blob(t, &data, &len, &type) || type != &llhttp_parser_blob )
    return PL_type_error("llhttp_parser", t);
  *p = *(llhttp_swi_t**)data;
  return TRUE;
}

		 /*******************************
		 *   CALLING BACK INTO PROLOG   *
		 *******************************/

static void
report_uncaught(qid_t qid)
{ term_t ex = PL_exception(qid);
  if ( ex )
  { Sfprintf(Suser_error, "llhttp_swi: exception in callback: ");
    PL_write_term(Suser_error, ex, 1200, PL_WRT_QUOTED);
    Sfprintf(Suser_error, "\n");
  }
}

/* invoke Closure with the given extra args appended, via
 * uv_dispatch:uv_invoke/2 -- copied verbatim from c/uv_swi.c so this file
 * stays self-contained (see the top-of-file comment). Failures/exceptions
 * are reported and swallowed -- a misbehaving handler must not take down
 * the parser or the worker's event loop.
 */
static void
call_closure(record_t closure_rec, term_t *args, int nargs)
{ fid_t fid = PL_open_foreign_frame();
  term_t closure = PL_new_term_ref();
  term_t list    = PL_new_term_ref();
  term_t av      = PL_new_term_refs(2);
  static predicate_t pred = 0;
  int i;

  if ( !pred )
    pred = PL_predicate("uv_invoke", 2, "uv_dispatch");

  PL_recorded(closure_rec, closure);
  PL_put_nil(list);
  for(i = nargs-1; i >= 0; i--)
    (void)PL_cons_list(list, args[i], list);

  (void)PL_put_term(av+0, closure);
  (void)PL_put_term(av+1, list);

  { qid_t qid = PL_open_query(NULL, PL_Q_CATCH_EXCEPTION, pred, av);
    if ( !PL_next_solution(qid) )
      report_uncaught(qid);
    PL_close_query(qid);
  }

  PL_discard_foreign_frame(fid);
}

		 /*******************************
		 *        LLHTTP CALLBACKS      *
		 *******************************/

static int
on_url_cb(llhttp_t *parser, const char *at, size_t length)
{ llhttp_swi_t *p = parser->data;
  if ( p && p->on_url )
  { fid_t fid = PL_open_foreign_frame();
    term_t arg = PL_new_term_ref();
    (void)PL_put_chars(arg, PL_STRING|REP_ISO_LATIN_1, length, at);
    call_closure(p->on_url, &arg, 1);
    PL_discard_foreign_frame(fid);
  }
  return 0;
}

static int
on_header_field_cb(llhttp_t *parser, const char *at, size_t length)
{ llhttp_swi_t *p = parser->data;
  if ( p && p->on_header_field )
  { fid_t fid = PL_open_foreign_frame();
    term_t arg = PL_new_term_ref();
    (void)PL_put_chars(arg, PL_STRING|REP_ISO_LATIN_1, length, at);
    call_closure(p->on_header_field, &arg, 1);
    PL_discard_foreign_frame(fid);
  }
  return 0;
}

static int
on_header_value_cb(llhttp_t *parser, const char *at, size_t length)
{ llhttp_swi_t *p = parser->data;
  if ( p && p->on_header_value )
  { fid_t fid = PL_open_foreign_frame();
    term_t arg = PL_new_term_ref();
    (void)PL_put_chars(arg, PL_STRING|REP_ISO_LATIN_1, length, at);
    call_closure(p->on_header_value, &arg, 1);
    PL_discard_foreign_frame(fid);
  }
  return 0;
}

static int
on_body_cb(llhttp_t *parser, const char *at, size_t length)
{ llhttp_swi_t *p = parser->data;
  if ( p && p->on_body )
  { fid_t fid = PL_open_foreign_frame();
    term_t arg = PL_new_term_ref();
    (void)PL_put_chars(arg, PL_STRING|REP_ISO_LATIN_1, length, at);
    call_closure(p->on_body, &arg, 1);
    PL_discard_foreign_frame(fid);
  }
  return 0;
}

static int
on_headers_complete_cb(llhttp_t *parser)
{ llhttp_swi_t *p = parser->data;
  if ( p && p->on_headers_complete )
  { fid_t fid = PL_open_foreign_frame();
    call_closure(p->on_headers_complete, NULL, 0);
    PL_discard_foreign_frame(fid);
  }
  return 0;
}

static int
on_message_complete_cb(llhttp_t *parser)
{ llhttp_swi_t *p = parser->data;
  if ( p && p->on_message_complete )
  { fid_t fid = PL_open_foreign_frame();
    call_closure(p->on_message_complete, NULL, 0);
    PL_discard_foreign_frame(fid);
  }
  return 0;
}

		 /*******************************
		 *       FOREIGN PREDICATES     *
		 *******************************/

static foreign_t
pl_llhttp_parser_new(term_t parser_t)
{ llhttp_swi_t *p = calloc(1, sizeof(*p));
  if ( !p ) return PL_resource_error("memory");

  llhttp_settings_init(&p->settings);
  p->settings.on_url              = on_url_cb;
  p->settings.on_header_field     = on_header_field_cb;
  p->settings.on_header_value     = on_header_value_cb;
  p->settings.on_headers_complete = on_headers_complete_cb;
  p->settings.on_body             = on_body_cb;
  p->settings.on_message_complete = on_message_complete_cb;

  /* HTTP_REQUEST only -- this framework is a server, never a client, so
   * it only ever needs to parse requests (see adr/0003). */
  llhttp_init(&p->parser, HTTP_REQUEST, &p->settings);
  p->parser.data = p;

  return unify_parser(parser_t, p);
}

static foreign_t
pl_llhttp_on_url(term_t parser_t, term_t closure_t)
{ llhttp_swi_t *p;
  if ( !get_parser(parser_t, &p) ) return FALSE;
  p->on_url = PL_record(closure_t);
  return TRUE;
}

static foreign_t
pl_llhttp_on_header_field(term_t parser_t, term_t closure_t)
{ llhttp_swi_t *p;
  if ( !get_parser(parser_t, &p) ) return FALSE;
  p->on_header_field = PL_record(closure_t);
  return TRUE;
}

static foreign_t
pl_llhttp_on_header_value(term_t parser_t, term_t closure_t)
{ llhttp_swi_t *p;
  if ( !get_parser(parser_t, &p) ) return FALSE;
  p->on_header_value = PL_record(closure_t);
  return TRUE;
}

static foreign_t
pl_llhttp_on_headers_complete(term_t parser_t, term_t closure_t)
{ llhttp_swi_t *p;
  if ( !get_parser(parser_t, &p) ) return FALSE;
  p->on_headers_complete = PL_record(closure_t);
  return TRUE;
}

static foreign_t
pl_llhttp_on_body(term_t parser_t, term_t closure_t)
{ llhttp_swi_t *p;
  if ( !get_parser(parser_t, &p) ) return FALSE;
  p->on_body = PL_record(closure_t);
  return TRUE;
}

static foreign_t
pl_llhttp_on_message_complete(term_t parser_t, term_t closure_t)
{ llhttp_swi_t *p;
  if ( !get_parser(parser_t, &p) ) return FALSE;
  p->on_message_complete = PL_record(closure_t);
  return TRUE;
}

/* llhttp_errno_name() returns strings like "HPE_OK", "HPE_PAUSED",
 * "HPE_INVALID_METHOD" -- strip the HPE_ prefix and lowercase, giving
 * Prolog callers atoms like ok, paused, invalid_method. Written into a
 * caller-supplied stack buffer, not a static one: llhttp_execute/3 can be
 * called concurrently from independent worker threads (adr/0005), each
 * with its own parser, and a shared static buffer would let one worker's
 * result string get clobbered by another's. */
static void
errno_atom_name(llhttp_errno_t err, char *buf, size_t bufsz)
{ const char *name = llhttp_errno_name(err);
  size_t i = 0;

  if ( strncmp(name, "HPE_", 4) == 0 )
    name += 4;
  for ( ; name[i] && i < bufsz-1; i++ )
    buf[i] = (char)tolower((unsigned char)name[i]);
  buf[i] = '\0';
}

static foreign_t
pl_llhttp_execute(term_t parser_t, term_t data_t, term_t result_t)
{ llhttp_swi_t *p;
  char *s;
  size_t len;
  llhttp_errno_t err;
  char errbuf[32];

  if ( !get_parser(parser_t, &p) ) return FALSE;
  if ( !PL_get_nchars(data_t, &len, &s, CVT_ATOM|CVT_STRING|CVT_LIST|REP_ISO_LATIN_1) )
    return PL_type_error("text", data_t);

  err = llhttp_execute(&p->parser, s, len);
  errno_atom_name(err, errbuf, sizeof(errbuf));

  return PL_unify_atom_chars(result_t, errbuf);
}

static foreign_t
pl_llhttp_pause(term_t parser_t)
{ llhttp_swi_t *p;
  if ( !get_parser(parser_t, &p) ) return FALSE;
  llhttp_pause(&p->parser);
  return TRUE;
}

static foreign_t
pl_llhttp_resume(term_t parser_t)
{ llhttp_swi_t *p;
  if ( !get_parser(parser_t, &p) ) return FALSE;
  llhttp_resume(&p->parser);
  return TRUE;
}

static foreign_t
pl_llhttp_method_name(term_t parser_t, term_t method_t)
{ llhttp_swi_t *p;
  uint8_t method;
  const char *name;
  if ( !get_parser(parser_t, &p) ) return FALSE;
  method = llhttp_get_method(&p->parser);
  name = llhttp_method_name((llhttp_method_t)method);
  return PL_unify_atom_chars(method_t, name);
}

install_t
install_llhttp_swi(void)
{ PL_register_foreign("llhttp_parser_new",          1, pl_llhttp_parser_new, 0);
  PL_register_foreign("llhttp_on_url",              2, pl_llhttp_on_url, 0);
  PL_register_foreign("llhttp_on_header_field",     2, pl_llhttp_on_header_field, 0);
  PL_register_foreign("llhttp_on_header_value",     2, pl_llhttp_on_header_value, 0);
  PL_register_foreign("llhttp_on_headers_complete", 2, pl_llhttp_on_headers_complete, 0);
  PL_register_foreign("llhttp_on_body",             2, pl_llhttp_on_body, 0);
  PL_register_foreign("llhttp_on_message_complete", 2, pl_llhttp_on_message_complete, 0);
  PL_register_foreign("llhttp_execute",             3, pl_llhttp_execute, 0);
  PL_register_foreign("llhttp_pause",               1, pl_llhttp_pause, 0);
  PL_register_foreign("llhttp_resume",              1, pl_llhttp_resume, 0);
  PL_register_foreign("llhttp_method_name",         2, pl_llhttp_method_name, 0);
}
