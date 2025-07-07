# KeemenaPreprocessing

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
<!-- [![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://mantzaris.github.io/KeemenaPreprocessing.jl/stable/) -->
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://mantzaris.github.io/KeemenaPreprocessing.jl/dev/)
[![Build Status](https://github.com/mantzaris/KeemenaPreprocessing.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/mantzaris/KeemenaPreprocessing.jl/actions/workflows/CI.yml?query=branch%3Amain)

---



> **One-stop text pre-processor for Julia** - clean -> tokenise ->
segment -> build vocabulary -> align levels -> save bundle.

---

## What you get

* **Vocabulary**
  - deterministic id <-> token tables  
  - minimum-frequency filtering  
  - user-defined special tokens  

* **Tokenisation**
  - byte, character, whitespace or Unicode-word  
  - pluggable custom function  

* **Offset vectors**
  - word, sentence, paragraph and document boundaries  
  - always begin with **1** and end with `n_tokens + 1`  

* **Alignment cross-maps**
  - byte <-> char <-> word indices (forward & backward)  

* **Streaming mode**
  - constant-memory two-pass pipeline  
  - choose *vector of bundles* **or** *single merged bundle*  

* **Bundles**
  - everything packed into a `PreprocessBundle`  
  - save / load with JLD2 in one line  

---

## Quick example (full corpus in RAM)

```julia
using KeemenaPreprocessing

docs = ["First document.", "Second document..."]

cfg  = PreprocessConfiguration(
          tokenizer_name          = :unicode,
          record_sentence_offsets = true,
          minimum_token_frequency = 2)

bundle = preprocess_corpus(docs; config = cfg)

word_ids = get_token_ids(bundle, :word)
println("tokens:", length(word_ids))
```

The single call does **all** of: load, clean, tokenise, build vocabulary,
record offsets, assemble bundle.

---


## Processing *huge* corpora with constant memory

```julia
using KeemenaPreprocessing, Downloads

# Two Project Gutenberg books
alice = Downloads.download(
          "https://www.gutenberg.org/files/11/11-0.txt", "alice.txt")
time  = Downloads.download(
          "https://www.gutenberg.org/files/35/35-0.txt", "time_machine.txt")

cfg = PreprocessConfiguration(tokenizer_name = :whitespace)

merged = preprocess_corpus_streaming_full(
           [alice, time];           # any iterable of sources
           cfg          = cfg,
           chunk_tokens = 5_000)    # ~5 k tokens per internal chunk

println("total tokens:",
        length(get_token_ids(merged, :word)))
```

`preprocess_corpus_streaming_full` runs the two-pass streaming pipeline,
merges all internal chunks on the fly, and returns **one cohesive bundle**
covering the entire corpus—ideal when downstream code expects a single artefact
yet you still need strict memory bounds during preprocessing.

---

# Installing

open the Julia REPL, get into package mode pressing ] and put: add https://github.com/mantzaris/KeemenaPreprocessing.jl