# OBCS Makefile
# Jie Zheng
#
# This Makefile is used to build artifacts
# for the Ontology for Biological and Clinical Statistics.

### Configuration
#
# prologue:
# <http://clarkgrubb.com/makefile-style-guide#toc2>

MAKEFLAGS += --warn-undefined-variables
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := all
.DELETE_ON_ERROR:
.SUFFIXES:

### Definitions

SHELL   := /bin/bash
OBO     := http://purl.obolibrary.org/obo
OBCS    := $(OBO)/OBCS_
DEV     := $(OBO)/obcs/dev
TODAY   := $(shell date +%Y-%m-%d)

### Directories
#
# This is a temporary place to put things.
build:
	mkdir -p $@


### ROBOT
#
# We use the official development version of ROBOT for most things.
build/robot.jar: | build
	curl -L -o $@ "https://github.com/ontodev/robot/releases/download/v1.1.0/robot.jar"

ROBOT := java -jar build/robot.jar


### Imports
#
# Use Ontofox to import various modules.
build/%_imports.owl: src/ontology/OntoFox_inputs/%_import_input.txt | build/robot.jar build
	curl -s -F file=@$< -o $@ https://ontofox.hegroup.org/service.php

# Use ROBOT to remove external java axioms
src/ontology/imports/%_imports.owl: build/%_imports.owl
	$(ROBOT) remove --input build/$*_imports.owl \
	--base-iri 'http://purl.obolibrary.org/obo/$*_' \
	--axioms external \
	--preserve-structure false \
	--trim false \
	--output $@ 

IMPORT_FILES := $(wildcard src/ontology/imports/*_imports.owl)

.PHONY: imports
imports: $(IMPORT_FILES)


### Build
#
# Here we create a standalone OWL file appropriate for release.
# This involves merging, reasoning, annotating,
# and removing any remaining import declarations.
build/obcs_merged.owl: src/ontology/obcs_dev.owl | build/robot.jar build
	$(ROBOT) merge \
	--input $< \
	annotate \
	--ontology-iri "$(OBO)/obcs/obcs_merged.owl" \
	--version-iri "$(OBO)/obcs/$(TODAY)/obcs_merged.owl" \
	--annotation owl:versionInfo "$(TODAY)" \
	--output build/obcs_merged.tmp.owl
	sed '/<owl:imports/d' build/obcs_merged.tmp.owl > $@
	rm build/obcs_merged.tmp.owl

obcs.owl: build/obcs_merged.owl
	$(ROBOT) reason \
	--input $< \
	--reasoner HermiT \
	annotate \
	--ontology-iri "$(OBO)/obcs.owl" \
	--version-iri "$(OBO)/obcs/$(TODAY)/obcs.owl" \
	--annotation owl:versionInfo "$(TODAY)" \
	--output $@

test_report.tsv: build/obcs_merged.owl
	$(ROBOT) report \
	--input $< \
        --fail-on none \
	--output $@

### Test
#
# Run main tests
MERGED_VIOLATION_QUERIES := $(wildcard src/sparql/*-violation.rq)

build/terms-report.csv: build/obcs_merged.owl src/sparql/terms-report.rq | build
	$(ROBOT) query --input $< --select $(word 2,$^) $@

build/obcs-previous-release.owl: | build
	curl -L -o $@ "http://purl.obolibrary.org/obo/obcs.owl"

build/released-entities.tsv: build/obcs-previous-release.owl src/sparql/get-obcs-entities.rq | build/robot.jar
	$(ROBOT) query --input $< --select $(word 2,$^) $@

build/current-entities.tsv: build/obcs_merged.owl src/sparql/get-obcs-entities.rq | build/robot.jar
	$(ROBOT) query --input $< --select $(word 2,$^) $@

build/dropped-entities.tsv: build/released-entities.tsv build/current-entities.tsv
	comm -23 $^ > $@

# Run all validation queries and exit on error.
.PHONY: verify
verify: verify-merged verify-entities

# Run validation queries on obcs_merged and exit on error.
.PHONY: verify-merged
verify-merged: build/obcs_merged.owl $(MERGED_VIOLATION_QUERIES) | build/robot.jar
	$(ROBOT) verify --input $< --output-dir build \
	--queries $(MERGED_VIOLATION_QUERIES)

# Check if any entities have been dropped and exit on error.
.PHONY: verify-entities
verify-entities: build/dropped-entities.tsv
	@echo $(shell < $< wc -l) " obcs IRIs have been dropped"
	@! test -s $<

# Run a Hermit reasoner to find inconsistencies
.PHONY: reason
reason: build/obcs_merged.owl | build/robot.jar
	$(ROBOT) reason --input $< --reasoner HermiT

.PHONY: test
test: reason verify


### General/Users/jiezheng/Documents/ontology/obcs
#
# Full build
.PHONY: all
all: test obcs.owl build/terms-report.csv

# Remove generated files
.PHONY: clean
clean:
	rm -rf build

# Check for problems such as bad line-endings
.PHONY: check
check:
	src/scripts/check-line-endings.sh tsv

# Fix simple problems such as bad line-endings
.PHONY: fix
fix:
	src/scripts/fix-eol-all.sh
