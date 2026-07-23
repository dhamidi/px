SWIPL_LD = swipl-ld
CFLAGS   = -Wall -Wextra -O2 -I../vendor/llhttp

# libuv discovery (adr/0034): pkg-config first; but Homebrew installs
# no pkg-config by default (the first real Mac clone proved it), so
# fall back to the stable Homebrew keg symlink -- /opt/homebrew/opt
# on Apple Silicon, /usr/local/opt on Intel -- before assuming the
# default search paths (Debian's libuv1-dev) suffice with plain -luv.
UV_CFLAGS := $(shell pkg-config --cflags libuv 2>/dev/null)
UV_LIBS   := $(shell pkg-config --libs libuv 2>/dev/null)
ifeq ($(strip $(UV_LIBS)),)
  UV_PREFIX := $(firstword $(wildcard /opt/homebrew/opt/libuv /usr/local/opt/libuv))
  ifneq ($(strip $(UV_PREFIX)),)
    UV_CFLAGS = -I$(UV_PREFIX)/include
    UV_LIBS   = -L$(UV_PREFIX)/lib -luv
  else
    UV_LIBS = -luv
  endif
endif

# adr/0020: serialized threading mode as belt and braces; drop the
# runtime extension loader (also drops the -ldl link requirement).
CFLAGS_SQLITE = -DSQLITE_THREADSAFE=1 -DSQLITE_OMIT_LOAD_EXTENSION \
                -I../vendor/sqlite3

.PHONY: all clean distclean

all: uv_swi.so llhttp_swi.so http_stream_swi.so sqlite3_swi.so

uv_swi.so: uv_swi.c
	$(SWIPL_LD) -shared -o $@ $(CFLAGS) $(UV_CFLAGS) $< $(UV_LIBS)

llhttp_swi.so: llhttp_swi.c ../vendor/llhttp/llhttp.c ../vendor/llhttp/api.c ../vendor/llhttp/http.c
	$(SWIPL_LD) -shared -o $@ $(CFLAGS) $^

http_stream_swi.so: http_stream_swi.c
	$(SWIPL_LD) -shared -o $@ $(CFLAGS) $<

# The ~9 MB vendored amalgamation is compiled to an object file once and
# cached (adr/0020): `clean` leaves it alone so day-to-day rebuilds of
# sqlite3_swi.c stay fast; `distclean` removes it. Third-party warnings
# in the amalgamation are acceptable, hence no -Wall -Wextra here.
sqlite3.o: ../vendor/sqlite3/sqlite3.c
	$(CC) -c -fPIC -O2 $(CFLAGS_SQLITE) -o $@ $<

sqlite3_swi.so: sqlite3_swi.c sqlite3.o
	$(SWIPL_LD) -shared -o $@ $(CFLAGS) $(CFLAGS_SQLITE) $^

clean:
	rm -f *.so

distclean: clean
	rm -f sqlite3.o
