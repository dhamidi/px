/* 1:1 SWI-Prolog <-> SQLite bindings. See adr/0002 and adr/0020.
 *
 * Every exported predicate maps to one underlying SQLite call, with the
 * single carve-out adr/0020 grants: sqlite3_bind/3 and sqlite3_column/3
 * make a minimal type dispatch, because Prolog terms are dynamically
 * typed and SQLite's bind/column API is type-split -- that dispatch is
 * the FFI crossing itself, not smuggled policy. Nothing else branches.
 *
 * DB and Stmt are blobs following uv_swi.c's wrapping pattern, with the
 * adr/0014/0015 lesson applied from day one: every blob is pinned at
 * creation (PL_record of the freshly-unified blob term, stored in the
 * wrapper as self_ref) and unpinned only on confirmed close/finalize.
 * The blob release hook only ever sees an already-torn-down wrapper; it
 * never calls sqlite3_close or sqlite3_finalize itself. A leaked
 * (never-finalized) statement is a visible resource leak, not a latent
 * heap corruption.
 *
 * Errors: any SQLite return code other than SQLITE_OK / SQLITE_ROW /
 * SQLITE_DONE becomes a Prolog exception
 *   error(sqlite3_error(Code, Msg), context(Pred/Arity, _))
 * carrying sqlite3_errmsg at the moment of failure. No SQLite failure
 * is ever a silent Prolog failure at this layer.
 *
 * Known-benign warnings (same as uv_swi.c): PL_* calls whose results
 * are deliberately ignored are cast to (void) to silence
 * warn_unused_result; gcc's -Wmaybe-uninitialized can false-positive on
 * the blob-getter pattern (get_db/get_stmt only set *pp on the TRUE
 * path, which is the only path callers read it on).
 */

#include <SWI-Prolog.h>
#include <SWI-Stream.h>
#include <sqlite3.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

static atom_t ATOM_null;
static atom_t ATOM_row;
static atom_t ATOM_done;

		 /*******************************
		 *          BLOB TYPES          *
		 *******************************/

typedef struct db_blob
{ sqlite3  *db;
  record_t  self_ref;   /* PL_record of the blob term; pins the blob
                         * atom against atom-GC from creation until
                         * confirmed close (adr/0014, adr/0015). */
  int       closed;     /* close is idempotent: second close is a no-op */
} db_blob_t;

typedef struct stmt_blob
{ sqlite3_stmt *stmt;
  sqlite3      *db;     /* owning connection, for errmsg on failure */
  record_t      self_ref;  /* same pin, same rule */
  int           finalized; /* finalize is idempotent too */
} stmt_blob_t;

static int
release_db_blob(atom_t a)
{ db_blob_t **pp = PL_blob_data(a, NULL, NULL);
  db_blob_t *p = *pp;
  /* Only ever reached after pl_sqlite3_close erased the pin, so the
   * sqlite3* is already closed; never close it from GC (adr/0015). */
  if ( p )
    free(p);
  return TRUE;
}

static int
write_db_blob(IOSTREAM *s, atom_t a, int flags)
{ db_blob_t **pp = PL_blob_data(a, NULL, NULL);
  db_blob_t *p = *pp;
  (void)flags;
  Sfprintf(s, "<sqlite3_db>(%p%s)", (void*)p,
           (p && p->closed) ? ",closed" : "");
  return TRUE;
}

static PL_blob_t db_blob_type =
{ .magic   = PL_BLOB_MAGIC,
  .flags   = PL_BLOB_UNIQUE,
  .name    = "sqlite3_db",
  .release = release_db_blob,
  .compare = NULL,
  .write   = write_db_blob,
  .acquire = NULL,
  .save    = NULL,
  .load    = NULL
};

static int
release_stmt_blob(atom_t a)
{ stmt_blob_t **pp = PL_blob_data(a, NULL, NULL);
  stmt_blob_t *p = *pp;
  /* Same rule as release_db_blob: never sqlite3_finalize from GC. */
  if ( p )
    free(p);
  return TRUE;
}

static int
write_stmt_blob(IOSTREAM *s, atom_t a, int flags)
{ stmt_blob_t **pp = PL_blob_data(a, NULL, NULL);
  stmt_blob_t *p = *pp;
  (void)flags;
  Sfprintf(s, "<sqlite3_stmt>(%p%s)", (void*)p,
           (p && p->finalized) ? ",finalized" : "");
  return TRUE;
}

static PL_blob_t stmt_blob_type =
{ .magic   = PL_BLOB_MAGIC,
  .flags   = PL_BLOB_UNIQUE,
  .name    = "sqlite3_stmt",
  .release = release_stmt_blob,
  .compare = NULL,
  .write   = write_stmt_blob,
  .acquire = NULL,
  .save    = NULL,
  .load    = NULL
};

static int
get_db(term_t t, db_blob_t **pp)
{ void *data;
  size_t len;
  PL_blob_t *type;

  if ( !PL_get_blob(t, &data, &len, &type) || type != &db_blob_type )
    return PL_type_error("sqlite3_db", t);
  *pp = *(db_blob_t**)data;
  return TRUE;
}

static int
get_stmt(term_t t, stmt_blob_t **pp)
{ void *data;
  size_t len;
  PL_blob_t *type;

  if ( !PL_get_blob(t, &data, &len, &type) || type != &stmt_blob_type )
    return PL_type_error("sqlite3_stmt", t);
  *pp = *(stmt_blob_t**)data;
  return TRUE;
}

/* Live-handle getters: using an already-closed connection or an
 * already-finalized statement is a caller bug we want loud, not a
 * dangling-pointer dereference. */
static int
get_live_db(term_t t, db_blob_t **pp)
{ if ( !get_db(t, pp) )
    return FALSE;
  if ( (*pp)->closed )
    return PL_existence_error("sqlite3_db", t);
  return TRUE;
}

static int
get_live_stmt(term_t t, stmt_blob_t **pp)
{ if ( !get_stmt(t, pp) )
    return FALSE;
  if ( (*pp)->finalized )
    return PL_existence_error("sqlite3_stmt", t);
  return TRUE;
}

		 /*******************************
		 *            ERRORS            *
		 *******************************/

/* Throw error(sqlite3_error(Code, Msg), context(Pred/Arity, _)) with the
 * human message fetched via sqlite3_errmsg at the moment of failure
 * (sqlite3_errstr when there is no connection to ask). */
static int
raise_sqlite3_error(const char *pred, int arity, int code, sqlite3 *db)
{ term_t ex = PL_new_term_ref();
  const char *msg = db ? sqlite3_errmsg(db) : sqlite3_errstr(code);

  if ( PL_unify_term(ex,
         PL_FUNCTOR_CHARS, "error", 2,
           PL_FUNCTOR_CHARS, "sqlite3_error", 2,
             PL_INT, code,
             PL_UTF8_STRING, msg ? msg : "unknown error",
           PL_FUNCTOR_CHARS, "context", 2,
             PL_FUNCTOR_CHARS, "/", 2,
               PL_CHARS, pred,
               PL_INT, arity,
             PL_VARIABLE) )
    return PL_raise_exception(ex);
  return FALSE;
}

		 /*******************************
		 *       FOREIGN PREDICATES     *
		 *******************************/

/* sqlite3_open(+File, -DB): sqlite3_open_v2 */
static foreign_t
pl_sqlite3_open(term_t file_t, term_t db_t)
{ char *file;
  size_t len;
  sqlite3 *db = NULL;
  db_blob_t *p;
  int rc;

  if ( !PL_get_nchars(file_t, &len, &file, CVT_ATOM|CVT_STRING|REP_UTF8) )
    return PL_type_error("text", file_t);

  rc = sqlite3_open_v2(file, &db,
                       SQLITE_OPEN_READWRITE|SQLITE_OPEN_CREATE, NULL);
  if ( rc != SQLITE_OK )
  { int r = raise_sqlite3_error("sqlite3_open", 2, rc, db);
    if ( db )
      sqlite3_close(db);  /* even on failed open, db may be allocated */
    return r;
  }

  p = calloc(1, sizeof(*p));
  if ( !p )
  { sqlite3_close(db);
    return PL_resource_error("memory");
  }
  p->db = db;

  if ( !PL_unify_blob(db_t, &p, sizeof(p), &db_blob_type) )
    return FALSE;
  /* Pin the blob atom alive from creation until confirmed close --
   * see db_blob_t.self_ref and adr/0015: atom-GC must never be able to
   * reclaim a connection blob while statements still point into it. */
  p->self_ref = PL_record(db_t);
  return TRUE;
}

/* sqlite3_close(+DB): sqlite3_close. Idempotent: closing an
 * already-closed handle succeeds silently. Fails loudly (SQLITE_BUSY
 * exception) if statements are still live -- a bug we want loud. */
static foreign_t
pl_sqlite3_close(term_t db_t)
{ db_blob_t *p;
  int rc;

  if ( !get_db(db_t, &p) )
    return FALSE;
  if ( p->closed )
    return TRUE;

  rc = sqlite3_close(p->db);
  if ( rc != SQLITE_OK )
    return raise_sqlite3_error("sqlite3_close", 1, rc, p->db);

  /* Underlying C call succeeded: only now tear down the wrapper and
   * release the creation-time pin (adr/0015 ordering). */
  p->db = NULL;
  p->closed = 1;
  if ( p->self_ref )
  { PL_erase(p->self_ref);
    p->self_ref = 0;
  }
  return TRUE;
}

/* sqlite3_prepare(+DB, +SQL, -Stmt): sqlite3_prepare_v2. One statement
 * per call; trailing SQL after the first statement is an error. */
static foreign_t
pl_sqlite3_prepare(term_t db_t, term_t sql_t, term_t stmt_t)
{ db_blob_t *dbp;
  char *sql;
  size_t len;
  sqlite3_stmt *stmt = NULL;
  const char *tail = NULL;
  stmt_blob_t *p;
  int rc;

  if ( !get_live_db(db_t, &dbp) )
    return FALSE;
  if ( !PL_get_nchars(sql_t, &len, &sql, CVT_ATOM|CVT_STRING|REP_UTF8) )
    return PL_type_error("text", sql_t);

  rc = sqlite3_prepare_v2(dbp->db, sql, (int)len, &stmt, &tail);
  if ( rc != SQLITE_OK )
    return raise_sqlite3_error("sqlite3_prepare", 3, rc, dbp->db);
  if ( !stmt )                       /* empty SQL / comment only */
    return PL_domain_error("sql_statement", sql_t);
  { const char *end = sql + len;     /* trailing SQL: adr/0020 says error */
    const char *q;
    for(q = tail; q < end; q++)
    { if ( !isspace((unsigned char)*q) )
      { sqlite3_finalize(stmt);
        return PL_domain_error("single_sql_statement", sql_t);
      }
    }
  }

  p = calloc(1, sizeof(*p));
  if ( !p )
  { sqlite3_finalize(stmt);
    return PL_resource_error("memory");
  }
  p->stmt = stmt;
  p->db   = dbp->db;

  if ( !PL_unify_blob(stmt_t, &p, sizeof(p), &stmt_blob_type) )
    return FALSE;
  /* Same creation-time pin as pl_sqlite3_open (adr/0014/0015). */
  p->self_ref = PL_record(stmt_t);
  return TRUE;
}

/* sqlite3_bind(+Stmt, +Index, +Value): one of sqlite3_bind_int64 /
 * _double / _text / _null, chosen by the Prolog value's type -- the
 * minimal dispatch adr/0020 carves out as the FFI crossing itself.
 * Index is 1-based, matching SQLite. */
static foreign_t
pl_sqlite3_bind(term_t stmt_t, term_t index_t, term_t value_t)
{ stmt_blob_t *p;
  int index;
  int rc;

  if ( !get_live_stmt(stmt_t, &p) )
    return FALSE;
  if ( !PL_get_integer(index_t, &index) )
    return PL_type_error("integer", index_t);

  if ( PL_is_integer(value_t) )
  { int64_t v;
    if ( !PL_get_int64(value_t, &v) )
      return PL_type_error("int64", value_t);
    rc = sqlite3_bind_int64(p->stmt, index, v);
  } else if ( PL_is_float(value_t) )
  { double v;
    if ( !PL_get_float(value_t, &v) )
      return PL_type_error("float", value_t);
    rc = sqlite3_bind_double(p->stmt, index, v);
  } else if ( PL_is_atom(value_t) || PL_is_string(value_t) )
  { atom_t a;
    if ( PL_get_atom(value_t, &a) && a == ATOM_null )
    { rc = sqlite3_bind_null(p->stmt, index);
    } else
    { char *s;
      size_t len;
      if ( !PL_get_nchars(value_t, &len, &s, CVT_ATOM|CVT_STRING|REP_UTF8) )
        return PL_type_error("text", value_t);
      rc = sqlite3_bind_text(p->stmt, index, s, (int)len, SQLITE_TRANSIENT);
    }
  } else
  { return PL_type_error("sqlite3_value", value_t);
  }

  if ( rc != SQLITE_OK )
    return raise_sqlite3_error("sqlite3_bind", 3, rc, p->db);
  return TRUE;
}

/* sqlite3_step(+Stmt, -Result): sqlite3_step. Unifies Result with the
 * atom `row` or `done`; every other return code throws. */
static foreign_t
pl_sqlite3_step(term_t stmt_t, term_t result_t)
{ stmt_blob_t *p;
  int rc;

  if ( !get_live_stmt(stmt_t, &p) )
    return FALSE;

  rc = sqlite3_step(p->stmt);
  if ( rc == SQLITE_ROW )
    return PL_unify_atom(result_t, ATOM_row);
  if ( rc == SQLITE_DONE )
    return PL_unify_atom(result_t, ATOM_done);
  return raise_sqlite3_error("sqlite3_step", 2, rc, p->db);
}

/* sqlite3_column(+Stmt, +Index, -Value): sqlite3_column_type + the
 * matching accessor -- the read-side half of the bind dispatch.
 * Index is 0-based, matching SQLite. INTEGER -> integer, FLOAT ->
 * float, TEXT -> UTF-8 string, BLOB -> string of the raw bytes,
 * NULL -> the atom `null`. */
static foreign_t
pl_sqlite3_column(term_t stmt_t, term_t index_t, term_t value_t)
{ stmt_blob_t *p;
  int index;

  if ( !get_live_stmt(stmt_t, &p) )
    return FALSE;
  if ( !PL_get_integer(index_t, &index) )
    return PL_type_error("integer", index_t);

  switch( sqlite3_column_type(p->stmt, index) )
  { case SQLITE_INTEGER:
      return PL_unify_int64(value_t, sqlite3_column_int64(p->stmt, index));
    case SQLITE_FLOAT:
      return PL_unify_float(value_t, sqlite3_column_double(p->stmt, index));
    case SQLITE_TEXT:
    { const unsigned char *text = sqlite3_column_text(p->stmt, index);
      int bytes = sqlite3_column_bytes(p->stmt, index);
      return PL_unify_chars(value_t, PL_STRING|REP_UTF8,
                            (size_t)bytes, text ? (const char*)text : "");
    }
    case SQLITE_BLOB:
    { const void *blob = sqlite3_column_blob(p->stmt, index);
      int bytes = sqlite3_column_bytes(p->stmt, index);
      return PL_unify_chars(value_t, PL_STRING|REP_ISO_LATIN_1,
                            (size_t)bytes, blob ? (const char*)blob : "");
    }
    case SQLITE_NULL:
    default:
      return PL_unify_atom(value_t, ATOM_null);
  }
}

/* sqlite3_column_count(+Stmt, -N): sqlite3_column_count */
static foreign_t
pl_sqlite3_column_count(term_t stmt_t, term_t n_t)
{ stmt_blob_t *p;

  if ( !get_live_stmt(stmt_t, &p) )
    return FALSE;
  return PL_unify_integer(n_t, sqlite3_column_count(p->stmt));
}

/* sqlite3_column_name(+Stmt, +Index, -Name): sqlite3_column_name.
 * Name is an atom, so rows can be dicts keyed by column name. */
static foreign_t
pl_sqlite3_column_name(term_t stmt_t, term_t index_t, term_t name_t)
{ stmt_blob_t *p;
  int index;
  const char *name;

  if ( !get_live_stmt(stmt_t, &p) )
    return FALSE;
  if ( !PL_get_integer(index_t, &index) )
    return PL_type_error("integer", index_t);

  name = sqlite3_column_name(p->stmt, index);
  if ( !name )
    return PL_domain_error("column_index", index_t);
  return PL_unify_chars(name_t, PL_ATOM|REP_UTF8, (size_t)-1, name);
}

/* sqlite3_finalize(+Stmt): sqlite3_finalize. Idempotent: finalizing an
 * already-finalized handle succeeds silently. Note sqlite3_finalize
 * destroys the statement unconditionally (a non-OK return only echoes
 * the most recent step error, which pl_sqlite3_step already threw), so
 * unlike close the wrapper is torn down and the pin released regardless
 * of the return code -- keeping a pointer to a freed statement because
 * an earlier step failed would be exactly the dangling-pointer class
 * adr/0015 exists to prevent. The stale error code is then re-thrown. */
static foreign_t
pl_sqlite3_finalize(term_t stmt_t)
{ stmt_blob_t *p;
  int rc;
  sqlite3 *db;

  if ( !get_stmt(stmt_t, &p) )
    return FALSE;
  if ( p->finalized )
    return TRUE;

  db = p->db;
  rc = sqlite3_finalize(p->stmt);
  p->stmt = NULL;
  p->db = NULL;
  p->finalized = 1;
  if ( p->self_ref )
  { PL_erase(p->self_ref);
    p->self_ref = 0;
  }
  if ( rc != SQLITE_OK )
    return raise_sqlite3_error("sqlite3_finalize", 1, rc, db);
  return TRUE;
}

/* sqlite3_reset(+Stmt): sqlite3_reset */
static foreign_t
pl_sqlite3_reset(term_t stmt_t)
{ stmt_blob_t *p;
  int rc;

  if ( !get_live_stmt(stmt_t, &p) )
    return FALSE;
  rc = sqlite3_reset(p->stmt);
  if ( rc != SQLITE_OK )
    return raise_sqlite3_error("sqlite3_reset", 1, rc, p->db);
  return TRUE;
}

/* sqlite3_last_insert_rowid(+DB, -Id): sqlite3_last_insert_rowid */
static foreign_t
pl_sqlite3_last_insert_rowid(term_t db_t, term_t id_t)
{ db_blob_t *p;

  if ( !get_live_db(db_t, &p) )
    return FALSE;
  return PL_unify_int64(id_t, sqlite3_last_insert_rowid(p->db));
}

/* sqlite3_changes(+DB, -N): sqlite3_changes */
static foreign_t
pl_sqlite3_changes(term_t db_t, term_t n_t)
{ db_blob_t *p;

  if ( !get_live_db(db_t, &p) )
    return FALSE;
  return PL_unify_integer(n_t, sqlite3_changes(p->db));
}

/* sqlite3_errmsg(+DB, -Msg): sqlite3_errmsg */
static foreign_t
pl_sqlite3_errmsg(term_t db_t, term_t msg_t)
{ db_blob_t *p;
  const char *msg;

  if ( !get_live_db(db_t, &p) )
    return FALSE;
  msg = sqlite3_errmsg(p->db);
  return PL_unify_chars(msg_t, PL_STRING|REP_UTF8, (size_t)-1,
                        msg ? msg : "");
}

install_t
install_sqlite3_swi(void)
{ ATOM_null = PL_new_atom("null");
  ATOM_row  = PL_new_atom("row");
  ATOM_done = PL_new_atom("done");

  PL_register_foreign("sqlite3_open",              2, pl_sqlite3_open, 0);
  PL_register_foreign("sqlite3_close",             1, pl_sqlite3_close, 0);
  PL_register_foreign("sqlite3_prepare",           3, pl_sqlite3_prepare, 0);
  PL_register_foreign("sqlite3_bind",              3, pl_sqlite3_bind, 0);
  PL_register_foreign("sqlite3_step",              2, pl_sqlite3_step, 0);
  PL_register_foreign("sqlite3_column",            3, pl_sqlite3_column, 0);
  PL_register_foreign("sqlite3_column_count",      2, pl_sqlite3_column_count, 0);
  PL_register_foreign("sqlite3_column_name",       3, pl_sqlite3_column_name, 0);
  PL_register_foreign("sqlite3_finalize",          1, pl_sqlite3_finalize, 0);
  PL_register_foreign("sqlite3_reset",             1, pl_sqlite3_reset, 0);
  PL_register_foreign("sqlite3_last_insert_rowid", 2, pl_sqlite3_last_insert_rowid, 0);
  PL_register_foreign("sqlite3_changes",           2, pl_sqlite3_changes, 0);
  PL_register_foreign("sqlite3_errmsg",            2, pl_sqlite3_errmsg, 0);
}
