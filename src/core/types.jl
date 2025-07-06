

"""
    PipelineMetadata

Compact header bundled with every artefact produced by **KeemenaPreprocessing**.
It records the exact pipeline settings and the version of the on-disk schema so
that data can be re-processed, inspected, or migrated safely.

## Fields
* `configuration::PreprocessConfiguration`  
  The full set of cleaning, tokenisation, vocabulary, and offset-recording
  options that generated the artefact.  Storing this ensures strict
  reproducibility.

* `schema_version::VersionNumber`  
  The version of the **bundle file format** (not the Julia package).  
  Increment the **major** component when breaking changes are introduced so
  that loaders can detect incompatibilities and perform migrations or raise
  errors.

## Example
```julia
cfg  = PreprocessConfiguration(strip_html_tags = true)
meta = PipelineMetadata(cfg, v"1.0.0")

@info "tokeniser:" meta.configuration.tokenizer_name
@assert meta.schema_version >= v"1.0.0"
```
"""
struct PipelineMetadata
    configuration :: PreprocessConfiguration #cleaning and tokeniser params
    schema_version:: VersionNumber
end

"""
    PipelineMetadata() -> PipelineMetadata

Convenience constructor that returns a metadata header with

* the **default** `PreprocessConfiguration()` (all keyword-arguments left at
  their documented defaults); and
* the current bundle **schema version** `v"1.0.0"`.

Handy for rapid prototyping or unit tests when you do not need to customise the
pipeline but still require a valid `PipelineMetadata` object.

Identical to:

```julia
PipelineMetadata(PreprocessConfiguration(), v"1.0.0")
```
"""
PipelineMetadata() = PipelineMetadata(PreprocessConfiguration(), v"1.0.0")


"""
    Vocabulary

Immutable lookup table produced by `build_vocabulary` that maps between
integer **token-ids** and the string literals that appear in a corpus.

## Fields
* `id_to_token_strings::Vector{String}`  
  Position `i` holds the *canonical* surface form of token-id `i`
  (`vocab.id_to_token_strings[id]` → `"word"`).

* `token_to_id_map::Dict{String,Int}`  
  Fast reverse mapping from token string to its integer id
  (`vocab.token_to_id_map["word"]` → `id`).  
  Look-ups fall back to the `<UNK>` id when the string is absent.

* `token_frequencies::Vector{Int}`  
  Corpus counts aligned with `id_to_token_strings`
  (`token_frequencies[id]` gives the raw frequency of that token).

* `special_tokens::Dict{Symbol,Int}`  
  Set of reserved ids for sentinel symbols such as
  `:unk`, `:pad`, `:bos`, `:eos`, …  
  Keys are **roles** (`Symbol`); values are the corresponding integer ids.

## Usage example
```julia
vocab = build_vocabulary(tokens; minimum_token_frequency = 3)

@info "UNK id:    " vocab.special_tokens[:unk]
@info "«hello» id:" vocab.token_to_id_map["hello"]
@info "id → token:" vocab.id_to_token_strings[42]
```
"""
struct Vocabulary
    id_to_token_strings :: Vector{String}
    token_to_id_map     :: Dict{String,Int}
    token_frequencies   :: Vector{Int}
    special_tokens      :: Dict{Symbol,Int}
end


"""
    Corpus

Flat, memory-efficient container that stores an entire corpus of token-ids
together with optional hierarchical **offset tables** that recover the original
structure (documents → paragraphs → sentences → words → characters → bytes).

Every offset vector records the **starting index** (1-based, inclusive) of each
unit inside `token_ids`.  The final entry therefore equals
`length(token_ids)+1`, making range retrieval convenient via
`view(token_ids, offsets[i] : offsets[i+1]-1)`.

## Fields
| field | type | always present? | description |
|-------|------|-----------------|-------------|
| `token_ids` | `Vector{Int}` | ✓ | Concatenated token identifiers returned by the vocabulary. |
| `document_offsets` | `Vector{Int}` | ✓ | Start positions of each **document** (outermost level). |
| `paragraph_offsets` | `Union{Vector{Int},Nothing}` | cfg-dependent | Paragraph starts within each document when `record_paragraph_offsets=true`. |
| `sentence_offsets` | `Union{Vector{Int},Nothing}` | cfg-dependent | Sentence boundaries when `record_sentence_offsets=true`. |
| `word_offsets` | `Union{Vector{Int},Nothing}` | cfg-dependent | Word boundaries when `record_word_offsets=true`. |
| `character_offsets` | `Union{Vector{Int},Nothing}` | cfg-dependent | Unicode-character spans when `record_character_offsets=true`. |
| `byte_offsets` | `Union{Vector{Int},Nothing}` | cfg-dependent | Byte-level spans when `record_byte_offsets=true`. |

## Example
```julia
# assume `corp` is a Corpus produced by preprocess_corpus
doc1_range = corp.document_offsets[1] : corp.document_offsets[2]-1
doc1_token_ids = view(corp.token_ids, doc1_range)

if corp.sentence_offsets ≠ nothing
    first_sentence = view(corp.token_ids,
                          corp.sentence_offsets[1] : corp.sentence_offsets[2]-1)
end
```

The presence or absence of each optional offsets vector is determined entirely
by the corresponding `record_*_offsets` flags in
[`PreprocessConfiguration`](@ref).
"""
struct Corpus
    token_ids          :: Vector{Int}
    document_offsets   :: Vector{Int}
    paragraph_offsets  :: Union{Vector{Int},Nothing}
    sentence_offsets   :: Union{Vector{Int},Nothing}
    word_offsets       :: Union{Vector{Int},Nothing}
    character_offsets  :: Union{Vector{Int},Nothing}
    byte_offsets       :: Union{Vector{Int},Nothing}
end


"""
    LevelBundle

Self-contained pairing of a [`Corpus`](@ref) and its companion
[`Vocabulary`](@ref).  A `LevelBundle` represents **one segmentation level**
(e.g. words, characters, or bytes) produced by the preprocessing pipeline.
By storing both objects side-by-side it guarantees that every `token_id`
found in `corpus.token_ids` is valid according to `vocabulary`.

## Fields
* `corpus     :: Corpus`  
  All token-ids plus optional offset tables describing the structure of the
  text at this level.

* `vocabulary :: Vocabulary`  
  Bidirectional mapping between token strings and the integer ids used in
  `corpus.token_ids`.

## Integrity checks
The inner constructor performs two runtime validations:

1. **Range check** - the largest token-id must not exceed
   `length(vocabulary.id_to_token_strings)`.
2. **Lower bound** - all token-ids must be >= 1 (id 0 is never legal).

Violations raise an informative `ArgumentError`, catching mismatches early.

## Example
```julia
word_corpus  = Corpus(word_ids, doc_offs, nothing, sent_offs, word_offs,
                      nothing, nothing)
word_vocab   = build_vocabulary(words; minimum_token_frequency = 2)

word_bundle  = LevelBundle(word_corpus, word_vocab)

nb_tokens    = length(word_bundle.vocabulary.id_to_token_strings)
@info "bundle contains nb_tokens unique tokens"
```
"""
struct LevelBundle
    corpus     :: Corpus
    vocabulary :: Vocabulary
    
    #inner constructor for validation
    function LevelBundle(corp::Corpus, vocab::Vocabulary)
        if !isempty(corp.token_ids)
            max_id = maximum(corp.token_ids)
            max_id > length(vocab.id_to_token_strings) &&
                error("Corpus contains token ID $max_id but vocabulary has only $(length(vocab.id_to_token_strings)) tokens")
            minimum(corp.token_ids) < 1 &&
                error("Token IDs must be >= 1")
        end
        new(corp, vocab)
    end
end


"""
    CrossMap

Alignment table that links two segmentation levels of the same corpus
(e.g. **bytes -> characters**, **characters -> words**, **words -> sentences**).

For every unit in the *destination* level the `alignment` vector stores the
1-based **index into the source offsets** at which that unit begins.
This allows constant-time projection of any span expressed in destination
units back to the finer-grained source sequence.

## Fields
* `source_level      :: Symbol`  
  Name of the *finer* level (must match a key in `bundle.levels`,
  typically `:byte`, `:char`, `:word`, `:sentence`, or `:paragraph`).

* `destination_level :: Symbol`  
  Name of the *coarser* level whose boundaries are encoded.

* `alignment         :: Vector{Int}`  
  Length = `N_destination + 1`.  
  `alignment[i]` is the starting source-level offset of destination element `i`;
  the extra sentinel entry `alignment[end] = N_source + 1` lets you slice with  
  `alignment[i] : alignment[i+1]-1` without bounds checks.

## Example
```julia
# map words ⇒ sentences
m = CrossMap(:word, :sentence, sent2word_offsets)

first_sentence_word_ids = alignment_view(m, 1)  # helper returning a view
```

The constructor is trivial and performs no validation; pipelines are expected
to guarantee consistency when emitting `CrossMap` objects.
"""
struct CrossMap
    source_level      :: Symbol
    destination_level :: Symbol
    alignment         :: Vector{Int}
end


"""
    CrossMap(src, dst, align)

Shorthand outer constructor that builds a [`CrossMap`](@ref) while **materialising
the alignment vector as `Vector{Int}`**.

Arguments
----------
* `src::Symbol` - identifier of the *source* (finer-grained) level  
  (e.g. `:char`, `:word`).

* `dst::Symbol` - identifier of the *destination* (coarser) level  
  (e.g. `:word`, `:sentence`).

* `align::AbstractVector{<:Integer}` - offset array mapping every destination
  unit to its starting position in the source sequence.  Any integer-typed
  vector is accepted; it is copied into a dense `Vector{Int}` to guarantee
  contiguous storage and type stability inside the resulting `CrossMap`.

Returns
-------
A `CrossMap(src, dst, Vector{Int}(align))`.

### Example
```julia
cm = CrossMap(:char, :word, UInt32[1, 5, 9, 14])
@assert cm.alignment isa Vector{Int}
```
"""
CrossMap(src::Symbol, dst::Symbol, align::AbstractVector{<:Integer}) =
    CrossMap(src, dst, Vector{Int}(align))


"""
    PreprocessBundle{ExtraT}

Top-level artefact emitted by `preprocess_corpus` (or the streaming variant).
A bundle contains everything required to feed a downstream model or to reload
a corpus without re-running the expensive preprocessing pipeline.

## Type parameter
* `ExtraT` - arbitrary payload for user-defined information (e.g. feature
  matrices, clustering assignments, language tags).  Use `Nothing` when no
  extras are needed.

## Fields
| field | type | description |
|-------|------|-------------|
| `levels` | `Dict{Symbol,LevelBundle}` | Mapping from segmentation level name (`:byte`, `:char`, `:word`, `:sentence`, `:paragraph`, …) to the corresponding [`LevelBundle`](@ref). |
| `metadata` | [`PipelineMetadata`](@ref) | Reproducibility header (configuration + schema version). |
| `alignments` | `Dict{Tuple{Symbol,Symbol},CrossMap}` | Pair-wise offset projections between levels, keyed as `(source, destination)` (e.g. `(:char, :word)`). |
| `extras` | `ExtraT` | Optional user payload carried alongside the core data. |

## Typical workflow
```julia
bund = preprocess_corpus(files; strip_html_tags=true)

# inspect vocabulary
word_vocab = bund.levels[:word].vocabulary
println("vocabulary size: ", length(word_vocab.id_to_token_strings))

# project a sentence span back to character offsets
cm = bund.alignments[(:char, :sentence)]
first_sentence_char_span = cm.alignment[1] : cm.alignment[2]-1
```

The bundle is immutable; to add additional levels or extras create a fresh
instance (helper functions `add_level!`, `with_extras`, etc. are provided by
the package).
"""
struct PreprocessBundle{ExtraT}
    levels     :: Dict{Symbol,LevelBundle}
    metadata   :: PipelineMetadata
    alignments :: Dict{Tuple{Symbol,Symbol},CrossMap}
    extras     :: ExtraT
end


##############
# Constructors


"""
`LEVEL_TO_OFFSETS_FIELD`

Lookup table that converts a segmentation-level identifier to the **field name**
inside a [`Corpus`](@ref) where the start-offset vector for that level is
stored.

| level symbol | corpus field accessed |
|--------------|----------------------|
| `:byte`      | `:byte_offsets`      |
| `:character` | `:character_offsets` |
| `:word`      | `:word_offsets`      |
| `:sentence`  | `:sentence_offsets`  |
| `:paragraph` | `:paragraph_offsets` |
| `:document`  | `:document_offsets`  |

### Example
```julia
lvl   = :word
field = LEVEL_TO_OFFSETS_FIELD[lvl]       # => :word_offsets
offs  = getfield(corpus, field)           # Vector{Int} with word boundaries
```

Using this constant avoids fragile string or symbol concatenations when you
need to inspect or slice a corpus programmatically.
"""
const LEVEL_TO_OFFSETS_FIELD = Dict(
    :byte      => :byte_offsets,
    :character => :character_offsets,
    :word      => :word_offsets,
    :sentence  => :sentence_offsets,
    :paragraph => :paragraph_offsets,
    :document  => :document_offsets
)


"""
    PreprocessBundle(levels; metadata = PipelineMetadata(),
                          alignments = Dict{Tuple{Symbol,Symbol},CrossMap}(),
                          extras = nothing) -> PreprocessBundle

Outer constructor that **validates** and assembles the individual artefacts
generated by `KeemenaPreprocessing` into a single [`PreprocessBundle`](@ref).

### Required argument
* `levels::Dict{Symbol,<:LevelBundle}` - at least one segmentation
  level (keyed by level name such as `:word` or `:char`).

### Optional keyword arguments
| keyword | default | purpose |
|---------|---------|---------|
| `metadata` | `PipelineMetadata()` | Configuration & schema header. |
| `alignments` | empty `Dict` | Maps `(source,destination) -> CrossMap`. |
| `extras` | `nothing` | User-supplied payload propagated unchanged. |

### Runtime checks
1. **Non-empty** `levels`.
2. For each `(lvl, lb)` in `levels` run `validate_offsets(lb.corpus, lvl)` to
   ensure internal offset consistency.
3. For every supplied alignment `(src,dst) → cm`:
   * both `src` and `dst` must exist in `levels`;
   * `length(cm.alignment) == length(levels[src].corpus.token_ids)`;
   * `cm.source_level      == src`;
   * `cm.destination_level == dst`.

Any violation throws an informative `ArgumentError`.

### Returns
A fully-validated `PreprocessBundle{typeof(extras)}` containing:
`Dict(levels)`, `metadata`, `Dict(alignments)`, and `extras`.

### Example
```julia
word_bundle = LevelBundle(word_corpus, word_vocab)
char_bundle = LevelBundle(char_corpus, char_vocab)

bund = PreprocessBundle(Dict(:word=>word_bundle, :char=>char_bundle);
                        alignments = Dict((:char,:word)=>char2word_map))
```
"""
function PreprocessBundle(levels::Dict{Symbol,<:LevelBundle};
                          metadata   :: PipelineMetadata = PipelineMetadata(),
                          alignments :: Dict{Tuple{Symbol,Symbol},<:CrossMap} = Dict{Tuple{Symbol,Symbol},CrossMap}(),
                          extras = nothing)

    isempty(levels) && error("At least one LevelBundle is required")

    # level-wise validation
    for (lvl, lb) in levels
        validate_offsets(lb.corpus, lvl)
    end

    # alignment validation
    for ((src,dst), cm) in alignments
        haskey(levels, src) || error("Alignment source :$src not found")
        haskey(levels, dst) || error("Alignment destination :$dst not found")
        length(cm.alignment) == length(levels[src].corpus.token_ids) ||
            error("Alignment $src→$dst length mismatch")
        cm.source_level == src || error("CrossMap source_level mismatch")
        cm.destination_level == dst || error("CrossMap destination_level mismatch")
    end

    PreprocessBundle{typeof(extras)}(
        Dict(levels), metadata, Dict(alignments), extras
    )
end


"""
    PreprocessBundle(; metadata = PipelineMetadata(), extras = nothing) -> PreprocessBundle

Convenience constructor that produces an **empty** [`PreprocessBundle`](@ref):

* `levels     = Dict{Symbol,LevelBundle}()`  
* `alignments = Dict{Tuple{Symbol,Symbol},CrossMap}()`  
* `metadata   = metadata` (defaults to `PipelineMetadata()`)  
* `extras     = extras`   (defaults to `nothing`)

Useful when you want to build a bundle **incrementally**—for example, loading
individual levels from disk or generating them in separate jobs: while still
attaching a common metadata header or arbitrary user payload.

```julia
bund = PreprocessBundle()                      # blank skeleton
bund = merge(bund, load_word_level("word.jld"))  # pseudo-code for adding data
```

The returned object's type parameter is inferred from `extras` so that any
payload, including complex structs, can be stored without further boilerplate.
"""
PreprocessBundle(; metadata = PipelineMetadata(), extras = nothing) =
    PreprocessBundle{typeof(extras)}(Dict(), metadata, Dict{Tuple{Symbol,Symbol},CrossMap}(), extras)


"""
    validate_offsets(corpus, level_name)

Internal sanity-check used by the `PreprocessBundle` constructor.  
It verifies that the offset table recorded for segmentation level
`level_name` inside `corpus` is **present, consistent, and monotone**.

The routine is intentionally *silent* on success; it throws an
`ArgumentError` with a descriptive message when an inconsistency is found.

### Arguments
| argument | type | description |
|----------|------|-------------|
| `corpus` | [`Corpus`](@ref) | The corpus whose offsets are to be validated. |
| `level_name` | `Symbol` | The segmentation level to check (`:byte`, `:character`, `:word`, `:sentence`, `:paragraph`, or `:document`). |

### Validation rules
1. **Skip rules**  
   * If `level_name == :document` no strict checks are applied (documents may
     span multiple tokens per offset).  
   * If `level_name` has no dedicated offsets field (e.g. custom level) or that
     field is `nothing`, the function returns immediately.

2. **Token count match**  
   `length(corpus.token_ids) == length(offsets) - 1`  
   Ensures there is exactly one offset per token plus the sentinel end marker.

3. **Strict monotonicity**  
   `issorted(offsets, lt = <)`  
   Offsets must be strictly increasing so that every span
   `offsets[i] : offsets[i+1]-1` is well-defined.

### Errors
Throws `ArgumentError` when any of the above invariants is violated.

### Example
```julia
validate_offsets(bundle.levels[:word].corpus, :word)  # no output on success
```
"""
function validate_offsets(corpus::Corpus, level_name::Symbol)
    # 1-token-per-offset invariants
    level_name === :document && return

    field = get(LEVEL_TO_OFFSETS_FIELD, level_name, nothing)
    field === nothing && return                    # level has no dedicated offsets field

    offsets = getfield(corpus, field)
    offsets === nothing && return                  # offsets not recorded for this level


    # The number of tokens at a given level should correspond to the number of
    # offset segments.
    expected_tokens = length(offsets) - 1
    if length(corpus.token_ids) != expected_tokens
        error("Corpus for level :$level_name has $(length(corpus.token_ids)) tokens, but its offsets define $expected_tokens segments.")
    end

    # The offsets must still be strictly increasing.
    issorted(offsets, lt = <) ||
        error("Offsets for level :$level_name must be strictly increasing")

end


"""
    has_level(bundle, level) -> Bool

Return `true` if the given `PreprocessBundle` contains a
`LevelBundle` for the segmentation level `level`
(e.g. `:byte`, `:word`, `:sentence`); otherwise return `false`.

# Arguments
- `bundle::PreprocessBundle` — bundle to inspect.
- `level::Symbol`            — level identifier to look for.

# Example
```julia
julia> has_level(bund, :word)
true
```
"""
has_level(bundle::PreprocessBundle, level::Symbol) = haskey(bundle.levels, level)


"""
    get_level(bundle, level) → LevelBundle

Fetch the `LevelBundle` associated with segmentation level `level`
from a `PreprocessBundle`.

# Arguments
* `bundle::PreprocessBundle` — bundle returned by `preprocess_corpus`.
* `level::Symbol` — identifier such as `:byte`, `:word`, `:sentence`, ...

# Returns
The requested `LevelBundle`.

# Errors
Throws an `ArgumentError` when the level is absent, listing all available
levels to aid debugging.

# Example
```julia
word_bundle = get_level(bund, :word)
println("vocabulary size: ", length(word_bundle.vocabulary.id_to_token_strings))
```
"""
function get_level(bundle::PreprocessBundle, level::Symbol)
    if !has_level(bundle, level)
        error("Level $level is not present in this bundle. Available levels: $(keys(bundle.levels))")
    end
    bundle.levels[level]
end


"""
    get_corpus(bundle, level) -> Corpus

Retrieve the `Corpus` object for segmentation level `level`
from a `PreprocessBundle`.

This is equivalent to `get_level(bundle, level).corpus` and is provided
as a convenience helper when you only need the sequence of token-ids and
offset tables rather than the whole `LevelBundle`.

# Arguments
- `bundle::PreprocessBundle` - bundle produced by `preprocess_corpus`.
- `level::Symbol` - level identifier such as `:byte`, `:word`, `:sentence`, ...

# Returns
The `Corpus` stored in the requested level.

# Errors
Throws an `ArgumentError` if the level is not present in `bundle`
(see `get_level` for details).

# Example
```julia
word_corp = get_corpus(bund, :word)

# iterate over sentences
sent_offs = word_corp.sentence_offsets
for i in 1:length(sent_offs)-1
    rng = sent_offs[i] : sent_offs[i+1]-1
    println(view(word_corp.token_ids, rng))
end
```
"""
get_corpus(bundle::PreprocessBundle, level::Symbol) = get_level(bundle, level).corpus


"""
    get_vocabulary(bundle, level) -> Vocabulary

Return the `Vocabulary` associated with segmentation level `level`
(eg `:byte`, `:word`, `:sentence`) from a given `PreprocessBundle`

Effectively a shorthand for  
`get_level(bundle, level).vocabulary`

# Arguments
- `bundle::PreprocessBundle` - Bundle produced by `preprocess_corpus`
- `level::Symbol` — Level identifier whose vocabulary you need

# Returns
The `Vocabulary` stored for `level`

# Errors
Raises an `ArgumentError` if `level` is not present in `bundle`
(see `get_level` for details)

# Example
```julia
vocab = get_vocabulary(bund, :word)
println("Top-10 tokens: ", vocab.id_to_token_strings[1:10])
```
"""
get_vocabulary(bundle::PreprocessBundle, level::Symbol) = get_level(bundle, level).vocabulary


"""
    get_token_ids(bundle, level) -> Vector{Int}

Return the vector of **token-ids** for segmentation level `level`
contained in a `PreprocessBundle`.

Identical to  
`get_corpus(bundle, level).token_ids`,  
but provided as a convenience helper when you only need the raw id
sequence and not the full `Corpus` object.

# Arguments
- `bundle::PreprocessBundle` - bundle produced by `preprocess_corpus`.
- `level::Symbol` - segmentation level identifier (e.g. `:byte`, `:word`).

# Returns
A `Vector{Int}` whose length equals the number of tokens at that level.

# Errors
Throws an `ArgumentError` if the requested level is absent
(see `get_level` for details).

# Example
```julia
word_ids = get_token_ids(bund, :word)
println("first ten ids: ", word_ids[1:10])
```
"""
get_token_ids(bundle::PreprocessBundle, level::Symbol) = get_corpus(bundle, level).token_ids


"""
    add_level!(bundle, level, lb) -> PreprocessBundle

Mutating helper that inserts a new `LevelBundle` `lb` into
`bundle.levels` under key `level`.  The routine:

1. **Guards against duplicates** - throws an error if `level` already exists.  
2. **Validates** the offsets inside `lb.corpus` for consistency with
   the supplied level via `validate_offsets`.  
3. Stores the bundle and returns the **same** `bundle` instance so the call
   can be chained.

be aware that, `add_level!` modifies its first argument **in place**; if you require
    an immutable bundle keep a copy before calling

# Arguments
| name | type | description |
|------|------|-------------|
| `bundle` | `PreprocessBundle` | Target bundle to extend. |
| `level`  | `Symbol` | Identifier for the new segmentation level (e.g. `:char`, `:word`). |
| `lb`     | `LevelBundle` | Data + vocabulary for that level. |

# Returns
The same `bundle`, now containing `level => lb`.

# Errors
* `ArgumentError` if a level with the same name already exists.
* Propagates any error raised by `validate_offsets` when `lb.corpus`
  is inconsistent.

# Example
```julia
char_bundle = LevelBundle(char_corp, char_vocab)
add_level!(bund, :character, char_bundle)

@assert has_level(bund, :character)
```
"""
function add_level!(bundle::PreprocessBundle, level::Symbol, lb::LevelBundle)
    haskey(bundle.levels, level) && error("Level :$level already exists")
    validate_offsets(lb.corpus, level)
    bundle.levels[level] = lb
    return bundle
end


"""
    with_extras(original, new_extras) -> PreprocessBundle

Create a **shallow copy** of `original` where only the `extras` field is
replaced by `new_extras`.  All other components (`levels`, `metadata`,
`alignments`) are cloned by reference, so the operation is cheap and the
returned bundle remains consistent with the source.

Useful when you have performed post-processing (e.g. dimensionality reduction,
cluster assignments, per-document labels) and want to attach the results
without mutating the original bundle in place.

# Arguments
| name | type | description |
|------|------|-------------|
| `original` | `PreprocessBundle` | Bundle produced by `preprocess_corpus`. |
| `new_extras` | `Any` | Arbitrary payload to store under `bundle.extras`. |

# Returns
A new `PreprocessBundle{typeof(new_extras)}` identical to `original`
except that `extras == new_extras`.

# Example
```julia
labels = collect(kmeans(doc_embeddings, 50).assignments)
labeled = with_extras(bund, labels)

@assert labeled.levels === bund.levels         # same reference
@assert labeled.extras === labels              # updated payload
```
"""
function with_extras(original::PreprocessBundle, new_extras)
    PreprocessBundle(original.levels;
                     metadata   = original.metadata,
                     alignments = original.alignments,
                     extras     = new_extras)
end


Base.iterate(bundle::PreprocessBundle) = iterate(bundle.levels)
Base.iterate(bundle::PreprocessBundle, state) = iterate(bundle.levels, state)
Base.length(bundle::PreprocessBundle) = length(bundle.levels)
Base.keys(bundle::PreprocessBundle) = keys(bundle.levels)
Base.values(bundle::PreprocessBundle) = values(bundle.levels)


Base.length(cm::CrossMap)      = length(cm.alignment)
Base.getindex(cm::CrossMap, i) = cm.alignment[i]
Base.show(io::IO, cm::CrossMap) =
    print(io, "CrossMap ", cm.source_level, "→", cm.destination_level,
               " (", length(cm), " entries)")


function Base.show(io::IO, bundle::PreprocessBundle)
    print(io, "PreprocessBundle with $(length(bundle.levels)) level(s): ")
    print(io, join(keys(bundle.levels), ", "))
end


function Base.show(io::IO, ::MIME"text/plain", bundle::PreprocessBundle)
    println(io, "PreprocessBundle:")
    println(io, "  Levels: ", join(keys(bundle.levels), ", "))
    println(io, "  Schema: ", bundle.metadata.schema_version)
    if bundle.extras !== nothing
        println(io, "  Extras: ", typeof(bundle.extras))
    end
    
    for (level, lb) in bundle.levels
        println(io, "\n  Level :$level")
        println(io, "    Tokens: ", length(lb.corpus.token_ids))
        println(io, "    Vocabulary size: ", length(lb.vocabulary.id_to_token_strings))
        println(io, "    Documents: ", length(lb.corpus.document_offsets) - 1)
    end
end

