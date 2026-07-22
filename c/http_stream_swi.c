/* A real SWI-Prolog IOSTREAM for writing an HTTP response directly to a
 * connection's socket. See adr/0007: response writing is a genuine
 * Snew/IOFUNCTIONS stream, not a buffer assembled in Prolog and handed
 * to uv_write in one shot.
 *
 * Rather than duplicating uv_swi.c's private handle-blob layout here,
 * Swrite calls back into Prolog's own uv_swi:uv_write/3 (the same 1:1
 * predicate ordinary Prolog code would call) via PL_call -- legal and
 * cheap because Swrite only ever runs on the worker thread that already
 * owns a Prolog engine (the same thread that will later drive uv_run
 * for this connection), matching adr/0005's single-thread-owns-its-
 * connections rule.
 */

#include <SWI-Prolog.h>
#include <SWI-Stream.h>
#include <stdlib.h>
#include <string.h>

typedef struct
{ record_t tcp_handle;
} resp_ctx_t;

static ssize_t
resp_write(void *handle, char *buf, size_t bufsize)
{ resp_ctx_t *ctx = handle;
  fid_t fid = PL_open_foreign_frame();
  term_t tcp    = PL_new_term_ref();
  term_t bytes  = PL_new_term_ref();
  term_t done   = PL_new_term_ref();
  term_t av     = PL_new_term_refs(3);
  static predicate_t pred = 0;
  ssize_t result = -1;

  if ( !pred )
    pred = PL_predicate("uv_write", 3, "uv_swi");

  PL_recorded(ctx->tcp_handle, tcp);
  (void)PL_put_chars(bytes, PL_STRING|REP_ISO_LATIN_1, bufsize, buf);
  /* done = http_stream:ignore_write_result -- must be a real M:G compound,
   * not an atom containing a colon, or uv_dispatch's strip_module/3 won't
   * find the module and the later call_closure() for this write's
   * completion will raise existence_error. */
  { term_t mod  = PL_new_term_ref();
    term_t goal = PL_new_term_ref();
    functor_t colon = PL_new_functor(PL_new_atom(":"), 2);
    (void)PL_put_atom_chars(mod, "http_stream");
    (void)PL_put_atom_chars(goal, "ignore_write_result");
    (void)PL_cons_functor(done, colon, mod, goal);
  }

  (void)PL_put_term(av+0, tcp);
  (void)PL_put_term(av+1, bytes);
  (void)PL_put_term(av+2, done);

  { qid_t qid = PL_open_query(NULL, PL_Q_CATCH_EXCEPTION, pred, av);
    if ( PL_next_solution(qid) )
      result = (ssize_t)bufsize;
    else
    { term_t ex = PL_exception(qid);
      if ( ex )
      { Sfprintf(Suser_error, "http_stream: uv_write failed: ");
        PL_write_term(Suser_error, ex, 1200, PL_WRT_QUOTED);
        Sfprintf(Suser_error, "\n");
      }
    }
    PL_close_query(qid);
  }

  PL_discard_foreign_frame(fid);
  return result;
}

static int
resp_close(void *handle)
{ resp_ctx_t *ctx = handle;
  PL_erase(ctx->tcp_handle);
  free(ctx);
  return 0;
}

static IOFUNCTIONS resp_functions =
{ .read    = NULL,
  .write   = resp_write,
  .seek    = NULL,
  .close   = resp_close,
  .control = NULL,
  .seek64  = NULL
};

/* uv_response_stream(+TcpHandle, -Stream) is det.
 *
 * Stream is a real output IOSTREAM: write/1, format/2, nl/1 etc. all
 * work on it directly. Closing Stream (close/1) only releases the
 * stream's own bookkeeping -- it does NOT uv_close the connection,
 * so callers control the connection's lifetime independently (e.g.
 * to decide keep-alive vs. close after the response is flushed).
 */
static foreign_t
pl_uv_response_stream(term_t tcp_t, term_t stream_t)
{ resp_ctx_t *ctx = malloc(sizeof(*ctx));
  IOSTREAM *s;

  if ( !ctx )
    return PL_resource_error("memory");
  ctx->tcp_handle = PL_record(tcp_t);

  s = Snew(ctx, SIO_OUTPUT|SIO_FBUF|SIO_RECORDPOS, &resp_functions);
  if ( !s )
  { PL_erase(ctx->tcp_handle);
    free(ctx);
    return PL_resource_error("memory");
  }
  s->encoding = ENC_UTF8;

  return PL_unify_stream(stream_t, s);
}

install_t
install_http_stream_swi(void)
{ PL_register_foreign("uv_response_stream", 2, pl_uv_response_stream, 0);
}
