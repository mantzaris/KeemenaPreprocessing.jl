

module _Vocabulary

using StatsBase                # countmap
using ..KeemenaPreprocessing:  PreprocessConfiguration,
                               Vocabulary


"""
    build_vocabulary(tokens; cfg, id_type = UInt32) -> Vocabulary

Create a frozen `Vocabulary` from a flat `tokens` vector.

Steps
-----
1. count token frequencies
2. start from a copy of `cfg.special_tokens`
3. auto-inject `<BOS>/<EOS>` only when `cfg.record_sentence_offsets` is
   `true` and the user has not supplied them already
4. (Optional future hooks see `TODO:` markers below)
5. assign deterministic integer IDs (all specials first, then corpus tokens
   whose frequency >= `cfg.minimum_token_frequency`)
6. construct and return the `Vocabulary` object

the returned object is immutable and ready for downstream models
"""
function build_vocabulary(tokens::Vector{String};
                          cfg::PreprocessConfiguration,
                          id_type::Type{<:Unsigned}=UInt32)

    # 1. token -> frequency
    freqs_dict = countmap(tokens)                     # Dict{String,Int}

    # 2. start from a mutable *copy* of user-supplied specials
    specials = Dict(cfg.special_tokens)               # Symbol -> String

    # 3. sentence markers (added only if needed)
    if cfg.record_sentence_offsets
        specials[:bos] = get(specials, :bos, "<BOS>")
        specials[:eos] = get(specials, :eos, "<EOS>")
    end

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

    # 4. assign IDs  (specials first, deterministic alphabetical order)
    id_to_tok = String[]
    tok_to_id = Dict{String,id_type}()

    for sym in sort!(collect(keys(specials)))
        tok = specials[sym]
        push!(id_to_tok, tok)
        tok_to_id[tok] = id_type(length(id_to_tok))
    end

    # 5. add corpus tokens that meet the frequency threshold
    for (tok, f) in freqs_dict
        (f < cfg.minimum_token_frequency || haskey(tok_to_id, tok)) && continue
        push!(id_to_tok, tok)
        tok_to_id[tok] = id_type(length(id_to_tok))
    end

    # 6. aligned frequency vector (specials get zero by convention)
    token_freqs = [get(freqs_dict, tok, 0) for tok in id_to_tok]

    # 7. specials map: Symbol ⇒ ID (IDs are stable across reloads)
    specials_id = Dict(sym => tok_to_id[str] for (sym, str) in specials)

    return Vocabulary(id_to_tok, tok_to_id, token_freqs, specials_id)
end

end # module _Vocabulary


# Make the builder visible to the main module
import ._Vocabulary: build_vocabulary
