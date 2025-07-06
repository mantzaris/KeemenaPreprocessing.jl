

module _Vocabulary


using StatsBase                # countmap
using ..KeemenaPreprocessing:  PreprocessConfiguration,
                               Vocabulary


"""
    build_vocabulary(tokens; cfg) → Vocabulary

Construct a [`Vocabulary`](@ref) from a corpus-wide list of **string tokens**.
The procedure is fully deterministic and guarantees that the resulting token
-> id mapping is *stable* across runs given the same inputs and configuration.

### Arguments
| name | type | description |
|------|------|-------------|
| `tokens` | `Vector{String}` | Flat sequence of corpus tokens (typically the output of `tokenize_and_segment`). |
| `cfg` | [`PreprocessConfiguration`](@ref) | Supplies frequency threshold (`minimum_token_frequency`) and the initial set of `special_tokens`. |

### Algorithm
1. **Frequency count** - `countmap(tokens)` to obtain *token → frequency*.
2. **Seed specials** - make a *mutable* copy of `cfg.special_tokens`.
3. **Dynamic specials** - when `cfg.record_sentence_offsets == true` ensure
   `:bos` / `:eos` markers are present (defaults `"<BOS>"`, `"<EOS>"`).
4. **Assign ids to specials**  
   * Sort special symbols alphabetically for reproducibility.  
   * Insert each literal into `id_to_tok`; update `tok_to_id`.
5. **Insert corpus tokens**  
   * Iterate corpus lexemes in sorted order.  
   * Skip any token already present (covers specials collisions).  
   * Skip tokens whose frequency `< cfg.minimum_token_frequency`.  
   * Append the rest, extending the id vectors.
6. **Frequency vector** - build `token_frequencies` aligned with `id_to_tok`
   (specials get `0` by convention).
7. **Specials id map** - convert `Symbol -> String` into `Symbol -> Int` by
   looking up the final ids.

### Returns
A fully-populated [`Vocabulary`](@ref):

* `id_to_token_strings :: Vector{String}`  
* `token_to_id_map     :: Dict{String,Int}`  
* `token_frequencies   :: Vector{Int}`  
* `special_tokens      :: Dict{Symbol,Int}`

### Examples
```julia
vocab = build_vocabulary(tokens; cfg = cfg)

@info "UNK id: "  vocab.special_tokens[:unk]
@info "«hello» frequency: " vocab.token_frequencies[vocab.token_to_id_map["hello"]]
```
"""
function build_vocabulary(tokens::Vector{String};
                          cfg::PreprocessConfiguration)

    # 1 token -> frequency
    freqs_dict = countmap(tokens)                     # Dict{String,Int}

    # 2 start from a mutable *copy* of user-supplied specials
    specials = Dict(cfg.special_tokens)               # Symbol -> String

    # 3 sentence markers (added only if needed)
    if cfg.record_sentence_offsets
        specials[:bos] = get(specials, :bos, "<BOS>")
        specials[:eos] = get(specials, :eos, "<EOS>")
    end

    id_to_tok = String[]
    tok_to_id = Dict{String,Int}()

    for sym in sort!(collect(keys(specials)))
        tok = specials[sym]
        push!(id_to_tok, tok)
        tok_to_id[tok] = length(id_to_tok)
    end

    # 5 add corpus tokens that meet the frequency threshold
    for tok in sort!(collect(keys(freqs_dict)))            # stable order
        f = freqs_dict[tok]
        (f < cfg.minimum_token_frequency || haskey(tok_to_id, tok)) && continue
        push!(id_to_tok, tok)
        tok_to_id[tok] = length(id_to_tok)
    end

    # 6 aligned frequency vector (specials get zero by convention)
    token_freqs = Int64[get(freqs_dict, tok, 0) for tok in id_to_tok]

    # 7 specials map: Symbol -> ID (IDs are stable across reloads)
    specials_id = Dict(sym => tok_to_id[str] for (sym, str) in specials)

    return Vocabulary(id_to_tok, tok_to_id, token_freqs, specials_id)
end


"""
    special_token_id(vocab, sym::Symbol)

Return the numeric ID of the special token `sym`.  Raises an informative
error if the special is missing.
"""
special_token_id(vocab::Vocabulary, sym::Symbol) =
    get(vocab.special_tokens, sym) do
        throw(ArgumentError("Special token :$sym not present; have $(keys(vocab.special_tokens))"))
    end


"""
    build_vocabulary(tokens::Vector{UInt8}; cfg) -> Vocabulary

Byte-level overload that builds a [`Vocabulary`](@ref) when the input sequence
has already been **flattened to raw UTF-8 bytes** (the usual output of
`tokenize_and_segment` with `tokenizer_name = :byte`).

Because the downstream implementation expects *string* tokens, every byte is
first converted to a **one-byte string** via

```julia
str_tokens = string.(Char.(tokens))
```

and control is delegated to the canonical
`build_vocabulary(tokens::Vector{String}; cfg)` method.  All arguments, sorting
rules, frequency thresholds, and special-token handling therefore remain
identical to the string-token version; only the lightweight byte-to-string
conversion is performed up front.

### Arguments
* `tokens :: Vector{UInt8}` - flat sequence of byte tokens.
* `cfg    :: PreprocessConfiguration` - configuration supplying
  `minimum_token_frequency`, `special_tokens`, etc.

### Returns
A fully-initialised [`Vocabulary`](@ref) suitable for byte-level models.

### Example
```julia
byte_tokens = UInt8[0x61, 0x62, 0x63]   # "abc"
vocab       = build_vocabulary(byte_tokens; cfg = cfg)
```
"""
function build_vocabulary(tokens::Vector{UInt8};
                          cfg::PreprocessConfiguration)

    str_tokens = string.(Char.(tokens))          # one-byte strings
    return build_vocabulary(str_tokens; cfg = cfg)
end


"""
    build_vocabulary(freqs; cfg) -> Vocabulary

Create a [`Vocabulary`](@ref) from a **pre-computed token-frequency table**
rather than from the raw token sequence.  This overload is useful when you
already have global counts—for example, collected in a prior streaming pass or
loaded from disk—and want to avoid iterating through the full corpus again.

### Arguments
| name  | type                       | description |
|:------|:---------------------------|:------------|
| `freqs` | `Dict{String,Int}` | Maps each *token string* to its corpus frequency. |
| `cfg`   | [`PreprocessConfiguration`](@ref) | Supplies `minimum_token_frequency`, the initial `special_tokens`, and the *dynamic* sentence markers when `record_sentence_offsets=true`. |

### Algorithm (identical to the token-list version)
1. **Seed specials** - copy `cfg.special_tokens`.  
   If `cfg.record_sentence_offsets`, ensure `:bos` / `:eos` exist
   (defaults `"<BOS>"`, `"<EOS>"`).
2. **Assign ids to specials** - symbols are sorted alphabetically for
   reproducibility.  Their ids occupy the first slots of `id_to_tok`.
3. **Insert corpus tokens** - iterate the *lexically-sorted* keys of `freqs`,
   append tokens whose frequency is **≥ `cfg.minimum_token_frequency`** and
   that are not already taken by a special.
4. **Frequency vector** - `token_frequencies[i]` equals the count of
   `id_to_tok[i]` (zero for specials).
5. **Specials id map** - convert `Symbol -> String` into `Symbol -> Int`.

### Returns
A fully-initialised [`Vocabulary`](@ref) comprising

* `id_to_token_strings :: Vector{String}`
* `token_to_id_map     :: Dict{String,Int}`
* `token_frequencies   :: Vector{Int}`
* `special_tokens      :: Dict{Symbol,Int}`

### Example
```julia
freqs = Dict("foo"=>120, "bar"=>5, "baz"=>1)
cfg   = PreprocessConfiguration(minimum_token_frequency = 2)

vocab = build_vocabulary(freqs; cfg = cfg)

@info "vocabulary size: \$(length(vocab.id_to_token_strings))"
```
"""
function build_vocabulary(freqs::Dict{String,Int}; cfg::PreprocessConfiguration)
    specials = Dict(cfg.special_tokens)
    cfg.record_sentence_offsets && (specials[:bos] = get(specials,:bos,"<BOS>");
                                    specials[:eos] = get(specials,:eos,"<EOS>"))

    id_to_tok = String[]
    tok_to_id = Dict{String,Int}()

    for sym in sort!(collect(keys(specials)))
        tok = specials[sym]
        push!(id_to_tok, tok);  tok_to_id[tok] = length(id_to_tok)
    end

    for tok in sort!(collect(keys(freqs)))
        f = freqs[tok]
        (f < cfg.minimum_token_frequency || haskey(tok_to_id,tok)) && continue
        push!(id_to_tok, tok);  tok_to_id[tok] = length(id_to_tok)
    end

    token_freqs = Int64[get(freqs, tok, 0) for tok in id_to_tok]
    specials_id = Dict(sym => tok_to_id[str] for (sym,str) in specials)

    Vocabulary(id_to_tok, tok_to_id, token_freqs, specials_id)
end


end # module _Vocabulary


# Make the builder visible to the main module
import ._Vocabulary: build_vocabulary
