

function preprocess_corpus(sources;
                            save_to::Union{Nothing,String}=nothing,
                            config::Union{Nothing,PreprocessConfiguration}=nothing,
                            kwargs...) #remaining keywords

    if config !== nothing && !isempty(kwargs)
        error("Pass either config= or per-field keywords, not both.")
    end
    
    cfg = config === nothing ? PreprocessConfiguration(; kwargs...) : config
    
    return _preprocess_core(sources, cfg; save_to)
end


function preprocess_corpus(sources, cfg::PreprocessConfiguration;
                            save_to::Union{Nothing,String} = nothing)

    return _preprocess_core(sources, cfg; save_to)
end


function preprocess_corpus_streaming(srcs;
                                     cfg   ::PreprocessConfiguration = PreprocessConfiguration(),
                                     vocab ::Union{Nothing,Vocabulary} = nothing)

    # Pass 1 - optional full-corpus vocab
    if vocab === nothing
        all_docs            = collect(_load_sources(srcs))
        clean_docs          = clean_documents(all_docs, cfg)
        all_tokens, _       = tokenize_and_segment(clean_docs, cfg)
        vocab               = build_vocabulary(all_tokens; cfg=cfg)
    end

    raw_chunks = doc_chunk_iterator(srcs, cfg)  # Pass 2 - streaming

    return Channel{PreprocessBundle}(Inf) do ch
        for docs in raw_chunks
            clean_docs        = clean_documents(docs, cfg)
            tokens, offs      = tokenize_and_segment(clean_docs, cfg)
            bundle            = assemble_bundle(tokens, offs, vocab, cfg)
            build_alignments!(bundle)
            put!(ch, bundle)
        end
    end
 end


function _preprocess_core(sources,
                          cfg::PreprocessConfiguration;
                          save_to::Union{Nothing,String}=nothing)

    # 1 load & clean
    docs          = _load_sources(sources)
    clean_docs    = clean_documents(docs, cfg)

    # 2 tokenise & segment
    tokens,offs   = tokenize_and_segment(clean_docs, cfg)

    # 3 vocab + bundle
    vocab         = build_vocabulary(tokens; cfg=cfg)
    bundle        = assemble_bundle(tokens, offs, vocab, cfg)
    build_alignments!(bundle)

    save_to !== nothing && save_preprocess_bundle(bundle, save_to)
    return bundle
end


function doc_chunk_iterator(srcs, cfg; chunk_tokens::Int = cfg.chunk_size)
    est_tokens(doc) = count(isspace, doc) + 1     # quick proxy

    return Channel{Vector{String}}() do ch
        buf    = String[]
        budget = 0

        for doc in _load_sources(srcs)
            push!(buf, doc)
            budget += est_tokens(doc)
            
            if budget >= chunk_tokens
                put!(ch, buf)
                buf    = String[]
                budget = 0
            end
        end
        !isempty(buf) && put!(ch, buf)
    end
end
