---
title: "KeemenaPreprocessing.jl: Unicode-Robust Cleaning, Multi-Level Tokenisation & Streaming Offset Bundling for Julia NLP"
tags:
  - Julia
  - NLP
  - Text Processing
  - Tokenization
  - Corpus Cleaning
authors:
  - name: "Alexander V. Mantzaris"
    orcid: 0000-0002-0026-5725
    affiliation: 1
affiliations:
  - name: "Department of Statistics and Data Science, University of Central Florida (UCF), USA"
    index: 1
date: July 7 2025
bibliography: paper.bib
---


# Summary

KeemenaPreprocessing.jl begins where raw text first enters a research workflow, applying a carefully chosen set of cleaning operations that work well for most corpora yet remain fully customisable.  By default the toolkit lower-cases characters, folds accents, removes control glyphs, normalises whitespace, and replaces URLs, e-mails, and numbers by sentinel tokens; each rule may be toggled individually through an optional `PreprocessConfiguration`, so users can disable lower-casing for case-sensitive tasks or preserve digits for OCR evaluation without rewriting the pipeline.  

After cleaning, the same configuration drives tokenisation.  Keemena ships byte-, character-, and word-level tokenisers and will seamlessly wrap a user-supplied function—allowing, for instance, a spaCy segmentation pass when language-specific heuristics are required [@honnibal2020spacy].  Multiple tokenisers can operate in one sweep, so a single corpus pass can yield both sub-word pieces for a language model and whitespace tokens for classical bag-of-words features.  Each token stream is accompanied by dense offset vectors: words are anchored to their byte and character positions, sentences and paragraphs are delimited explicitly, and a cross-alignment table keeps byte <-> char <-> word mappings exact.  This design guarantees that every higher-level span can be traced unambiguously back to the source bytes, a property indispensable for annotation projection and reversible data augmentation.  

All artefacts—clean strings, token-ids, offset vectors, vocabulary statistics, and alignment tables are consolidated into a single `PreprocessBundle`.  The bundle can be saved or loaded with one function call using the JLD2 format, making it a drop-in dependency for downstream embedding or language-model pipelines inspired by word2vec [@mikolov2013efficient].  For modest datasets, the entire pipeline executes in a single statement; for web-scale corpora, KeemenaPreprocessing's streaming mode processes fixed-size token chunks in constant memory while still accumulating global frequency tables.  Thus, whether invoked with default settings for a quick experiment or finely tuned for production, KeemenaPreprocessing.jl offers a cohesive, Julia-native path from raw text to analysis-ready data [@julia]. Many of these principles are introduced in [@bird2009natural];


# Statement of Need

Natural-language ML pipelines depend on reliable, reproducible preprocessing. Popular toolkits such as spaCy [@honnibal2020spacy], Stanford CoreNLP [@manning2014stanford], and Gensim [@vrehuuvrek2010software] are Python or Java-centric, require heavyweight installations, and assume the full corpus fits in memory or on a local filesystem. While WordTokenizers.jl provides basic tokenisation for Julia [@kaushal2020wordtokenizers], Julia users still lack an integrated, streaming pipeline that:

- Scales beyond RAM through chunked streaming.

- Tracks fine-grained offsets so models can mix sub-word and sentence-level features.

- Lives entirely in Julia, avoiding Python/Java dependencies and enabling zero-copy interop with Julia's numerical stack.

KeemenaPreprocessing.jl fills this gap, letting researchers preprocess billions of tokens on commodity hardware while retaining compatibility with embedding or language-model training workflows inspired by word2vec [@mikolov2013efficient]. 


# Acknowledgements

Thanks to the Julia community for their continued support of open-source scientific computing.

# References