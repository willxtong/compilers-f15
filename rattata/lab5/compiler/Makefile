SUBDIRS = top,util,front_end/parse,front_end/generalToInfAddr,front_end/typeChecker,front_end/elab,back_end/formatAssem,back_end/regAlloc,back_end/to3Addr,back_end/to2Addr,back_end/toWonkyAssem,back_end/removeMemMemInstrs,back_end/fewTmpsTo3Addr,back_end/condenseMoves,front_end/memStuffToInfAddr,optimizations/deadCodeElimination,optimizations,optimizations/constPropAndFold,optimizations/inlining
LIBS = str
MAIN = top

OCAMLBUILD = ocamlbuild
OCAMLBUILDFLAGS = -use-ocamlfind

DEBUG = $(MAIN).d.byte
NATIVE = $(MAIN).native
TOPLEVEL = $(MAIN).top

all: c0c

c0c: bin/c0c
bin/c0c: native
	mkdir -p bin
	install $(NATIVE) $@

debug: $(DEBUG)
native: $(NATIVE)
top: $(TOPLEVEL)

OCAMLOPTS = $(OCAMLBUILDFLAGS) -Is $(SUBDIRS) -libs $(LIBS)
OCAMLBRUN = $(OCAMLBUILD) $(OCAMLOPTS)

%.native: always
	$(OCAMLBRUN) $@
%.d.byte: always
	$(OCAMLBRUN) -cflags -annot $@
top: always
	$(OCAMLBRUN) $@

clean:
	$(OCAMLBUILD) -Is $(SUBDIRS) -clean
	@echo			# $(OCAMLBUILD) -clean needs a newline
	rm -f bin/c0c

always:

.PHONY: c0c debug native top clean always
