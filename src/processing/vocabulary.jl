

module _Vocabulary


using StatsBase                # countmap
using ..KeemenaPreprocessing:  PreprocessConfiguration,
                               Vocabulary



"""
    build_vocabulary(tokens::Vector{String}; cfg::PreprocessConfiguration) -> Vocabulary
    build_vocabulary(freqs::Dict{String,Int};   cfg::PreprocessConfiguration) -> Vocabulary
    build_vocabulary(stream::Channel{Vector{String}};
                     cfg::PreprocessConfiguration;
                     chunk_size::Int = 500_000) -> Vocabulary

Construct a `Vocabulary` from token data that may be held entirely in memory,
pre-counted, or streamed in batches.

# Method overview
* **Vector method** - accepts a flat vector of token strings.
* **Dict method**   - accepts a dictionary that maps each token string to its
  corpus frequency.
* **Streaming method** - accepts a channel that yields token-vector batches so
  you can build a vocabulary without ever loading the whole corpus at once.

All three methods share the same counting, filtering, and ID-assignment logic;
they differ only in how token data are supplied.

# Shared argument
* `cfg` - a `PreprocessConfiguration` that provides
  * `minimum_token_frequency`
  * initial `special_tokens`
  * dynamic sentence markers when `record_sentence_offsets` is true.

# Additional arguments
* `tokens` - vector of token strings.
* `freqs`  - dictionary from token string to integer frequency.
* `stream` - channel that produces vectors of token strings.
* `chunk_size` - number of tokens to buffer before flushing counts
  (streaming method only).

# Processing steps
1. **Seed specials** - copy the special tokens from `cfg` and insert
   `<BOS>` / `<EOS>` if sentence offsets are recorded.
2. **Count tokens** - accumulate frequencies from the provided data source.
3. **Filter** - discard tokens occurring fewer times than
   `cfg.minimum_token_frequency`.
4. **Assign IDs** - assign IDs to specials first (alphabetical order for
   reproducibility), then to remaining tokens sorted by descending frequency
   and finally lexicographic order.
5. **Return** - a deterministic `Vocabulary` containing `token_to_id`,
   `id_to_token`, and `frequencies`.

# Examples

```julia
# From a token vector
tokens = ["the", "red", "fox", ...]
vocab  = build_vocabulary(tokens; cfg = config)

# From pre-computed counts
counts = Dict("the" => 523_810, "fox" => 1_234)
vocab  = build_vocabulary(counts; cfg = config)

# Streaming large corpora
ch = Channel{Vector{String}}(8) do c
    for path in corpus_paths
        put!(c, tokenize(read(path, String)))
    end
end
vocab = build_vocabulary(ch; cfg = config, chunk_size = 100_000)
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
    special_token_id(vocab::Vocabulary, sym::Symbol)

Return the numeric ID of the special token `sym`.
Raises an informative error if the special is missing.
"""
special_token_id(vocab::Vocabulary, sym::Symbol) =
    get(vocab.special_tokens, sym) do
        throw(ArgumentError("Special token : (sym) not present; have  (keys(vocab.special_tokens))"))
    end



function build_vocabulary(tokens::Vector{UInt8};
                          cfg::PreprocessConfiguration)

    str_tokens = string.(Char.(tokens))          # one-byte strings
    return build_vocabulary(str_tokens; cfg = cfg)
end




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
