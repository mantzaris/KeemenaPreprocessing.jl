

module _Alignment


using ..KeemenaPreprocessing: Corpus, CrossMap,
                              PreprocessBundle, get_corpus


"return validated offset vector or throw"
_require_offsets(name, v) =
    (v isa AbstractVector && length(v) >= 2) ? v : throw(ArgumentError("Corpus is missing valid $name offsets (need >= 2 entries)."))


function alignment_byte_to_word(byte_c::Corpus{IdT,OffsetT},
                                word_c::Corpus{IdT,OffsetT})::CrossMap{IdT} where {IdT,OffsetT}

    bo = _require_offsets(:byte, byte_c.byte_offsets)   # byte boundaries
    wo = _require_offsets(:word, word_c.word_offsets)   # word boundaries

    bo[end] == wo[end] || throw(ArgumentError(
        "byte and word corpora cover different span"))

    nbytes = bo[end] - 1
    b2w    = Vector{IdT}(undef, nbytes)

    @inbounds begin
        w, next_end = 1, wo[2]            # first word ends at wo[2]
        for i in 1:nbytes
            b2w[i] = w
            if i + 1 == next_end
                w      += 1
                next_end = wo[w + 1]
            end
        end
    end
    CrossMap(:byte, :word, b2w)
end


function alignment_char_to_word(char_c::Corpus{IdT,OffsetT},
                                word_c::Corpus{IdT,OffsetT})::CrossMap{IdT,OffsetT} where {IdT,OffsetT}

    co = _require_offsets(:character, char_c.character_offsets)
    wo = _require_offsets(:word,      word_c.word_offsets)

    co[end] == wo[end] || throw(ArgumentError(
        "char and word corpora cover different span"))

    nch = co[end] - 1
    c2w = Vector{IdT}(undef, nch)

    @inbounds begin
        w, next_end = 1, wo[2]
        for i in 1:nch
            c2w[i] = w
            if i + 1 == next_end
                w      += 1
                next_end = wo[w + 1]
            end
        end
    end
    CrossMap(:character, :word, c2w)
end


function alignment_byte_to_char(byte_c::Corpus{IdT,OffsetT},
                                char_c::Corpus{IdT,OffsetT})::CrossMap{IdT,OffsetT} where {IdT,OffsetT}

    bo = _require_offsets(:byte,      byte_c.byte_offsets)
    co = _require_offsets(:character, char_c.character_offsets)

    bo[end] == co[end] || throw(ArgumentError(
        "byte and character corpora cover different span"))

    nbytes = bo[end] - 1
    b2c    = Vector{IdT}(undef, nbytes)

    @inbounds begin
        ch, next_end = 1, co[2]
        for i in 1:nbytes
            b2c[i] = ch
            if i + 1 == next_end
                ch += 1
                next_end = co[ch + 1]
            end
        end
    end
    CrossMap(:byte, :character, b2c)
end


function build_alignments!(bund::PreprocessBundle;
                           pairs = [(:byte,      :word),
                                    (:character, :word),
                                    (:byte,      :character)])

    have = keys(bund.levels)

    for (src, dst) in pairs
        (src in have && dst in have) || continue           # both levels?
        haskey(bund.alignments, (src, dst)) && continue    # already built?

        map = if src == :byte && dst == :word
            alignment_byte_to_word(get_corpus(bund, :byte),
                                   get_corpus(bund, :word))

        elseif src == :character && dst == :word
            alignment_char_to_word(get_corpus(bund, :character),
                                   get_corpus(bund, :word))

        elseif src == :byte && dst == :character
            alignment_byte_to_char(get_corpus(bund, :byte),
                                   get_corpus(bund, :character))

        else
            nothing     # unsupported pair
        end

        map !== nothing && (bund.alignments[(src, dst)] = map)
    end
    return bund
end


end # module


import ._Alignment: alignment_byte_to_word, alignment_char_to_word, alignment_byte_to_char, build_alignments!