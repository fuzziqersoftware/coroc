OBJECTS=coroc.o
CXX=g++
CXXFLAGS=-std=c++14 -g -Wall -Werror
LDFLAGS=-g -std=c++14

ifeq ($(shell uname -s),Darwin)
	INSTALL_DIR=/opt/local
else
	INSTALL_DIR=/usr/local
endif

all: libcoroc.a test

install: libcoroc.a
	mkdir -p $(INSTALL_DIR)/include/coroc
	cp libcoroc.a $(INSTALL_DIR)/lib/
	cp -r *.hh $(INSTALL_DIR)/include/coroc/

libcoroc.a: $(OBJECTS)
	rm -f libcoroc.a
	ar rcs libcoroc.a $(OBJECTS)

test: BasicTest
	./BasicTest

%Test: %Test.o $(OBJECTS)
	$(CXX) $(LDFLAGS) $^ -o $@

clean:
	rm -rf *.dSYM *.o gmon.out libcoroc.a *Test

.PHONY: clean test
