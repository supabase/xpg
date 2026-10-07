SRC_DIR = src

# the `-Wno`s quiet C90 warnings
PG_CFLAGS = -std=c11 -Wextra -Wall -Werror \
	-Wno-declaration-after-statement \
	-Wno-vla \
	-Wno-long-long
ifeq ($(COVERAGE), 1)
PG_CFLAGS += --coverage
endif

UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Darwin)
    SHARED_EXT  := dylib
else
    SHARED_EXT  := so
endif

EXTENSION = hello
EXTVERSION = 0.1

DATA = $(wildcard sql/*--*.sql)

EXTRA_CLEAN = sql/$(EXTENSION)--$(EXTVERSION).sql $(EXTENSION).control

TESTS = $(wildcard test/sql/*.sql)
REGRESS = $(patsubst test/sql/%.sql,%,$(TESTS))
REGRESS_OPTS = --use-existing --inputdir=test

MODULE_big = $(EXTENSION)
SRC = $(wildcard $(SRC_DIR)/*.c)

OBJS = $(patsubst $(SRC_DIR)/%.c, src/%.o, $(SRC))

PG_CONFIG = pg_config

PG_CPPFLAGS := $(CPPFLAGS) -DEXTVERSION=\"$(EXTVERSION)\"

all: sql/$(EXTENSION)--$(EXTVERSION).sql $(EXTENSION).control

sql/$(EXTENSION)--$(EXTVERSION).sql: sql/$(EXTENSION).sql
	cp $< $@

$(EXTENSION).control:
	sed "s/@EXTVERSION@/$(EXTVERSION)/g" $(EXTENSION).control.in > $@

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

.PHONY: test
test:
	make installcheck

.PHONY: test-core
test-core:
	$(pg_regress_installcheck) --dlpath=$(PG_REGRESS_TESTS)/lib --inputdir=$(PG_REGRESS_TESTS) --schedule=$(PG_REGRESS_TESTS)/parallel_schedule --dbname=regression
