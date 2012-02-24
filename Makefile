PROGNAME=Dabble

DC=dmd
DFLAGS=-inline
DSOURCE=$(wildcard src/*.d)

all:
	$(DC) $(DFLAGS) $(DSOURCE) -release -odpkg/release -ofbin/$(PROGNAME)

unittest:
	$(DC) $(DFLAGS) $(DSOURCE) -unittest -debug -ofpkg/unittest -ofbin/$(PROGNAME).unittest
	bin/$(PROGNAME).unittest

debug:
	$(DC) $(DFLAGS) $(DSOURCE) -debug -ofpkg/debug -ofbin/$(PROGNAME).debug
