

module _Tokenization


using Unicode
using Base.Unicode: graphemes
using ..KeemenaPreprocessing: PreprocessConfiguration


_ws_tokenizer(str::AbstractString) = split(str) .|> String


# very small Unicode-word-boundary heuristic (good enough for English + mixed)
const _WB_RE = r"\p{L}[\p{M}\p{Pc}\p{Pd}\p{Nd}\p{L}]*" *
               r"|\p{N}[\p{M}\p{Pc}\p{Pd}\p{Nd}\p{L}]*"

_unicode_tokenizer(str::AbstractString) =
    [String(m.match) for m in eachmatch(_WB_RE, str)]


#raw UTF-8 bytes
_byte_tokenizer(str::AbstractString) = collect(codeunits(str))   # Vector{UInt8}


_char_tokenizer(s::AbstractString) = [ String(g) for g in graphemes(s) ]


_select_tokenizer(tk) =
    tk isa Function    ? tk :
    tk === :char       ? _char_tokenizer :
    tk === :unicode    ? _unicode_tokenizer :
    tk === :whitespace ? _ws_tokenizer :
    tk === :byte       ? _byte_tokenizer  :
    error("Unknown tokenizer $(tk); should have been validated earlier")


_split_paragraphs(txt::AbstractString) = split(txt, r"\n{2,}") #split(txt, r"\\n{2,}")
_split_sentences(txt::AbstractString)  = split(txt, r"(?<=[.!?])\s+") #split(p,  r"(?<=[.!?])\\s+")




"""
    tokenize_and_segment(chunks, cfg::PreprocessConfiguration) -> (tokens, offsets)
    tokenize_and_segment(docs::Vector{String}, cfg::PreprocessConfiguration) -> (tokens, offsets)

Tokenise raw text and record start-index vectors (offsets) for the
segmentation levels you request in `cfg`.

# Method overview
* **Streaming variant**  
  Accepts an iterator that yields `(chunk, terminal)` where  
  `chunk :: String` is a piece of raw text and  
  `terminal :: Bool` is true when the chunk ends a document.

* **Convenience variant**  
  Accepts a vector of full documents. Each document is wrapped into a
  `(doc, true)` pair and then processed by the streaming implementation.

Both variants share the same algorithm and return type.

# Shared arguments
* `cfg` - an instance of `PreprocessConfiguration` that selects
  * the tokenizer (`tokenizer_name`);
  * which offset tables are recorded (`record_sentence_offsets`,  
    `record_paragraph_offsets`, and so on);
  * how empty tokens are handled (`preserve_empty_tokens`).

# Source-specific arguments
* `chunks` - iterator of `(String, Bool)` pairs.
* `docs`   - vector of document strings.

# Returns
`(tokens, offsets)`

* `tokens :: Vector{UInt8}` when `tokenizer_name == :byte`, otherwise
  `Vector{String}`.
* `offsets :: Dict{Symbol,Vector{Int}}` whose keys correspond to every
  `record_*_offsets` flag set to true in `cfg`.  
  Each vector always begins with 1 and ends with `length(tokens) + 1`.

# Processing steps
1. **Select tokenizer** with `_select_tokenizer(cfg.tokenizer_name)`.
2. **Validate** that byte offsets are requested only with the byte tokenizer
   and character offsets only with the character tokenizer.
3. **Iterate** over chunks  
   • Optionally split into paragraphs and sentences.  
   • Tokenise each sentence and push tokens.  
   • After each push, append `next_index = length(tokens) + 1`
     to every active offset vector.  
   • When `terminal` is true, close the current document offset.
4. **Close sentinels** - ensure every recorded offsets vector ends with
   `length(tokens) + 1`.
5. **Package** and return `(tokens, offsets)`.

# Example

```julia
# Whole-corpus path
docs = ["Hello world.", "Second document..."]
cfg  = PreprocessConfiguration(tokenizer_name = :whitespace,
                               record_sentence_offsets = true,
                               record_document_offsets = true)

tokens, offs = tokenize_and_segment(docs, cfg)

println(tokens)        # ["Hello", "world.", "Second", "document..."]
println(offs[:document])   # [1, 3]        sentinel at end is implicit
println(offs[:sentence])   # [1, 3, 5]
```
Error conditions: an ArgumentError is thrown if you request byte offsets
with a non-byte tokenizer or character offsets with a non-character tokenizer,
or if any other incompatible configuration is detected.
"""
function tokenize_and_segment(chunks, cfg::PreprocessConfiguration)

    tok_fn     = _select_tokenizer(cfg.tokenizer_name)
    tok_eltype = cfg.tokenizer_name === :byte ? UInt8 : String
    tokens     = Vector{tok_eltype}()

    # sanity checks (fail to avoid confusion)
    if cfg.record_character_offsets && cfg.tokenizer_name != :char
        error("record_character_offsets=true requires tokenizer_name = :char")
    end
    if cfg.record_byte_offsets && cfg.tokenizer_name != :byte
        error("record_byte_offsets=true requires tokenizer_name = :byte")
    end

    #always start each offset vector with 1 (sentinel)
    doc_offs = cfg.record_document_offsets   ? Int[1] : Int[]
    par_offs = cfg.record_paragraph_offsets  ? Int[1] : Int[]
    sen_offs = cfg.record_sentence_offsets   ? Int[1] : Int[]
    word_offs = cfg.record_word_offsets      ? Int[1] : Int[]
    char_offs = cfg.record_character_offsets ? Int[1] : Int[]
    byte_offs = cfg.record_byte_offsets      ? Int[1] : Int[]

   
    for (chunk, terminal) in chunks #for doc in docs
        
        paragraphs = cfg.record_paragraph_offsets ? _split_paragraphs(chunk) : (chunk,)

        for para in paragraphs
            sentences = cfg.record_sentence_offsets ? _split_sentences(para) : (para,)

            for sent in sentences
                tkns = tok_fn(sent)

                if !cfg.preserve_empty_tokens && (eltype(tkns) <: AbstractString)
                    filter!(t -> !isempty(t), tkns)
                end

                for tok in tkns
                    push!(tokens, tok)

                    nxt = length(tokens) + 1      # = index of the *next* token

                    if cfg.record_word_offsets
                        push!(word_offs, nxt)
                    end
                    if cfg.tokenizer_name == :char && cfg.record_character_offsets
                        push!(char_offs, nxt)
                    elseif cfg.tokenizer_name == :byte && cfg.record_byte_offsets
                        push!(byte_offs, nxt)
                    end
                end

                cfg.record_sentence_offsets && push!(sen_offs, length(tokens)+1)
            end
            cfg.record_paragraph_offsets && push!(par_offs, length(tokens)+1)
        end
        
        if terminal && cfg.record_document_offsets
            push!(doc_offs, length(tokens) + 1)
        end
    end

    cfg.record_character_offsets && char_offs[end] != length(tokens) + 1 &&
        push!(char_offs, length(tokens) + 1)

    cfg.record_byte_offsets && byte_offs[end] != length(tokens) + 1 &&
        push!(byte_offs, length(tokens) + 1)

    cfg.record_word_offsets && word_offs[end] != length(tokens)+1 &&
        push!(word_offs, length(tokens)+1)

    cfg.record_sentence_offsets  && !isempty(sen_offs) && sen_offs[end] != length(tokens)+1 &&
        push!(sen_offs, length(tokens)+1)
        
    cfg.record_paragraph_offsets && !isempty(par_offs) && par_offs[end] != length(tokens)+1 &&
        push!(par_offs, length(tokens)+1)

    # package result dict
    offs = Dict{Symbol,Vector{Int}}()
    cfg.record_document_offsets  && (offs[:document]  = doc_offs)
    cfg.record_paragraph_offsets && (offs[:paragraph] = par_offs)
    cfg.record_sentence_offsets  && (offs[:sentence]  = sen_offs)
    cfg.record_word_offsets      && (offs[:word]      = word_offs)
    cfg.record_character_offsets && (offs[:character] = char_offs)
    cfg.record_byte_offsets      && (offs[:byte]      = byte_offs)

    return tokens, offs
end



function tokenize_and_segment(docs::Vector{String},
                              cfg::PreprocessConfiguration)
    # Turn each whole document into a single-terminal chunk
    iter = ((doc, true) for doc in docs)
    return tokenize_and_segment(iter, cfg)
end


end # module _Tokenization


import ._Tokenization: tokenize_and_segment