module _Subwords

using ..KeemenaPreprocessing:
    PreprocessConfiguration, SubwordOptions,
    Vocabulary, Corpus, LevelBundle,
    PipelineMetadata, PreprocessBundle,
    build_vocabulary,
    CURRENT_SCHEMA_VERSION

import KeemenaSubwords


"""
Artifacts produced by `subword = SubwordOptions(...)` preprocessing.
"""
struct SubwordArtifacts
    tokenization_texts::Vector{String}
    offsets::Union{Nothing,Vector{Union{Nothing,Vector{Tuple{Int,Int}}}}}
    attention_masks::Union{Nothing,Vector{Union{Nothing,Vector{Int}}}}
    token_type_ids::Union{Nothing,Vector{Union{Nothing,Vector{Int}}}}
    special_tokens_masks::Union{Nothing,Vector{Union{Nothing,Vector{Int}}}}
    per_document_metadata::Vector{NamedTuple}
    tokenizer_metadata::NamedTuple
    source_description::String
    format::Symbol
    mode::Symbol
    level_name::Symbol
end


_describe_source(source) =
    source isa Symbol         ? ":$(source)" :
    source isa AbstractString ? String(source) :
    source isa NamedTuple     ? "NamedTuple($(join(keys(source), ", ")))" :
    source isa KeemenaSubwords.FilesSpec ? "FilesSpec(format=$(source.format))" :
    string(typeof(source))

_parent_function(name::Symbol) = getfield(parentmodule(@__MODULE__), name)


function _resolve_subword_tokenizer(opts::SubwordOptions)
    src = opts.source

    if src isa KeemenaSubwords.AbstractSubwordTokenizer
        return src
    elseif src isa Symbol
        return KeemenaSubwords.load_tokenizer(src)
    elseif src isa AbstractString
        return KeemenaSubwords.load_tokenizer(String(src); format = opts.format)
    elseif src isa NamedTuple
        return KeemenaSubwords.load_tokenizer(src)
    elseif src isa KeemenaSubwords.FilesSpec
        return KeemenaSubwords.load_tokenizer(src)
    end

    throw(ArgumentError(
        "Unsupported SubwordOptions source type $(typeof(src)); expected " *
        "Symbol, AbstractString, NamedTuple, FilesSpec, or AbstractSubwordTokenizer"))
end


function _native_vocabulary(tokenizer)
    vocab_size = KeemenaSubwords.vocab_size(tokenizer)
    id_to_token_strings = [KeemenaSubwords.id_to_token(tokenizer, i) for i in 1:vocab_size]
    token_to_id_map = Dict(tok => i for (i, tok) in pairs(id_to_token_strings))
    token_frequencies = zeros(Int, vocab_size)

    specials = Dict{Symbol,Int}()
    for (sym, id) in KeemenaSubwords.special_tokens(tokenizer)
        id isa Integer || continue
        1 <= id <= vocab_size || continue
        specials[sym] = Int(id)
    end

    return Vocabulary(id_to_token_strings, token_to_id_map, token_frequencies, specials)
end


function _encode_subword_document(
    tokenizer,
    clean_text::String,
    opts::SubwordOptions,
)
    tokenization_text = KeemenaSubwords.tokenization_view(tokenizer, clean_text)

    result = if opts.apply_tokenization_view
        KeemenaSubwords.encode_result(
            tokenizer, tokenization_text;
            add_special_tokens = opts.add_special_tokens,
            assume_normalized = true,
            return_offsets = opts.return_offsets,
            return_masks = opts.return_masks)
    else
        KeemenaSubwords.encode_result(
            tokenizer, clean_text;
            add_special_tokens = opts.add_special_tokens,
            assume_normalized = false,
            return_offsets = opts.return_offsets,
            return_masks = opts.return_masks)
    end

    return tokenization_text, result
end


function _corpus_vocab_cfg(cfg::PreprocessConfiguration)::PreprocessConfiguration
    # For subword corpus mode we intentionally build vocabulary from subword
    # pieces without sentence-marker injection.
    return PreprocessConfiguration(
        minimum_token_frequency = cfg.minimum_token_frequency,
        special_tokens = cfg.special_tokens,
        record_sentence_offsets = false,
    )
end


function _map_tokens_to_ids(tokens::Vector{String}, vocab::Vocabulary)::Vector{Int}
    unk_id = get(vocab.special_tokens, :unk, nothing)
    unk_id === nothing && throw(ArgumentError("Vocabulary lacks :unk token"))

    token_ids = Vector{Int}(undef, length(tokens))
    for (i, tok) in pairs(tokens)
        token_ids[i] = get(vocab.token_to_id_map, tok, unk_id)
    end
    return token_ids
end


function _build_subword_artifacts(
    tokenization_texts::Vector{String},
    offsets::Union{Nothing,Vector{Union{Nothing,Vector{Tuple{Int,Int}}}}},
    attention_masks::Union{Nothing,Vector{Union{Nothing,Vector{Int}}}},
    token_type_ids::Union{Nothing,Vector{Union{Nothing,Vector{Int}}}},
    special_tokens_masks::Union{Nothing,Vector{Union{Nothing,Vector{Int}}}},
    per_document_metadata::Vector{NamedTuple},
    tokenizer,
    opts::SubwordOptions,
)::SubwordArtifacts
    return SubwordArtifacts(
        tokenization_texts,
        offsets,
        attention_masks,
        token_type_ids,
        special_tokens_masks,
        per_document_metadata,
        KeemenaSubwords.model_info(tokenizer),
        _describe_source(opts.source),
        opts.format,
        opts.mode,
        opts.level_name,
    )
end


function _build_subword_native_bundle(
    clean_docs::Vector{String},
    cfg::PreprocessConfiguration,
    tokenizer;
    vocab::Union{Nothing,Vocabulary} = nothing,
    update_vocab_frequencies::Bool = true,
)::PreprocessBundle
    opts = cfg.subword
    opts === nothing && error("_build_subword_native_bundle requires cfg.subword to be set")
    opts.mode == :tokenizer_native || error("_build_subword_native_bundle requires mode=:tokenizer_native")

    token_ids = Int[]
    doc_offsets = Int[1]

    tokenization_texts = String[]
    offsets = opts.return_offsets ? Union{Nothing,Vector{Tuple{Int,Int}}}[] : nothing
    attention_masks = opts.return_masks ? Union{Nothing,Vector{Int}}[] : nothing
    token_type_ids = opts.return_masks ? Union{Nothing,Vector{Int}}[] : nothing
    special_tokens_masks = opts.return_masks ? Union{Nothing,Vector{Int}}[] : nothing
    per_document_metadata = NamedTuple[]

    for doc in clean_docs
        clean_text = String(doc)
        tokenization_text, result = _encode_subword_document(tokenizer, clean_text, opts)

        append!(token_ids, result.ids)
        push!(doc_offsets, length(token_ids) + 1)
        # Always store tokenizer-view text so offset reference remains explicit/stable.
        push!(tokenization_texts, tokenization_text)
        push!(per_document_metadata, result.metadata)

        offsets !== nothing && push!(offsets, result.offsets)
        attention_masks !== nothing && push!(attention_masks, result.attention_mask)
        token_type_ids !== nothing && push!(token_type_ids, result.token_type_ids)
        special_tokens_masks !== nothing && push!(special_tokens_masks, result.special_tokens_mask)
    end

    vocab = vocab === nothing ? _native_vocabulary(tokenizer) : vocab
    n_vocab = length(vocab.id_to_token_strings)
    for id in token_ids
        1 <= id <= n_vocab || error(
            "Tokenizer produced id $id outside vocabulary size $n_vocab for level :$(opts.level_name)")
        update_vocab_frequencies && (vocab.token_frequencies[id] += 1)
    end

    corpus = Corpus(token_ids, doc_offsets, nothing, nothing, nothing, nothing, nothing)
    level_bundle = LevelBundle(corpus, vocab)
    levels = Dict(opts.level_name => level_bundle)

    extras = _build_subword_artifacts(
        tokenization_texts,
        offsets,
        attention_masks,
        token_type_ids,
        special_tokens_masks,
        per_document_metadata,
        tokenizer,
        opts,
    )

    return PreprocessBundle(
        levels;
        metadata = PipelineMetadata(cfg, CURRENT_SCHEMA_VERSION),
        extras = extras,
    )
end


function _build_subword_corpus_bundle(
    clean_docs::Vector{String},
    cfg::PreprocessConfiguration,
    tokenizer;
    vocab::Union{Nothing,Vocabulary} = nothing,
)::PreprocessBundle
    opts = cfg.subword
    opts === nothing && error("_build_subword_corpus_bundle requires cfg.subword to be set")
    opts.mode == :bundle_reindexed || error("_build_subword_corpus_bundle requires mode=:bundle_reindexed")

    piece_tokens = String[]
    doc_offsets = Int[1]

    tokenization_texts = String[]
    offsets = opts.return_offsets ? Union{Nothing,Vector{Tuple{Int,Int}}}[] : nothing
    attention_masks = opts.return_masks ? Union{Nothing,Vector{Int}}[] : nothing
    token_type_ids = opts.return_masks ? Union{Nothing,Vector{Int}}[] : nothing
    special_tokens_masks = opts.return_masks ? Union{Nothing,Vector{Int}}[] : nothing
    per_document_metadata = NamedTuple[]

    for doc in clean_docs
        clean_text = String(doc)
        tokenization_text, result = _encode_subword_document(tokenizer, clean_text, opts)

        append!(piece_tokens, result.tokens)
        push!(doc_offsets, length(piece_tokens) + 1)
        push!(tokenization_texts, tokenization_text)
        push!(per_document_metadata, result.metadata)

        offsets !== nothing && push!(offsets, result.offsets)
        attention_masks !== nothing && push!(attention_masks, result.attention_mask)
        token_type_ids !== nothing && push!(token_type_ids, result.token_type_ids)
        special_tokens_masks !== nothing && push!(special_tokens_masks, result.special_tokens_mask)
    end

    vocab = vocab === nothing ? build_vocabulary(piece_tokens; cfg = _corpus_vocab_cfg(cfg)) : vocab
    token_ids = _map_tokens_to_ids(piece_tokens, vocab)

    corpus = Corpus(token_ids, doc_offsets, nothing, nothing, nothing, nothing, nothing)
    level_bundle = LevelBundle(corpus, vocab)
    levels = Dict(opts.level_name => level_bundle)

    extras = _build_subword_artifacts(
        tokenization_texts,
        offsets,
        attention_masks,
        token_type_ids,
        special_tokens_masks,
        per_document_metadata,
        tokenizer,
        opts,
    )

    return PreprocessBundle(
        levels;
        metadata = PipelineMetadata(cfg, CURRENT_SCHEMA_VERSION),
        extras = extras,
    )
end


function preprocess_subword_native(sources, cfg::PreprocessConfiguration)::PreprocessBundle
    opts = cfg.subword
    opts === nothing && error("preprocess_subword_native requires cfg.subword to be set")
    opts.mode == :tokenizer_native || error("preprocess_subword_native requires mode=:tokenizer_native")

    docs = _parent_function(:_load_sources)(sources)
    clean_docs = _parent_function(:clean_documents)(docs, cfg)
    tokenizer = _resolve_subword_tokenizer(opts)
    return _build_subword_native_bundle(clean_docs, cfg, tokenizer)
end


function preprocess_subword_corpus(sources, cfg::PreprocessConfiguration)::PreprocessBundle
    opts = cfg.subword
    opts === nothing && error("preprocess_subword_corpus requires cfg.subword to be set")
    opts.mode == :bundle_reindexed || error("preprocess_subword_corpus requires mode=:bundle_reindexed")

    docs = _parent_function(:_load_sources)(sources)
    clean_docs = _parent_function(:clean_documents)(docs, cfg)
    tokenizer = _resolve_subword_tokenizer(opts)
    return _build_subword_corpus_bundle(clean_docs, cfg, tokenizer)
end


function _streaming_subword_native_vocabulary(srcs,
                                              cfg::PreprocessConfiguration,
                                              tokenizer;
                                              chunk_tokens::Int)::Vocabulary
    opts = cfg.subword
    opts === nothing && error("_streaming_subword_native_vocabulary requires cfg.subword to be set")
    opts.mode == :tokenizer_native || error("_streaming_subword_native_vocabulary requires mode=:tokenizer_native")

    vocab = _native_vocabulary(tokenizer)
    fill!(vocab.token_frequencies, 0)

    chunk_iter = _parent_function(:doc_chunk_iterator)(srcs, cfg; chunk_tokens = chunk_tokens)
    clean_documents = _parent_function(:clean_documents)

    n_vocab = length(vocab.id_to_token_strings)
    for docs in chunk_iter
        clean_docs = clean_documents(docs, cfg)
        for doc in clean_docs
            _, result = _encode_subword_document(tokenizer, String(doc), opts)
            for id in result.ids
                1 <= id <= n_vocab || error(
                    "Tokenizer produced id $id outside vocabulary size $n_vocab for level :$(opts.level_name)")
                vocab.token_frequencies[id] += 1
            end
        end
    end
    return vocab
end


function _streaming_subword_piece_frequencies(srcs,
                                              cfg::PreprocessConfiguration,
                                              tokenizer;
                                              chunk_tokens::Int)::Dict{String,Int}
    opts = cfg.subword
    opts === nothing && error("_streaming_subword_piece_frequencies requires cfg.subword to be set")
    opts.mode == :bundle_reindexed || error("_streaming_subword_piece_frequencies requires mode=:bundle_reindexed")

    freqs = Dict{String,Int}()
    chunk_iter = _parent_function(:doc_chunk_iterator)(srcs, cfg; chunk_tokens = chunk_tokens)
    clean_documents = _parent_function(:clean_documents)

    for docs in chunk_iter
        clean_docs = clean_documents(docs, cfg)
        for doc in clean_docs
            _, result = _encode_subword_document(tokenizer, String(doc), opts)
            for tok in result.tokens
                freqs[tok] = get(freqs, tok, 0) + 1
            end
        end
    end
    return freqs
end


function _validate_streaming_subword_vocab(vocab::Vocabulary,
                                           opts::SubwordOptions,
                                           tokenizer)::Vocabulary
    if opts.mode == :tokenizer_native
        expected = _native_vocabulary(tokenizer)
        if vocab.id_to_token_strings != expected.id_to_token_strings
            error("Provided vocabulary does not match tokenizer-native id ordering for mode=:tokenizer_native.")
        end
        if vocab.token_to_id_map != expected.token_to_id_map
            error("Provided vocabulary token_to_id_map does not match tokenizer-native mapping for mode=:tokenizer_native.")
        end
        if vocab.special_tokens != expected.special_tokens
            error("Provided vocabulary special_tokens do not match tokenizer-native special token ids for mode=:tokenizer_native.")
        end
        length(vocab.token_frequencies) == length(expected.id_to_token_strings) || error(
            "Provided vocabulary token_frequencies length does not match tokenizer vocabulary size for mode=:tokenizer_native.")

        # Normalize mapping/specials to the canonical tokenizer-native reference,
        # while preserving caller-provided frequencies.
        return Vocabulary(
            copy(expected.id_to_token_strings),
            Dict(expected.token_to_id_map),
            copy(vocab.token_frequencies),
            Dict(expected.special_tokens),
        )
    elseif opts.mode == :bundle_reindexed
        haskey(vocab.special_tokens, :unk) || error(
            "Provided vocabulary must include :unk when mode=:bundle_reindexed.")
        return vocab
    end
    error("Unsupported subword mode :$(opts.mode)")
end


function preprocess_subword_streaming(srcs;
                                      cfg::PreprocessConfiguration,
                                      vocab::Union{Nothing,Vocabulary} = nothing,
                                      chunk_tokens::Int = 500_000,
                                      channel_capacity::Int = 1)::Channel{PreprocessBundle}
    opts = cfg.subword
    opts === nothing && error("preprocess_subword_streaming requires cfg.subword to be set")
    channel_capacity >= 0 || throw(ArgumentError(
        "channel_capacity must be >= 0; got $channel_capacity"))

    tokenizer = _resolve_subword_tokenizer(opts)

    resolved_vocab = if vocab === nothing
        if opts.mode == :tokenizer_native
            _streaming_subword_native_vocabulary(
                srcs, cfg, tokenizer; chunk_tokens = chunk_tokens)
        elseif opts.mode == :bundle_reindexed
            freqs = _streaming_subword_piece_frequencies(
                srcs, cfg, tokenizer; chunk_tokens = chunk_tokens)
            build_vocabulary(freqs; cfg = _corpus_vocab_cfg(cfg))
        else
            error("Unsupported subword mode :$(opts.mode)")
        end
    else
        _validate_streaming_subword_vocab(vocab, opts, tokenizer)
    end

    raw_chunks = _parent_function(:doc_chunk_iterator)(srcs, cfg; chunk_tokens = chunk_tokens)
    clean_documents = _parent_function(:clean_documents)

    return Channel{PreprocessBundle}(channel_capacity) do ch
        for docs in raw_chunks
            clean_docs = clean_documents(docs, cfg)
            bundle = if opts.mode == :tokenizer_native
                _build_subword_native_bundle(
                    clean_docs, cfg, tokenizer;
                    vocab = resolved_vocab,
                    update_vocab_frequencies = false,
                )
            elseif opts.mode == :bundle_reindexed
                _build_subword_corpus_bundle(
                    clean_docs, cfg, tokenizer;
                    vocab = resolved_vocab,
                )
            else
                error("Unsupported subword mode :$(opts.mode)")
            end
            put!(ch, bundle)
        end
    end
end


function _append_optional_artifacts!(dest, src, field_name::AbstractString)
    if dest === nothing || src === nothing
        dest === src || error(
            "Subword artifacts mismatch across streaming chunks for $(field_name).")
        return
    end
    append!(dest, src)
end


function merge_subword_artifacts!(accum::SubwordArtifacts,
                                  incoming::SubwordArtifacts)::SubwordArtifacts
    accum.source_description == incoming.source_description || error("Subword source mismatch across streaming chunks")
    accum.format == incoming.format || error("Subword format mismatch across streaming chunks")
    accum.mode == incoming.mode || error("Subword mode mismatch across streaming chunks")
    accum.level_name == incoming.level_name || error("Subword level_name mismatch across streaming chunks")
    accum.tokenizer_metadata == incoming.tokenizer_metadata || error("Subword tokenizer metadata mismatch across streaming chunks")

    append!(accum.tokenization_texts, incoming.tokenization_texts)
    append!(accum.per_document_metadata, incoming.per_document_metadata)
    _append_optional_artifacts!(accum.offsets, incoming.offsets, "offsets")
    _append_optional_artifacts!(accum.attention_masks, incoming.attention_masks, "attention_masks")
    _append_optional_artifacts!(accum.token_type_ids, incoming.token_type_ids, "token_type_ids")
    _append_optional_artifacts!(accum.special_tokens_masks, incoming.special_tokens_masks, "special_tokens_masks")
    return accum
end


function preprocess_subword(sources, cfg::PreprocessConfiguration)::PreprocessBundle
    opts = cfg.subword
    opts === nothing && error("preprocess_subword requires cfg.subword to be set")

    if opts.mode == :tokenizer_native
        return preprocess_subword_native(sources, cfg)
    elseif opts.mode == :bundle_reindexed
        return preprocess_subword_corpus(sources, cfg)
    end

    error("Unsupported subword mode :$(opts.mode)")
end


function _require_subword_artifacts(bundle::PreprocessBundle)::SubwordArtifacts
    extras = bundle.extras
    extras isa SubwordArtifacts || error(
        "Bundle extras do not contain SubwordArtifacts. This helper only works for bundles produced by subword = SubwordOptions(...).")
    return extras
end


get_subword_offsets(bundle::PreprocessBundle) =
    _require_subword_artifacts(bundle).offsets

get_subword_attention_mask(bundle::PreprocessBundle) =
    _require_subword_artifacts(bundle).attention_masks

get_subword_token_type_ids(bundle::PreprocessBundle) =
    _require_subword_artifacts(bundle).token_type_ids

get_subword_special_tokens_mask(bundle::PreprocessBundle) =
    _require_subword_artifacts(bundle).special_tokens_masks

function get_subword_metadata(bundle::PreprocessBundle)
    extras = _require_subword_artifacts(bundle)
    return (
        source = extras.source_description,
        format = extras.format,
        mode = extras.mode,
        level_name = extras.level_name,
        tokenizer = extras.tokenizer_metadata,
        per_document = extras.per_document_metadata,
        tokenization_texts = extras.tokenization_texts,
    )
end


end # module _Subwords


import ._Subwords:
    SubwordArtifacts,
    preprocess_subword,
    preprocess_subword_native,
    preprocess_subword_corpus,
    preprocess_subword_streaming,
    merge_subword_artifacts!,
    get_subword_offsets,
    get_subword_attention_mask,
    get_subword_token_type_ids,
    get_subword_special_tokens_mask,
    get_subword_metadata
