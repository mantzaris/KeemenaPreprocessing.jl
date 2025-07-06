

# Quick Start

The **`preprocess_corpus`** wrapper lets you go from raw text -> cleaned, tokenised, aligned, and fully-packaged [`PreprocessBundle`](@ref) in one line.  
Its **only required argument is `sources`** (strings, file paths, URLs, or any iterable that mixes them). Everything else is optional.

| You pass… | What happens |
|-----------|--------------|
| *No* `config=` and *no* keywords | A fresh `PreprocessConfiguration` is created with all documented defaults. |
| **Keyword overrides** but *no* `config=` | A fresh configuration is built from the defaults **plus your overrides**. |
| **`config = cfg`** object | That exact configuration is used; keyword overrides are forbidden (ambiguity). |

---

## Minimal 'hello bundle' (all defaults)

```julia
using KeemenaPreprocessing

bund = preprocess_corpus("my_corpus.txt") #one-liner
@show bund.vocab_size
```

---

## Single *in-memory* string

```julia
raw = """
      It was a dark stormy night,
      And we see Sherlock Holmes.
      """

bund = preprocess_corpus(raw) # treats `raw` as a document
```

---

## Multiple strings (small ad-hoc corpus)

```julia
docs = [
    "Mary had a little lamb.",
    "Humpty-Dumpty sat on a wall.",
    """
    Roses are red,
    violets are blue
    """
]

bund = preprocess_corpus(docs;
                         tokenizer_name = :whitespace,
                         minimum_token_frequency = 2)
```


---

## Multiple **file paths**

```julia
sources = ["data/alice.txt",
           "data/time_machine.txt",
           "/var/corpora/news_2024.txt"]

bund = preprocess_corpus(sources; lowercase = false)
```

Directories in `sources` are **silently skipped**; mixing paths *and* raw strings is fine.


---

## Remote URLs

```julia
urls = [
    "https://www.gutenberg.org/files/11/11-0.txt",   # Alice
    "https://www.gutenberg.org/files/35/35-0.txt"    # Time Machine
]

bund = preprocess_corpus(urls;
                         tokenizer_name = :unicode,
                         record_sentence_offsets = true)
```


---

## Zero-configuration **byte-level** tokenisation

```julia
cfg  = byte_cfg()                 # shorthand helper
bund = preprocess_corpus("binary_corpus.bin", cfg)
```

---

## Saving and loading bundles

```julia
cfg   = PreprocessConfiguration(minimum_token_frequency = 5)
bund1 = preprocess_corpus("my_corpus.txt";
                          config  = cfg,
                          save_to = "corpus.jld2")

bund2 = load_preprocess_bundle("corpus.jld2")
```


---

## Alignments and `CrossMap` 

Every time you call `preprocess_corpus` (streaming or not) the helper  
`build_ensure_alignments!` **adds deterministic mappings between all recorded segmentation levels**:

* **Offset arrays** eg `bundle.levels[:word].corpus.sentence_offsets`.
* **`CrossMap`** : sparse look-up tables linking byte -> char -> word -> sentence indices

### a Inspecting offsets

```julia
wc = get_corpus(bund, :word)     # word-level Corpus
@show wc.sentence_offsets[1:10]  # sentinel-terminated, always sorted
```

### Byte -> word mapping for a single token

```julia
btw = bund.levels[:word].cross_map        # `CrossMap` object
byte_ix = 12345
word_ix = btw(byte_ix)    # constant-time lookup
```

### Convenience helpers

```julia
word_ix = alignment_byte_to_word(bund, byte_ix)
char_ix = alignment_byte_to_char(bund, byte_ix)
```

These helpers are thin wrappers over `CrossMap`, but keep your code independent of the underlying representation.


## Working with *multiple* segmentation levels

The pipeline can record **byte, character, word, sentence, paragraph, and document** offsets simultaneously.  
Just enable the flags you need in the configuration:

```julia
using KeemenaPreprocessing

cfg = PreprocessConfiguration(
          tokenizer_name            = :unicode,    # word-ish tokens
          record_byte_offsets       = true,
          record_character_offsets  = true,
          record_word_offsets       = true,
          record_sentence_offsets   = true,
          record_paragraph_offsets  = true,
          record_document_offsets   = true)

bund = preprocess_corpus("demo.txt"; config = cfg)

byte_corp = get_corpus(bund, :byte)        # each token is UInt8
char_corp = get_corpus(bund, :char)        # Unicode code-points
word_corp = get_corpus(bund, :word)        # words / graphemes
sent_offs = word_corp.sentence_offsets     # sentinel-terminated
para_offs = word_corp.paragraph_offsets
doc_offs  = word_corp.document_offsets

@show (byte_corp.token_ids[1:10],
       char_corp.token_ids[1:10],
       word_corp.token_ids[1:10])
```

By default every offset array is **sorted and sentinel-terminated** (`last == n_tokens + 1`), so it is safe to `searchsortedlast` or binary-search into them.

---

## Supplying a **custom tokenizer** function

Any callable `f(::AbstractString) -> Vector{String}` can replace the built-ins.  
Below we split on whitespace **and** the dash "‐" character:

```julia
using KeemenaPreprocessing

function dash_whitespace_tok(text::AbstractString)
    return split(text, r"[ \t\n\r\-]+", keepempty = false)
end

cfg = PreprocessConfiguration(
          tokenizer_name           = dash_whitespace_tok,    # <- callable
          minimum_token_frequency  = 2,
          record_word_offsets      = true)

docs  = ["state-of-the-art models excel",   # note the dashes
         "art-of-war is timeless"]

bund   = preprocess_corpus(docs; config = cfg)

# Inspect the custom tokenisation
wc = get_corpus(bund, :word)
@show map(tid -> wc.vocabulary.string(tid), wc.token_ids)
```

### Tips for custom tokenisers

| Requirement | Guideline |
|-------------|-----------|
| **Return type** | `Vector{<:AbstractString}` (no UInt8). |
| **No trimming** | If you want empty tokens preserved, call with `preserve_empty_tokens = true`. |
| **Offsets** | Only `:byte` and `:char` levels need special handling; `CrossMap` takes care of higher levels automatically. |


---

## pitfalls

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| Passing `config=` **and** keyword overrides | `ErrorException: Pass either config= or per-field keywords, not both.` | Pick one method; never both. |
| `record_paragraph_offsets = true` but `preserve_newlines = false` | Warning and paragraphs not recorded. | Enable `preserve_newlines` (done automatically with a warning). |
| Unsupported `tokenizer_name` symbol | `AssertionError` | Check [`TOKENIZERS`](@ref) or supply a callable. |

