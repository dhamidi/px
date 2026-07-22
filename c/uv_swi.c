/* 1:1 SWI-Prolog <-> libuv bindings. See adr/0002 and adr/0004.
 *
 * Every exported predicate maps to one libuv call. Callbacks are ordinary
 * Prolog closures (atom, Module:Name, or a partially-applied compound)
 * recorded via PL_record() so they survive across the async C boundary,
 * and invoked synchronously through uv_dispatch:uv_invoke/2 -- see adr/0005:
 * this is only safe because the thread calling uv_run/2 is itself a real
 * Prolog thread with its own attached engine (a "worker"), so callbacks
 * firing during that call can PL_call directly, same-thread.
 */

#include <SWI-Prolog.h>
#include <SWI-Stream.h>
#include <uv.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>

typedef enum { UV_SWI_LOOP, UV_SWI_TCP, UV_SWI_TIMER, UV_SWI_ASYNC } uv_swi_kind_t;

typedef struct
{ uv_swi_kind_t kind;
  union
  { uv_loop_t  loop;
    uv_tcp_t   tcp;
    uv_timer_t timer;
    uv_async_t async;
  } h;
} uv_swi_handle_t;

typedef struct
{ record_t on_connection;
  record_t on_read;
  record_t on_close;
  record_t on_timeout;  /* only used when kind == UV_SWI_TIMER */
  record_t on_async;    /* only used when kind == UV_SWI_ASYNC, see adr/0005 */
  record_t self_ref;    /* pins the handle's blob atom alive between
                          * uv_close() and on_close_cb -- see pl_uv_close().
                          * Without this, once Prolog code drops its last
                          * reference to the handle term (which it normally
                          * does right after calling uv_close), the blob
                          * atom can be GC'd and its release callback will
                          * free() this struct's owning uv_swi_handle_t
                          * while libuv still holds a live pointer to it,
                          * a use-after-free that crashes on a *later*,
                          * unrelated libuv callback once the loop
                          * revisits the corrupted memory. */
} conn_ctx_t;

static void
release_ctx(uv_handle_t *h)
{ conn_ctx_t *ctx = h->data;
  if ( !ctx )
    return;
  if ( ctx->on_connection ) PL_erase(ctx->on_connection);
  if ( ctx->on_read )       PL_erase(ctx->on_read);
  if ( ctx->on_close )      PL_erase(ctx->on_close);
  if ( ctx->on_timeout )    PL_erase(ctx->on_timeout);
  if ( ctx->on_async )      PL_erase(ctx->on_async);
  if ( ctx->self_ref )      PL_erase(ctx->self_ref);
  free(ctx);
  h->data = NULL;
}

		 /*******************************
		 *      BLOB TYPE (handles)    *
		 *******************************/

static int
release_uv_swi_handle(atom_t a)
{ uv_swi_handle_t **pp = PL_blob_data(a, NULL, NULL);
  uv_swi_handle_t *p = *pp;
  if ( p )
  { if ( p->kind != UV_SWI_LOOP )
      release_ctx((uv_handle_t*)&p->h);
    free(p);
  }
  return TRUE;
}

static int
write_uv_swi_handle(IOSTREAM *s, atom_t a, int flags)
{ uv_swi_handle_t **pp = PL_blob_data(a, NULL, NULL);
  uv_swi_handle_t *p = *pp;
  const char *kind = "handle";
  (void)flags;
  if ( p )
  { switch(p->kind)
    { case UV_SWI_LOOP:  kind = "loop"; break;
      case UV_SWI_TCP:   kind = "tcp"; break;
      case UV_SWI_TIMER: kind = "timer"; break;
      case UV_SWI_ASYNC: kind = "async"; break;
    }
  }
  Sfprintf(s, "<uv_%s>(%p)", kind, p);
  return TRUE;
}

static PL_blob_t uv_swi_blob =
{ .magic   = PL_BLOB_MAGIC,
  .flags   = PL_BLOB_UNIQUE,
  .name    = "uv_handle",
  .release = release_uv_swi_handle,
  .compare = NULL,
  .write   = write_uv_swi_handle,
  .acquire = NULL,
  .save    = NULL,
  .load    = NULL
};

static int
unify_handle(term_t t, uv_swi_handle_t *p)
{ return PL_unify_blob(t, &p, sizeof(p), &uv_swi_blob);
}

static int
get_handle(term_t t, uv_swi_handle_t **p)
{ void *data;
  size_t len;
  PL_blob_t *type;

  if ( !PL_get_blob(t, &data, &len, &type) || type != &uv_swi_blob )
    return PL_type_error("uv_handle", t);
  *p = *(uv_swi_handle_t**)data;
  return TRUE;
}

static uv_loop_t *
get_loop(term_t t)
{ uv_swi_handle_t *p;
  if ( !get_handle(t, &p) || p->kind != UV_SWI_LOOP )
  { PL_type_error("uv_loop", t);
    return NULL;
  }
  return &p->h.loop;
}

static uv_tcp_t *
get_tcp(term_t t)
{ uv_swi_handle_t *p;
  if ( !get_handle(t, &p) || p->kind != UV_SWI_TCP )
  { PL_type_error("uv_tcp", t);
    return NULL;
  }
  return &p->h.tcp;
}

static uv_timer_t *
get_timer(term_t t)
{ uv_swi_handle_t *p;
  if ( !get_handle(t, &p) || p->kind != UV_SWI_TIMER )
  { PL_type_error("uv_timer", t);
    return NULL;
  }
  return &p->h.timer;
}

static uv_async_t *
get_async(term_t t)
{ uv_swi_handle_t *p;
  if ( !get_handle(t, &p) || p->kind != UV_SWI_ASYNC )
  { PL_type_error("uv_async", t);
    return NULL;
  }
  return &p->h.async;
}

		 /*******************************
		 *   CALLING BACK INTO PROLOG   *
		 *******************************/

static void
report_uncaught(qid_t qid)
{ term_t ex = PL_exception(qid);
  if ( ex )
  { Sfprintf(Suser_error, "uv_swi: exception in callback: ");
    PL_write_term(Suser_error, ex, 1200, PL_WRT_QUOTED);
    Sfprintf(Suser_error, "\n");
  }
}

/* invoke Closure with the given extra args appended, via
 * uv_dispatch:uv_invoke/2 (defined in prolog/worker.pl), which does
 * Closure =.. L, append(L, Args, L2), Goal =.. L2, call(Goal).
 * Failures/exceptions are reported and swallowed -- a misbehaving handler
 * must not take down the worker's event loop.
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
		 *        LIBUV CALLBACKS       *
		 *******************************/

static void
alloc_cb(uv_handle_t *h, size_t suggested, uv_buf_t *buf)
{ (void)h;
  buf->base = malloc(suggested);
  buf->len  = buf->base ? suggested : 0;
}

static void
on_read_cb(uv_stream_t *stream, ssize_t nread, const uv_buf_t *buf)
{ conn_ctx_t *ctx = stream->data;
  term_t args[2];
  fid_t fid;

  if ( nread > 0 && ctx && ctx->on_read )
  { fid = PL_open_foreign_frame();
    args[0] = PL_new_term_ref();
    unify_handle(args[0], (uv_swi_handle_t*)((char*)stream -
                 offsetof(uv_swi_handle_t, h)));
    args[1] = PL_new_term_ref();
    (void)PL_put_chars(args[1], PL_STRING|REP_ISO_LATIN_1, nread, buf->base);
    call_closure(ctx->on_read, args, 2);
    PL_discard_foreign_frame(fid);
  }
  else if ( nread < 0 && ctx && ctx->on_read )
  { fid = PL_open_foreign_frame();
    args[0] = PL_new_term_ref();
    unify_handle(args[0], (uv_swi_handle_t*)((char*)stream -
                 offsetof(uv_swi_handle_t, h)));
    args[1] = PL_new_term_ref();
    PL_put_atom_chars(args[1], "end_of_file");
    call_closure(ctx->on_read, args, 2);
    PL_discard_foreign_frame(fid);
  }

  if ( buf->base )
    free(buf->base);
}

static void
on_connection_cb(uv_stream_t *server, int status)
{ conn_ctx_t *ctx = server->data;
  term_t args[2];
  fid_t fid;
  (void)status;

  if ( !ctx || !ctx->on_connection )
    return;

  fid = PL_open_foreign_frame();
  args[0] = PL_new_term_ref();
  unify_handle(args[0], (uv_swi_handle_t*)((char*)server -
               offsetof(uv_swi_handle_t, h)));
  args[1] = PL_new_term_ref();
  (void)PL_put_integer(args[1], status);
  call_closure(ctx->on_connection, args, 2);
  PL_discard_foreign_frame(fid);
}

typedef struct
{ record_t closure;
  char    *data;
} write_req_t;

static void
on_write_cb(uv_write_t *req, int status)
{ write_req_t *wr = req->data;
  term_t args[1];
  fid_t fid;

  if ( wr->closure )
  { fid = PL_open_foreign_frame();
    args[0] = PL_new_term_ref();
    (void)PL_put_integer(args[0], status);
    call_closure(wr->closure, args, 1);
    PL_erase(wr->closure);
    PL_discard_foreign_frame(fid);
  }
  free(wr->data);
  free(wr);
  free(req);
}

static void
on_timer_cb(uv_timer_t *handle)
{ conn_ctx_t *ctx = handle->data;
  if ( !ctx || !ctx->on_timeout )
    return;
  { fid_t fid = PL_open_foreign_frame();
    call_closure(ctx->on_timeout, NULL, 0);
    PL_discard_foreign_frame(fid);
  }
}

/* Fires on the OWNING loop's thread whenever uv_async_send/1 is called on
 * this handle from any thread -- see adr/0005/0006: this is the one libuv
 * call that's safe cross-thread, and is exactly how bridge.pl wakes a
 * worker's own uv_run to let IT call uv_stop on itself, same-thread. */
static void
on_async_cb(uv_async_t *handle)
{ conn_ctx_t *ctx = handle->data;
  if ( !ctx || !ctx->on_async )
    return;
  { fid_t fid = PL_open_foreign_frame();
    call_closure(ctx->on_async, NULL, 0);
    PL_discard_foreign_frame(fid);
  }
}

/* Only release the connection context here, not the outer uv_swi_handle_t
 * struct itself -- that struct is owned by the Prolog blob (unify_handle)
 * and freed exactly once, by release_uv_swi_handle, when the blob's atom
 * is garbage collected. Freeing it here too would double-free it the
 * moment the atom is later reclaimed. */
static void
on_close_cb(uv_handle_t *h)
{ conn_ctx_t *ctx = h->data;
  if ( ctx && ctx->on_close )
  { fid_t fid = PL_open_foreign_frame();
    call_closure(ctx->on_close, NULL, 0);
    PL_discard_foreign_frame(fid);
  }
  release_ctx(h);
}

		 /*******************************
		 *       FS REQUEST CONTEXT     *
		 *******************************/

/* uv_fs_t requests (adr/0004) are one-shot, not a handle the caller holds
 * onto and reuses like a uv_tcp_t or uv_timer_t -- so unlike UV_SWI_TCP /
 * UV_SWI_TIMER they are NOT wrapped in the uv_swi_handle_t blob. Each call
 * plain-mallocs a uv_fs_t plus a small context struct carrying the
 * recorded closure (and, for reads, the buffer), both freed from the
 * completion callback after uv_fs_req_cleanup() -- required by libuv to
 * release internal buffers (e.g. a resolved realpath) -- has run. This is
 * the one place in this file that frees on completion rather than via the
 * blob release callback, precisely because there is no blob here to do it
 * on GC; see on_close_cb above for why a *handle*, once wrapped in a blob,
 * must never be freed from a completion callback. */

typedef struct
{ record_t closure;
} fs_ctx_t;              /* uv_fs_open, uv_fs_close */

typedef struct
{ record_t closure;
  char    *buf;
} fs_read_ctx_t;          /* uv_fs_read */

/* OnOpen is invoked with 1 extra arg: the raw req->result (libuv
 * convention -- >=0 is the fd, <0 is a negative errno). Interpreting that
 * is left to the Prolog layer, per adr/0002's "no policy in C" rule. */
static void
on_fs_open_cb(uv_fs_t *req)
{ fs_ctx_t *ctx = req->data;
  fid_t fid = PL_open_foreign_frame();
  term_t arg = PL_new_term_ref();
  (void)PL_put_int64(arg, req->result);
  call_closure(ctx->closure, &arg, 1);
  PL_discard_foreign_frame(fid);
  PL_erase(ctx->closure);
  free(ctx);
  uv_fs_req_cleanup(req);
  free(req);
}

/* OnRead is invoked with 2 extra args: (Result, Data). Result is the raw
 * req->result (>=0 byte count, 0 at EOF, <0 negative errno); Data is a
 * Prolog string of exactly that many bytes (empty string when Result =< 0).
 * Passing Result separately -- rather than only a string, empty at EOF --
 * lets callers tell an error apart from EOF without ambiguity. This is the
 * contract the Prolog convenience layer built on top of uv_fs_read/5 will
 * rely on. */
static void
on_fs_read_cb(uv_fs_t *req)
{ fs_read_ctx_t *ctx = req->data;
  fid_t fid = PL_open_foreign_frame();
  term_t args[2];
  args[0] = PL_new_term_ref();
  (void)PL_put_int64(args[0], req->result);
  args[1] = PL_new_term_ref();
  (void)PL_put_chars(args[1], PL_STRING|REP_ISO_LATIN_1,
                      req->result > 0 ? (size_t)req->result : 0, ctx->buf);
  call_closure(ctx->closure, args, 2);
  PL_discard_foreign_frame(fid);
  PL_erase(ctx->closure);
  free(ctx->buf);
  free(ctx);
  uv_fs_req_cleanup(req);
  free(req);
}

/* OnClose is invoked with 1 extra arg: the raw req->result (0 on success,
 * <0 negative errno). */
static void
on_fs_close_cb(uv_fs_t *req)
{ fs_ctx_t *ctx = req->data;
  fid_t fid = PL_open_foreign_frame();
  term_t arg = PL_new_term_ref();
  (void)PL_put_int64(arg, req->result);
  call_closure(ctx->closure, &arg, 1);
  PL_discard_foreign_frame(fid);
  PL_erase(ctx->closure);
  free(ctx);
  uv_fs_req_cleanup(req);
  free(req);
}

		 /*******************************
		 *       FOREIGN PREDICATES     *
		 *******************************/

static foreign_t
pl_uv_loop_new(term_t loop)
{ uv_swi_handle_t *p = malloc(sizeof(*p));
  if ( !p ) return PL_resource_error("memory");
  p->kind = UV_SWI_LOOP;
  if ( uv_loop_init(&p->h.loop) )
  { free(p);
    return PL_permission_error("create", "uv_loop", loop);
  }
  return unify_handle(loop, p);
}

static foreign_t
pl_uv_tcp_init(term_t loop_t, term_t handle_t)
{ uv_loop_t *loop = get_loop(loop_t);
  uv_swi_handle_t *p;
  conn_ctx_t *ctx;
  if ( !loop ) return FALSE;

  p = malloc(sizeof(*p));
  if ( !p ) return PL_resource_error("memory");
  p->kind = UV_SWI_TCP;
  if ( uv_tcp_init(loop, &p->h.tcp) )
  { free(p);
    return PL_permission_error("create", "uv_tcp", handle_t);
  }
  ctx = calloc(1, sizeof(*ctx));
  if ( !ctx ) { free(p); return PL_resource_error("memory"); }
  p->h.tcp.data = ctx;
  if ( !unify_handle(handle_t, p) )
    return FALSE;
  /* Pin the handle's own blob atom alive from creation until release_ctx
   * erases this on confirmed close (see conn_ctx_t.self_ref and adr/0014).
   * Without this, a handle used only across async callbacks -- like a
   * listening socket, never referenced again by any Prolog goal once
   * uv_run starts blocking, or a client connection between one event and
   * the next -- has no live Prolog reference at all and can be atom-GC'd
   * while libuv still holds a live pointer to it: a use-after-free that
   * only shows up under real concurrency/GC pressure, not sequential
   * testing. adr/0014's original fix only pinned from uv_close onward;
   * this covers the whole lifetime. */
  ctx->self_ref = PL_record(handle_t);
  return TRUE;
}

/* Binds with SO_REUSEPORT so multiple independent workers (adr/0005) can
 * each own an fd for the same port and let the kernel load-balance
 * accepts across them. libuv creates its tcp socket lazily (not until
 * uv_tcp_bind/connect), too late to set SO_REUSEPORT before bind(2) takes
 * effect -- so the socket is created, configured, and bound by hand here,
 * then handed to libuv via uv_tcp_open, which skips libuv's own
 * socket()+bind() and just adopts the fd as-is. */
static foreign_t
pl_uv_tcp_bind_reuseport(term_t handle_t, term_t ip_t, term_t port_t)
{ uv_tcp_t *tcp = get_tcp(handle_t);
  char *ip;
  int port;
  struct sockaddr_in addr;
  int fd;
  int one = 1;

  if ( !tcp ) return FALSE;
  if ( !PL_get_atom_chars(ip_t, &ip) ) return PL_type_error("atom", ip_t);
  if ( !PL_get_integer(port_t, &port) ) return PL_type_error("integer", port_t);
  if ( uv_ip4_addr(ip, port, &addr) )
    return PL_domain_error("ip_address", ip_t);

  fd = socket(AF_INET, SOCK_STREAM, 0);
  if ( fd < 0 )
    return PL_permission_error("create", "socket", handle_t);
  if ( setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &one, sizeof(one)) ||
       setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one)) )
  { close(fd);
    return PL_permission_error("set_reuseport", "uv_tcp", handle_t);
  }
  if ( bind(fd, (struct sockaddr*)&addr, sizeof(addr)) )
  { close(fd);
    return PL_permission_error("bind", "uv_tcp", handle_t);
  }
  if ( uv_tcp_open(tcp, fd) )
  { close(fd);
    return PL_permission_error("adopt", "uv_tcp", handle_t);
  }
  return TRUE;
}

static foreign_t
pl_uv_listen(term_t handle_t, term_t backlog_t, term_t on_connection_t)
{ uv_tcp_t *tcp = get_tcp(handle_t);
  conn_ctx_t *ctx;
  int backlog;

  if ( !tcp ) return FALSE;
  if ( !PL_get_integer(backlog_t, &backlog) )
    return PL_type_error("integer", backlog_t);

  ctx = tcp->data;
  ctx->on_connection = PL_record(on_connection_t);

  if ( uv_listen((uv_stream_t*)tcp, backlog, on_connection_cb) )
    return PL_permission_error("listen", "uv_tcp", handle_t);
  return TRUE;
}

static foreign_t
pl_uv_accept(term_t server_t, term_t client_t)
{ uv_tcp_t *server = get_tcp(server_t);
  uv_tcp_t *client = get_tcp(client_t);
  if ( !server || !client ) return FALSE;
  if ( uv_accept((uv_stream_t*)server, (uv_stream_t*)client) )
    return PL_permission_error("accept", "uv_tcp", server_t);
  return TRUE;
}

static foreign_t
pl_uv_read_start(term_t handle_t, term_t on_read_t)
{ uv_tcp_t *tcp = get_tcp(handle_t);
  conn_ctx_t *ctx;
  if ( !tcp ) return FALSE;
  ctx = tcp->data;
  ctx->on_read = PL_record(on_read_t);
  if ( uv_read_start((uv_stream_t*)tcp, alloc_cb, on_read_cb) )
    return PL_permission_error("read", "uv_tcp", handle_t);
  return TRUE;
}

static foreign_t
pl_uv_read_stop(term_t handle_t)
{ uv_tcp_t *tcp = get_tcp(handle_t);
  if ( !tcp ) return FALSE;
  uv_read_stop((uv_stream_t*)tcp);
  return TRUE;
}

static foreign_t
pl_uv_write(term_t handle_t, term_t data_t, term_t on_write_t)
{ uv_tcp_t *tcp = get_tcp(handle_t);
  char *s;
  size_t len;
  uv_write_t *req;
  write_req_t *wr;
  uv_buf_t buf;

  if ( !tcp ) return FALSE;
  if ( !PL_get_nchars(data_t, &len, &s, CVT_ATOM|CVT_STRING|CVT_LIST|REP_ISO_LATIN_1) )
    return PL_type_error("text", data_t);

  req = malloc(sizeof(*req));
  wr  = malloc(sizeof(*wr));
  if ( !req || !wr )
  { free(req); free(wr);
    return PL_resource_error("memory");
  }
  wr->data = malloc(len);
  if ( !wr->data )
  { free(wr); free(req);
    return PL_resource_error("memory");
  }
  memcpy(wr->data, s, len);
  wr->closure = PL_record(on_write_t);
  req->data = wr;
  buf = uv_buf_init(wr->data, len);

  if ( uv_write(req, (uv_stream_t*)tcp, &buf, 1, on_write_cb) )
  { free(wr->data); free(wr); free(req);
    return PL_permission_error("write", "uv_tcp", handle_t);
  }
  return TRUE;
}

static foreign_t
pl_uv_close(term_t handle_t, term_t on_close_t)
{ uv_swi_handle_t *p;
  conn_ctx_t *ctx;
  if ( !get_handle(handle_t, &p) ) return FALSE;
  ctx = p->h.tcp.data;
  /* self_ref is already set (from creation -- see pl_uv_tcp_init et al.)
   * and erased by release_ctx once on_close_cb confirms the close is
   * done; don't re-record here, that would leak the original record. */
  if ( ctx )
    ctx->on_close = PL_record(on_close_t);
  uv_close((uv_handle_t*)&p->h, on_close_cb);
  return TRUE;
}

		 /*******************************
		 *            TIMERS            *
		 *******************************/

static foreign_t
pl_uv_timer_init(term_t loop_t, term_t handle_t)
{ uv_loop_t *loop = get_loop(loop_t);
  uv_swi_handle_t *p;
  conn_ctx_t *ctx;
  if ( !loop ) return FALSE;

  p = malloc(sizeof(*p));
  if ( !p ) return PL_resource_error("memory");
  p->kind = UV_SWI_TIMER;
  if ( uv_timer_init(loop, &p->h.timer) )
  { free(p);
    return PL_permission_error("create", "uv_timer", handle_t);
  }
  ctx = calloc(1, sizeof(*ctx));
  if ( !ctx ) { free(p); return PL_resource_error("memory"); }
  p->h.timer.data = ctx;
  if ( !unify_handle(handle_t, p) )
    return FALSE;
  /* See pl_uv_tcp_init's comment on self_ref: pin from creation to close. */
  ctx->self_ref = PL_record(handle_t);
  return TRUE;
}

/* OnTimeout is called with zero extra args each time the timer fires --
 * same convention as on_close_cb's zero-arg call_closure(..., NULL, 0). */
static foreign_t
pl_uv_timer_start(term_t handle_t, term_t timeout_t, term_t repeat_t, term_t on_timeout_t)
{ uv_timer_t *timer = get_timer(handle_t);
  conn_ctx_t *ctx;
  int64_t timeout, repeat;

  if ( !timer ) return FALSE;
  if ( !PL_get_int64(timeout_t, &timeout) )
    return PL_type_error("integer", timeout_t);
  if ( !PL_get_int64(repeat_t, &repeat) )
    return PL_type_error("integer", repeat_t);

  ctx = timer->data;
  ctx->on_timeout = PL_record(on_timeout_t);

  if ( uv_timer_start(timer, on_timer_cb, (uint64_t)timeout, (uint64_t)repeat) )
    return PL_permission_error("start", "uv_timer", handle_t);
  return TRUE;
}

static foreign_t
pl_uv_timer_stop(term_t handle_t)
{ uv_timer_t *timer = get_timer(handle_t);
  if ( !timer ) return FALSE;
  uv_timer_stop(timer);
  return TRUE;
}

/* uv_timer_close: no separate predicate -- the generic uv_close/2 above
 * already handles timers. get_handle() isn't kind-specific, and uv_close()
 * takes a uv_handle_t*, so uv_close(TimerHandle, OnClose) just works. */

		 /*******************************
		 *   ASYNC (cross-thread wake)  *
		 *******************************/

/* uv_async_t is libuv's one cross-thread-safe primitive (adr/0005): calling
 * uv_async_send/1 from any thread wakes the OWNING loop and runs OnAsync on
 * that loop's own thread. This is control-plane-only machinery for
 * prolog/bridge.pl's graceful-shutdown fan-out -- never a per-request data
 * path. The callback is fixed at init time (unlike uv_listen/uv_read_start,
 * where the handle is created first and the callback attached in a second
 * call) because that's libuv's own uv_async_init(loop, async, cb) shape. */
static foreign_t
pl_uv_async_init(term_t loop_t, term_t on_async_t, term_t handle_t)
{ uv_loop_t *loop = get_loop(loop_t);
  uv_swi_handle_t *p;
  conn_ctx_t *ctx;
  if ( !loop ) return FALSE;

  p = malloc(sizeof(*p));
  if ( !p ) return PL_resource_error("memory");
  p->kind = UV_SWI_ASYNC;
  if ( uv_async_init(loop, &p->h.async, on_async_cb) )
  { free(p);
    return PL_permission_error("create", "uv_async", handle_t);
  }
  ctx = calloc(1, sizeof(*ctx));
  if ( !ctx ) { free(p); return PL_resource_error("memory"); }
  ctx->on_async = PL_record(on_async_t);
  p->h.async.data = ctx;
  if ( !unify_handle(handle_t, p) )
    return FALSE;
  /* See pl_uv_tcp_init's comment on self_ref: pin from creation to close.
   * Especially critical here -- an async handle exists *solely* to be
   * reachable from other threads via uv_async_send/1, so it's never going
   * to have an ordinary Prolog-visible reference keeping it alive. */
  ctx->self_ref = PL_record(handle_t);
  return TRUE;
}

/* Safe to call from ANY thread, including one with no attached Prolog
 * engine at all -- this function itself makes no Prolog calls, it just
 * asks libuv to wake the owning loop. See adr/0005: in this project every
 * thread that calls it is in fact a worker with its own engine, but that
 * is a project-level convention, not something this C function enforces. */
static foreign_t
pl_uv_async_send(term_t handle_t)
{ uv_async_t *async = get_async(handle_t);
  if ( !async ) return FALSE;
  if ( uv_async_send(async) )
    return PL_permission_error("send", "uv_async", handle_t);
  return TRUE;
}

/* uv_async_close: no separate predicate -- same reasoning as timers above,
 * the generic uv_close/2 handles async handles too. */

		 /*******************************
		 *         FILESYSTEM           *
		 *******************************/

/* Flags/mode are passed through as plain integers from Prolog (e.g. 0 for
 * O_RDONLY, 0o644 for a mode) -- no symbolic flag-name mapping here, per
 * adr/0002's "no policy in C" rule; that belongs in a future Prolog
 * convenience layer, not this binding. */
static foreign_t
pl_uv_fs_open(term_t loop_t, term_t path_t, term_t flags_t, term_t mode_t, term_t on_open_t)
{ uv_loop_t *loop = get_loop(loop_t);
  char *path;
  size_t len;
  int flags, mode;
  uv_fs_t *req;
  fs_ctx_t *ctx;

  if ( !loop ) return FALSE;
  if ( !PL_get_nchars(path_t, &len, &path, CVT_ATOM|CVT_STRING|CVT_LIST|REP_ISO_LATIN_1) )
    return PL_type_error("text", path_t);
  if ( !PL_get_integer(flags_t, &flags) )
    return PL_type_error("integer", flags_t);
  if ( !PL_get_integer(mode_t, &mode) )
    return PL_type_error("integer", mode_t);

  req = malloc(sizeof(*req));
  ctx = malloc(sizeof(*ctx));
  if ( !req || !ctx )
  { free(req); free(ctx);
    return PL_resource_error("memory");
  }
  ctx->closure = PL_record(on_open_t);
  req->data = ctx;

  if ( uv_fs_open(loop, req, path, flags, mode, on_fs_open_cb) )
  { PL_erase(ctx->closure); free(ctx); free(req);
    return PL_permission_error("open", "uv_fs", path_t);
  }
  return TRUE;
}

static foreign_t
pl_uv_fs_read(term_t loop_t, term_t fd_t, term_t size_t_, term_t offset_t, term_t on_read_t)
{ uv_loop_t *loop = get_loop(loop_t);
  int fd;
  int64_t size, offset;
  uv_fs_t *req;
  fs_read_ctx_t *ctx;
  uv_buf_t buf;

  if ( !loop ) return FALSE;
  if ( !PL_get_integer(fd_t, &fd) )
    return PL_type_error("integer", fd_t);
  if ( !PL_get_int64(size_t_, &size) || size < 0 )
    return PL_type_error("nonneg_integer", size_t_);
  if ( !PL_get_int64(offset_t, &offset) )
    return PL_type_error("integer", offset_t);

  req = malloc(sizeof(*req));
  ctx = malloc(sizeof(*ctx));
  if ( !req || !ctx )
  { free(req); free(ctx);
    return PL_resource_error("memory");
  }
  ctx->closure = PL_record(on_read_t);
  ctx->buf = malloc(size > 0 ? (size_t)size : 1);
  if ( !ctx->buf )
  { PL_erase(ctx->closure); free(ctx); free(req);
    return PL_resource_error("memory");
  }
  req->data = ctx;
  buf = uv_buf_init(ctx->buf, (unsigned int)size);

  if ( uv_fs_read(loop, req, fd, &buf, 1, offset, on_fs_read_cb) )
  { PL_erase(ctx->closure); free(ctx->buf); free(ctx); free(req);
    return PL_permission_error("read", "uv_fs", fd_t);
  }
  return TRUE;
}

static foreign_t
pl_uv_fs_close(term_t loop_t, term_t fd_t, term_t on_close_t)
{ uv_loop_t *loop = get_loop(loop_t);
  int fd;
  uv_fs_t *req;
  fs_ctx_t *ctx;

  if ( !loop ) return FALSE;
  if ( !PL_get_integer(fd_t, &fd) )
    return PL_type_error("integer", fd_t);

  req = malloc(sizeof(*req));
  ctx = malloc(sizeof(*ctx));
  if ( !req || !ctx )
  { free(req); free(ctx);
    return PL_resource_error("memory");
  }
  ctx->closure = PL_record(on_close_t);
  req->data = ctx;

  if ( uv_fs_close(loop, req, fd, on_fs_close_cb) )
  { PL_erase(ctx->closure); free(ctx); free(req);
    return PL_permission_error("close", "uv_fs", fd_t);
  }
  return TRUE;
}

static foreign_t
pl_uv_run(term_t loop_t, term_t mode_t)
{ uv_loop_t *loop = get_loop(loop_t);
  char *mode;
  uv_run_mode m = UV_RUN_DEFAULT;

  if ( !loop ) return FALSE;
  if ( !PL_get_atom_chars(mode_t, &mode) )
    return PL_type_error("atom", mode_t);
  if ( strcmp(mode, "once") == 0 ) m = UV_RUN_ONCE;
  else if ( strcmp(mode, "nowait") == 0 ) m = UV_RUN_NOWAIT;

  uv_run(loop, m);
  return TRUE;
}

static foreign_t
pl_uv_stop(term_t loop_t)
{ uv_loop_t *loop = get_loop(loop_t);
  if ( !loop ) return FALSE;
  uv_stop(loop);
  return TRUE;
}

install_t
install_uv_swi(void)
{ PL_register_foreign("uv_loop_new",           1, pl_uv_loop_new, 0);
  PL_register_foreign("uv_tcp_init",           2, pl_uv_tcp_init, 0);
  PL_register_foreign("uv_tcp_bind_reuseport", 3, pl_uv_tcp_bind_reuseport, 0);
  PL_register_foreign("uv_listen",             3, pl_uv_listen, 0);
  PL_register_foreign("uv_accept",             2, pl_uv_accept, 0);
  PL_register_foreign("uv_read_start",         2, pl_uv_read_start, 0);
  PL_register_foreign("uv_read_stop",          1, pl_uv_read_stop, 0);
  PL_register_foreign("uv_write",              3, pl_uv_write, 0);
  PL_register_foreign("uv_close",              2, pl_uv_close, 0);
  PL_register_foreign("uv_timer_init",         2, pl_uv_timer_init, 0);
  PL_register_foreign("uv_timer_start",        4, pl_uv_timer_start, 0);
  PL_register_foreign("uv_timer_stop",         1, pl_uv_timer_stop, 0);
  PL_register_foreign("uv_fs_open",            5, pl_uv_fs_open, 0);
  PL_register_foreign("uv_fs_read",            5, pl_uv_fs_read, 0);
  PL_register_foreign("uv_fs_close",           3, pl_uv_fs_close, 0);
  PL_register_foreign("uv_async_init",         3, pl_uv_async_init, 0);
  PL_register_foreign("uv_async_send",         1, pl_uv_async_send, 0);
  PL_register_foreign("uv_run",                2, pl_uv_run, 0);
  PL_register_foreign("uv_stop",               1, pl_uv_stop, 0);
}
