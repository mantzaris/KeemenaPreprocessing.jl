

module _Tokenization


using Unicode
using ..KeemenaPreprocessing: PreprocessConfiguration


_ws_tokenizer(str::AbstractString) = split(str) .|> String


# very small Unicode-word-boundary heuristic (good enough for English + mixed)
const _WB_RE = r"(?<=\p{L}|\p{N})[\p{M}\p{Pc}\p{Pd}\p{Nd}\p{L}]*" #r"(?<=\\p{L}|\\p{N})[\\p{M}\\p{Pc}\\p{Pd}\\p{Nd}\\p{L}]*"

_unicode_tokenizer(str::AbstractString) =
    collect(eachmatch(_WB_RE, str)) .|> String


_select_tokenizer(tk) =
    tk isa Function   ? tk :
    tk === :unicode   ? _unicode_tokenizer :
    tk === :whitespace ? _ws_tokenizer :
    error("Unknown tokenizer $(tk); should have been validated earlier")


_split_paragraphs(txt::String) = split(txt, r"\n{2,}") #split(txt, r"\\n{2,}")
_split_sentences(txt::String)    = split(txt, r"(?<=[.!?])\s+") #split(p,  r"(?<=[.!?])\\s+")


"""
    tokenize_and_segment(docs, cfg) -> (tokens, offsets)

- `docs` : cleaned documents (`Vector{String}`)
- `cfg`  : `PreprocessConfiguration`

Returns  
- `tokens  :: Vector{String}` flat list  
- `offsets :: Dict{Symbol,Vector{Int}}` keys present only for the
  levels requested via `record_*_offsets`

each offset vector follows the Julia sentinel convention:
`offsets[:sentence][end] == length(tokens) + 1`
"""
function tokenize_and_segment(docs::Vector{String}, cfg::PreprocessConfiguration)

    tok_fn   = _select_tokenizer(cfg.tokenizer_name)
    tokens   = String[]

    #always start each offset vector with 1 (sentinel)
    doc_offs = cfg.record_document_offsets  ? Int[1] : Int[]
    par_offs = cfg.record_paragraph_offsets ? Int[1] : Int[]
    sen_offs = cfg.record_sentence_offsets  ? Int[1] : Int[]

    # main traversal
    for doc in docs
        paragraphs = cfg.record_paragraph_offsets ? _split_paragraphs(doc) : (doc,)

        for para in paragraphs
            sentences = cfg.record_sentence_offsets ? _split_sentences(para) : (para,)

            for sent in sentences
                tkns = tok_fn(sent)
                if !cfg.preserve_empty_tokens
                    filter!(t -> !isempty(t), tkns)
                end
                append!(tokens, tkns)
                cfg.record_sentence_offsets && push!(sen_offs, length(tokens)+1)
            end
            cfg.record_paragraph_offsets && push!(par_offs, length(tokens)+1)
        end
        cfg.record_document_offsets && push!(doc_offs, length(tokens)+1)
    end

    # package result dict
    offs = Dict{Symbol,Vector{Int}}()
    cfg.record_document_offsets  && (offs[:document]  = doc_offs)
    cfg.record_paragraph_offsets && (offs[:paragraph] = par_offs)
    cfg.record_sentence_offsets  && (offs[:sentence]  = sen_offs)

    return tokens, offs
end


end # module _Tokenization


import ._Tokenization: tokenize_and_segment