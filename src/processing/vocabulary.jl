
    # TODO: 1 - paragraph / document boundary markers

    # Example:
    # if cfg.record_paragraph_offsets
    #     specials[:pbos] = get(specials, :pbos, "<PBOS>")
    #     specials[:peos] = get(specials, :peos, "<PEOS>")
    # end
    #
    # Uncomment / extend when you have a model that requires them

    # TODO: 2 - sub-word or language-specific specials
    # If later you support BPE/SentencePiece in `extras`,
    # inject <BPE_UNK>, <SP_ACRONYM>, etc. here based on cfg flags

    # 4 assign IDs  (specials first, deterministic alphabetical order)

module _Vocabulary


using StatsBase                # countmap
using ..KeemenaPreprocessing:  PreprocessConfiguration,
                               Vocabulary


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

    # 7 specials map: Symbol ⇒ ID (IDs are stable across reloads)
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
