# KeemenaPreprocessing

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
<!-- [![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://mantzaris.github.io/KeemenaPreprocessing.jl/stable/) -->
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://mantzaris.github.io/KeemenaPreprocessing.jl/dev/)
[![Build Status](https://github.com/mantzaris/KeemenaPreprocessing.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/mantzaris/KeemenaPreprocessing.jl/actions/workflows/CI.yml?query=branch%3Amain)

---



> **One-stop text pre-processor for Julia** - clean -> tokenise ->
segment -> build vocabulary -> align levels -> save bundle.

KeemenaPreprocessing.jl is a corpus-level preprocessing substrate for ML/NLP pipelines in Julia. It builds a deterministic PreprocessBundle from raw text using a streaming, two-pass workflow with predictable memory behavior.
The key output is a reproducible artifact: token id streams plus offset tables and cross-level alignments (byte/char/word/sentence/etc.) suitable for downstream modeling, annotation alignment, and evaluation.

Intended for:
- Researchers and engineers preprocessing large corpora for training or evaluating ML/NLP models.
- Workflows that need stable offsets/cross-references (for aligning spans, annotations, evaluation, error analysis).

Not ideally for:
- Users looking for a full NLP toolkit (tagging, parsing, NER, lemmatization, etc.).
- Users wanting a library that bundles many tokenizer implementations or enforces a specific tokenizer ecosystem.

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

## Scope and ecosystem

- KeemenaPreprocessing focuses on building a deterministic, aligned preprocessing artifact for downstream modeling
- Tokenizer packages (like WordTokenizers.jl) focus on fast sentence/word splitting and configurable tokenizers, including global configurability via set_tokenizer/set_sentence_splitter
- BPE/tokenizer-model packages (like BytePairEncoding.jl) focus on subword tokenization methods (including GPT-2 byte-level BPE and tiktoken)
- KemenaPreprocessing integrates with these via callables rather than hard dependencies, to avoid locking users into upstream conventions and to preserve reproducible pipelines

* Bundles (portable preprocessing artifacts)

  * everything is packed into a `PreprocessBundle` (plain Julia structs + arrays)
  * convenience persistence via JLD2 (`save_preprocess_bundle` / `load_preprocess_bundle`)
  * JLD2 is a default convenience backend, not a constraint:
    advanced users can serialize the bundle differently (e.g. HDF5/Arrow/custom layouts)
    if they need cross-language interchange, memory mapping, or indexed random access

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

It can be downloaded from the general registry: `import Pkg; Pkg.add("KeemenaPreprocessing")`, or pressing ']' and then typing `add KeemenaPreprocessing` and then back in the REPL prompt `using KeemenaPreprocessing`.

For the Dev version: open the Julia REPL, get into package mode pressing ] and put: add https://github.com/mantzaris/KeemenaPreprocessing.jl


---

# Contributing to KeemenaPreprocessing.jl

Feel free to contribute and collaboration is encouraged.

## How to contribute
### Reporting bugs
Please open a GitHub issue and include:
- Julia version
- KeemenaPreprocessing.jl version (from Project.toml or `Pkg.status()`)
- A minimal reproducible example
- Expected behavior vs actual behavior with the error messages

### Proposing changes
Open an issue first if the change is large or affects the public API, so we can agree on direction before doing all the work and finding out that a modified plan would have been better

### Pull requests
1. Fork the repository and create a feature branch
2. Keep pull requests focused (one logical change per PR) as it makes review easier
3. Add tests for bug fixes and new features and putting clear test names helps
4. Update documentation if behavior or API changes
5. Ensure CI is green


## Community guidelines
Please be respectful and constructive. This project follows the Julia Community Standards