# [Using KeemenaPreprocessing with existing tokenizers](@id guide_existing_tokenizers)

KeemenaPreprocessing is not a tokenizer collection and it is not a general NLP toolkit.
Instead, it is a preprocessing pipeline: you choose how to tokenize, and KeemenaPreprocessing builds a deterministic `PreprocessBundle` (tokens + vocabulary + offsets + cross-level alignments) for downstream modeling, annotation, and evaluation.

If you want a lightweight custom tokenizer function (no external dependencies), see [Quick Start: Supplying a custom tokenizer function](@ref quickstart_custom_tokenizer).

This page shows how to use existing tokenizer packages (eg WordTokenizers.jl, BytePairEncoding.jl) without KeemenaPreprocessing taking hard dependencies on them. KeemenaPreprocessing also ships a small set of built-in tokenizers (`:whitespace`, `:unicode`, `:byte`, `:char`) for convenience with various configurations that should work in most instances.

- :word is the canonical key for the primary string-token stream produced by tokenizer_name (whitespace tokens, BPE pieces, grapheme clusters, etc)
- :character is the canonical key for the Unicode scalar-value stream (codepoints) when recorded
- :byte is the canonical key for the UTF-8 byte stream when recorded.

---

## Why callables (avoid hard dependencies)

KeemenaPreprocessing accepts tokenizers as callables rather than integrating tightly with any single tokenization ecosystem:

- Reproducibility: the tokenizer behavior is pinned inside your `PreprocessConfiguration`, rather than being controlled by hidden global defaults.
- Avoid global state surprises: some tokenizer packages expose globally configurable defaults (changing them can affect other code in the same Julia session)
- API stability: upstream tokenizers evolve; a minimal callable interface keeps KeemenaPreprocessing stable and reduces breakage risk.
- Separation of concerns: KeemenaPreprocessing focuses on streaming execution, offsets, alignment, and deterministic artifacts, not on maintaining feature parity with every tokenizer. (See [Built-in tokenizers](@ref built_in_tokenizers))

---

## Tokenizer interface contract

`PreprocessConfiguration(tokenizer_name = ...)` accepts either:

- a built-in symbol (`:whitespace`, `:unicode`, `:byte`, `:char`), or
- a custom callable `tokenizer(::AbstractString) -> Vector{<:AbstractString}`.

In other words:

```julia
tokens = tokenizer(text::AbstractString)
# tokens must be a Vector of strings (String, SubString{String}, etc.)
```

---

## Canonical level naming

KeemenaPreprocessing uses canonical level keys in the returned bundle:

- `:word` is the canonical key for the primary string-token stream (this includes subword pieces such as BPE).
- `:character` is used for grapheme-level tokenization (`tokenizer_name = :char`).
- `:byte` is used for raw UTF-8 bytes (`tokenizer_name = :byte`).


```julia
word_corpus = get_corpus(bundle, :word)
char_corpus = get_corpus(bundle, :character)
byte_corpus = get_corpus(bundle, :byte)
```

---

## WordTokenizers.jl (concrete examples)

WordTokenizers.jl exports multiple explicit tokenizers such as `nltk_word_tokenize`, `toktok_tokenize`, `penn_tokenize`, and others.

### Note on global configuration

WordTokenizers allows changing global defaults via `set_tokenizer(...)` and `set_sentence_splitter(...)`.
Changing these defaults can affect other packages (or other parts of your code) that call `WordTokenizers.tokenize` or `WordTokenizers.split_sentences` using the global defaults.

For reproducible pipelines, prefer calling the tokenizer you want explicitly (as below).

### Example: NLTK-like word tokenization

```julia
using KeemenaPreprocessing
import WordTokenizers

# Wrap WordTokenizers output so we always return Vector{String}
function nltk_word_tokens_as_strings(text::AbstractString)::Vector{String}
    return String.(WordTokenizers.nltk_word_tokenize(text))
end

cfg = PreprocessConfiguration(
    tokenizer_name = nltk_word_tokens_as_strings,
    record_sentence_offsets = true,   # optional: record sentence boundaries
    minimum_token_frequency = 1,      # convenient for quick experiments
)

documents = [
    "Hello, world! This is a test.",
    "Email me at example@test.com and visit https://example.com.",
    "Don't split 3.14 weirdly; keep punctuation sensible."
]

bundle = preprocess_corpus(documents; config = cfg)

println("Levels present: ", collect(keys(bundle.levels)))
word_corpus = get_corpus(bundle, :word)
println("Number of tokens: ", length(word_corpus.token_ids))
```

### Example: Penn Treebank tokenizer

```julia
using KeemenaPreprocessing
import WordTokenizers

function penn_tokens_as_strings(text::AbstractString)::Vector{String}
    return String.(WordTokenizers.penn_tokenize(text))
end

cfg = PreprocessConfiguration(
    tokenizer_name = penn_tokens_as_strings,
    record_sentence_offsets = true,
    minimum_token_frequency = 1,
)

documents = [
    "Mr. Smith can't attend today; he's busy.",
    "She said: \"Tokenize this properly!\""
]

bundle = preprocess_corpus(documents; config = cfg)
println("Levels present: ", collect(keys(bundle.levels)))
```

---

## BytePairEncoding.jl (conceptual + practical examples)

BytePairEncoding.jl provides BPE tokenizers (including OpenAI-style tiktoken and GPT-2 byte-level BPE)

`BytePairEncoding.load_tiktoken(...)` returns a callable tokenizer object that yields `Vector{String}` token pieces

```julia
import BytePairEncoding

bpe = BytePairEncoding.load_tiktoken("cl100k_base")

println("Is Function? ", bpe isa Function)
println("Callable for AbstractString? ", applicable(bpe, "Hello world!"))

pieces = bpe("Hello world! This is BPE.")
println(pieces)
```

Output looks like subword-ish pieces (often including leading-space pieces like `" world"`).

### Recommended, wrap the callable object in a plain function

Some configurations validate `tokenizer_name` with `isa Function`. Since `BPETokenizer` is callable but not a `Function`, the most robust pattern is to wrap it:

```julia
using KeemenaPreprocessing
import BytePairEncoding

bpe = BytePairEncoding.load_tiktoken("cl100k_base")

# Wrap the callable struct in a plain function.
bpe_function(text::AbstractString)::Vector{String} = bpe(text)

cfg = PreprocessConfiguration(
    tokenizer_name = bpe_function,

    # Recommended for BPE: avoid splitting text before tokenization.
    # Many BPE tokenizers are sensitive to boundary context.
    record_sentence_offsets = false,
    record_paragraph_offsets = false,

    minimum_token_frequency = 1,
)

documents = [
    "Hello world! This is a test of BPE tokenization.",
    "Email me at example@test.com and visit https://example.com."
]

bundle = preprocess_corpus(documents; config = cfg)

println("Levels present: ", collect(keys(bundle.levels)))

# The primary string-token segmentation is retrieved as :word
subword_corpus = get_corpus(bundle, :word)
println("Number of BPE tokens: ", length(subword_corpus.token_ids))

subword_vocab = get_vocabulary(bundle, :word)
println("First 30 vocab strings: ", subword_vocab.id_to_token_strings[1:min(end, 30)])
```

Important: Keemena stores the primary string-token stream under `:word` even when the tokenizer returns subword pieces (BPE).

### byte and character offsets with BPE

KeemenaPreprocessing supports byte-level and character-level tokenization via built-in tokenizers:

- `tokenizer_name = :byte` for raw UTF-8 bytes (level `:byte`)
- `tokenizer_name = :char` for Unicode graphemes (level `:character`)

If you request `record_byte_offsets=true` or `record_character_offsets=true`, make sure your configuration and your KeemenaPreprocessing version support doing so with your chosen tokenizer.
If you are using a BPE tokenizer and you need explicit byte/character token streams, the simplest robust approach is often to run an additional preprocessing pass using `:byte` or `:char` (with the same cleaning settings) and keep that with your BPE-based `:word` stream.

---

## Getting token IDs from BytePairEncoding (encoder)

If you need the exact integer IDs used by a tiktoken-style encoder, BytePairEncoding can load an encoder separately:

```julia
import BytePairEncoding

enc = BytePairEncoding.load_tiktoken_encoder("cl100k_base")
ids = enc.encode("hello world")   # Vector{Int}
println(ids)
```


## Using a Python tokenizer

KeemenaPreprocessing accepts a tokenizer as a callable with the shape:

`tokenizer(text::AbstractString)::Vector{String}`

That callable can wrap a Python tokenizer via PythonCall.jl. This minimal example uses only Python's standard library (`re`), so it proves the Julia-Python bridge without requiring any external Python tokenizer packages.

```julia
using KeemenaPreprocessing
using PythonCall

@pyexec """
import re as _re
_pattern = _re.compile(r"\\w+|[^\\w\\s]", flags=_re.UNICODE)

def python_regex_tokenizer(text: str, _pattern=_pattern):
    return _pattern.findall(text)
""" => python_regex_tokenizer

python_regex_tokens(text::AbstractString)::Vector{String} =
    pyconvert(Vector{String}, python_regex_tokenizer(String(text)))

documents = [
    "Hello, world! This is a test.",
    "Email me at example@test.com and visit https://example.com.",
    "Mr. Smith can't attend today; he's busy.",
]

cfg = PreprocessConfiguration(
    tokenizer_name = python_regex_tokens,
    record_sentence_offsets = true,
    minimum_token_frequency = 1,
)

bundle = preprocess_corpus(documents; config = cfg)

println("Levels present: ", collect(keys(bundle.levels)))
println("Token count: ", length(get_corpus(bundle, :word).token_ids))
println("Sample tokens: ", python_regex_tokens(documents[3]))
```

The returned token stream is stored under Keemena's :word level.
Swapping in an existing Python tokenizer follows the same wrapper shape so only the Python callable changes.



## Python tokenizer via spaCy (python dependency)

KeemenaPreprocessing accepts a tokenizer callable with the shape:

`tokenizer(text::AbstractString)::Vector{String}`

Here is the same bridge pattern as the stdlib example, but using spaCy. This uses `spacy.blank("en")`, so it does not download any language models.

If spaCy is not installed in the Python environment used by PythonCall, the snippet prints a short suggestion to install it via Julia's CondaPkg manager.

```julia
using KeemenaPreprocessing
using PythonCall

# try to import spaCy (optional dependency)
python_spacy = nothing
try
    python_spacy = pyimport("spacy")
catch error
    println("spaCy is not available in PythonCall's Python environment")
    println("Install it using Julia's CondaPkg, then restart.")
    return
end

# a blank English pipeline (no model downloads)
python_spacy_pipeline = python_spacy.blank("en")

# Define a tiny Python helper that returns List[str]
@pyexec """
def spacy_tokens(nlp, text):
    doc = nlp(text)
    return [token.text for token in doc]
""" => spacy_tokens

python_spacy_tokens = spacy_tokens

# Wrap as a Julia callable matching Keemena's tokenizer contract
function spacy_blank_en_tokens(text::AbstractString)::Vector{String}
    python_tokens = python_spacy_tokens(python_spacy_pipeline, String(text))
    return pyconvert(Vector{String}, python_tokens)
end

documents = [
    "Hello, world! This is a test.",
    "Email me at example@test.com and visit https://example.com.",
    "Mr. Smith can't attend today; he's busy.",
]

cfg = PreprocessConfiguration(
    tokenizer_name = spacy_blank_en_tokens,
    record_sentence_offsets = true,
    minimum_token_frequency = 1,
)

bundle = preprocess_corpus(documents; config = cfg)

println("Levels present: ", collect(keys(bundle.levels)))
println("Token count: ", length(get_corpus(bundle, :word).token_ids))
println("Sample tokens: ", spacy_blank_en_tokens(documents[3]))
```

The returned token stream is stored under this package's :word level and you can swap with a different Python tokenizer by changing the Python callable.