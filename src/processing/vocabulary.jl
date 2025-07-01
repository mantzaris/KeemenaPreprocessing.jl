
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
                          cfg::PreprocessConfiguration,
                          id_type::Type{<:Integer}=UInt32)

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
    tok_to_id = Dict{String,id_type}()

    for sym in sort!(collect(keys(specials)))
        tok = specials[sym]
        push!(id_to_tok, tok)
        tok_to_id[tok] = id_type(length(id_to_tok))
    end

    # 5 add corpus tokens that meet the frequency threshold
    for (tok, f) in freqs_dict
        (f < cfg.minimum_token_frequency || haskey(tok_to_id, tok)) && continue
        push!(id_to_tok, tok)
        tok_to_id[tok] = id_type(length(id_to_tok))
    end

    # 6 aligned frequency vector (specials get zero by convention)
    token_freqs = [get(freqs_dict, tok, 0) for tok in id_to_tok]

    # 7 specials map: Symbol ⇒ ID (IDs are stable across reloads)
    specials_id = Dict(sym => tok_to_id[str] for (sym, str) in specials)

    return Vocabulary(id_to_tok, tok_to_id, token_freqs, specials_id)
end


"""
    build_vocabulary(byte_tokens::Vector{UInt8}; cfg, id_type = UInt32)

Builds a 256-entry vocabulary (0-255) plus any special tokens
"""
function build_vocabulary(tokens::Vector{UInt8};
                          cfg::PreprocessConfiguration,
                          id_type::Type{<:Integer}=UInt32)

    str_tokens = String.(Char.(tokens))          # one-byte strings
    return build_vocabulary(str_tokens; cfg, id_type)
end


end # module _Vocabulary


# Make the builder visible to the main module
import ._Vocabulary: build_vocabulary
