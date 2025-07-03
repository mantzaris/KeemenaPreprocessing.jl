module _Alignment

using ..KeemenaPreprocessing: Corpus, CrossMap, PreprocessBundle, get_corpus

"return validated offset vector or throw"
_require_offsets(name, v) =
    (v isa AbstractVector && length(v) >= 2) ? v : throw(ArgumentError("Corpus is missing valid $name offsets (need >= 2 entries)."))

function alignment_byte_to_word(byte_c::Corpus, word_c::Corpus)::CrossMap
    bo = _require_offsets(:byte, byte_c.byte_offsets)
    wo = _require_offsets(:word, word_c.word_offsets)
    bo[end] == wo[end] || throw(ArgumentError("byte and word corpora cover different span"))

    n_bytes = length(bo) - 1  # FIXED: Use length of offsets, not sentinel value
    n_words = length(wo) - 1
    b2w = Vector{Int}(undef, n_bytes)

    # FIXED: Correct alignment logic
    @inbounds for w_idx in 1:n_words
        for b_idx in wo[w_idx]:(wo[w_idx+1] - 1)
            b2w[b_idx] = w_idx
        end
    end
    CrossMap(:byte, :word, b2w)
end

function alignment_char_to_word(char_c::Corpus, word_c::Corpus)::CrossMap
    co = _require_offsets(:character, char_c.character_offsets)
    wo = _require_offsets(:word, word_c.word_offsets)
    co[end] == wo[end] || throw(ArgumentError("char and word corpora cover different span"))

    n_chars = length(co) - 1
    n_words = length(wo) - 1
    c2w = Vector{Int}(undef, n_chars)

    @inbounds for w_idx in 1:n_words
        for c_idx in wo[w_idx]:(wo[w_idx+1] - 1)
            c2w[c_idx] = w_idx
        end
    end
    CrossMap(:character, :word, c2w)
end

function alignment_byte_to_char(byte_c::Corpus, char_c::Corpus)::CrossMap
    bo = _require_offsets(:byte, byte_c.byte_offsets)
    co = _require_offsets(:character, char_c.character_offsets)
    bo[end] == co[end] || throw(ArgumentError("byte and character corpora cover different span"))

    n_bytes = length(bo) - 1
    n_chars = length(co) - 1
    b2c = Vector{Int}(undef, n_bytes)

    @inbounds for c_idx in 1:n_chars
        for b_idx in co[c_idx]:(co[c_idx+1] - 1)
            b2c[b_idx] = c_idx
        end
    end
    CrossMap(:byte, :character, b2c)
end

function build_alignments!(bund::PreprocessBundle;
                           pairs = [(:byte, :word),
                                    (:character, :word),
                                    (:byte, :character)])
    have = keys(bund.levels)

    for (src, dst) in pairs
        (src in have && dst in have) || continue
        haskey(bund.alignments, (src, dst)) && continue

        map = if src == :byte && dst == :word
            alignment_byte_to_word(get_corpus(bund, :byte), get_corpus(bund, :word))
        elseif src == :character && dst == :word
            alignment_char_to_word(get_corpus(bund, :character), get_corpus(bund, :word))
        elseif src == :byte && dst == :character
            alignment_byte_to_char(get_corpus(bund, :byte), get_corpus(bund, :character))
        else
            nothing
        end

        map !== nothing && (bund.alignments[(src, dst)] = map)
    end
    return bund
end

end # module

import ._Alignment: alignment_byte_to_word, alignment_char_to_word, alignment_byte_to_char, build_alignments!
