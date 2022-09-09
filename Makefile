CURRENT_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

BASENAME = sweep

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Linux)
    SOEXT = so
endif
ifeq ($(UNAME_S),Darwin)
    SOEXT = dylib
endif

SWIPL      ?= swipl
SWIPLBASE   = $(shell $(SWIPL) --dump-runtime-variables | grep PLBASE   | cut -f 2 -d = | cut -f 1 -d ';')
SWIPLLIBDIR = $(shell $(SWIPL) --dump-runtime-variables | grep PLLIBDIR | cut -f 2 -d = | cut -f 1 -d ';')

TARGET   = $(BASENAME)-module.$(SOEXT)
OBJECT   = $(BASENAME).o
SOURCE   = $(BASENAME).c

LDFLAGS += -shared
LDFLAGS += -L$(SWIPLLIBDIR)
ifeq ($(UNAME_S),Linux)
    LDFLAGS += -Wl,-Bstatic
endif
LDFLAGS += -lswipl
ifeq ($(UNAME_S),Linux)
    LDFLAGS += -Wl,-Bdynamic
endif

CFLAGS  += -fPIC
CFLAGS  += -Wall
CFLAGS  += -Wextra
CFLAGS  += -O2
CFLAGS  += -I$(SWIPLBASE)/include

.PHONY: clean all check

all: $(TARGET)

$(OBJECT): $(SOURCE)
	$(CC) $(CFLAGS) -o $@ -c $(SOURCE)

$(TARGET): $(OBJECT)
	$(CC) -o $@ $(OBJECT) $(LDFLAGS)

clean:
	rm -f $(TARGET) $(OBJECT) $(BASENAME).info $(BASENAME).texi $(BASENAME).html

$(BASENAME).info:: README.org
	emacs -Q --batch --eval "(require 'ox-texinfo)" \
		--eval "(with-current-buffer (find-file \"README.org\") (org-export-to-file (quote texinfo) \"$@\" nil nil nil nil nil (quote org-texinfo-compile)))"

check: $(TARGET)
	emacs -batch --eval '(add-to-list (quote load-path) (expand-file-name "."))' \
		-l ert -l sweep -l sweep-tests.el -f ert-run-tests-batch-and-exit
