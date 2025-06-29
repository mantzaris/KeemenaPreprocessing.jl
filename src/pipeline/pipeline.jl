

function preprocess_corpus(sources; id_type::Type{<:Unsigned}=UInt32,
                            offset_type::Type{<:Integer}=Int,
                            save_to::Union{Nothing,String}=nothing,
                            config::Union{Nothing,PreprocessConfiguration}=nothing,
                            kwargs...) #remaining keywords

    if config !== nothing && !isempty(kwargs)
        error("Pass either config= or per-field keywords, not both.")
    end
    
    cfg = config === nothing ? PreprocessConfiguration(; kwargs...) : config
    
    return _preprocess_core(sources, cfg; id_type, offset_type, save_to)
end


function preprocess_corpus(sources, cfg::PreprocessConfiguration;
                            id_type::Type{<:Unsigned}=UInt32,
                            offset_type::Type{<:Integer}=Int,
                            save_to::Union{Nothing,String}=nothing)

    return _preprocess_core(sources, cfg; id_type, offset_type, save_to)
end


function _preprocess_core(sources,
                          cfg::PreprocessConfiguration;
                          id_type::Type{<:Unsigned}=UInt32,
                          offset_type::Type{<:Integer}=Int,
                          save_to::Union{Nothing,String}=nothing)

    # 1. load & clean
    docs          = _load_sources(sources)
    clean_docs    = clean_documents(docs, cfg)

    # 2. tokenise & segment
    tokens,offs   = tokenize_and_segment(clean_docs, cfg)

    # 3. vocab + bundle
    vocab         = build_vocabulary(tokens; cfg=cfg, id_type=id_type)
    bundle        = assemble_bundle(tokens, offs, vocab, cfg; offset_type)

    save_to !== nothing && save_preprocess_bundle(bundle, save_to)
    return bundle
end


function preprocess_corpus_streaming(srcs;
                                     cfg              = PreprocessConfiguration(),
                                     chunk_tokens     = cfg.chunk_size,
                                     id_type::Type{<:Unsigned}=UInt32,
                                     offset_type::Type{<:Integer}=Int)

    raw_chunks = doc_chunk_iterator(srcs, cfg; chunk_tokens)
    return Channel{PreprocessBundle}(Inf) do ch
        vocab  = nothing
        first  = true
        for docs in raw_chunks
            clean_docs        = clean_documents(docs, cfg)
            tokens, offs      = tokenize_and_segment(clean_docs, cfg)

            if first
                vocab = build_vocabulary(tokens; cfg, id_type)
                first = false
            end

            bundle = assemble_bundle(tokens, offs, vocab, cfg; offset_type)
            put!(ch, bundle)
        end
    end
end



"""
    doc_chunk_iterator(srcs, cfg; chunk_tokens=cfg.chunk_size)

Yields `Vector{String}` where the cumulative token *estimate* ≤ `chunk_tokens`.
"""
function doc_chunk_iterator(srcs, cfg; chunk_tokens::Int = cfg.chunk_size)
    est_tokens(doc) = count(isspace, doc) + 1     # quick proxy

    return Channel{Vector{String}}() do ch
        buf    = String[]
        budget = 0
        for doc in _load_sources(srcs)
            push!(buf, doc)
            budget += est_tokens(doc)
            if budget ≥ chunk_tokens
                put!(ch, buf)
                buf    = String[]
                budget = 0
            end
        end
        !isempty(buf) && put!(ch, buf)
    end
end
