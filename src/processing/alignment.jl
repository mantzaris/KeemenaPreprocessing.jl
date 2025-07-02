

module _Alignment


using ..KeemenaPreprocessing: Corpus, CrossMap


"Return validated offset vector or throw."
_require_offsets(name, v) =
    (v isa AbstractVector && length(v) >= 2) ? v : throw(ArgumentError("Corpus is missing valid $name offsets (need ≥ 2 entries)."))


function alignment_byte_to_word(c::Corpus{<:Integer,OffsetT})::CrossMap{OffsetT} where {OffsetT}
    bo = _require_offsets(:byte, c.byte_offsets)
    _  = _require_offsets(:word, c.word_offsets)

    nbytes = bo[end] - 1
    b2w    = Vector{OffsetT}(undef, nbytes)

    @inbounds begin
        w, next_end = 1, bo[2]
        for i in 1:nbytes
            b2w[i] = w
            if i + 1 == next_end
                w += 1
                next_end = bo[w + 1]
            end
        end
    end
    CrossMap(:byte, :word, b2w)
end


function alignment_char_to_word(char_c::Corpus{<:Integer,OffsetT},
                                word_c::Corpus{<:Integer,OffsetT})::CrossMap{OffsetT} where {OffsetT}

    co = _require_offsets(:character, char_c.character_offsets)  # char indices
    wo = _require_offsets(:word,      word_c.word_offsets)       # word boundaries

    co[end] == wo[end] ||
        throw(ArgumentError("char and word corpora cover different span"))

        
    nch  = co[end] - 1
    c2w  = Vector{OffsetT}(undef, nch)

    @inbounds begin
        w, next_end = 1, wo[2]
        for i in 1:nch
            c2w[i] = w
            if i + 1 == next_end         # test against wo
                w       += 1
                next_end = wo[w + 1]     # advance word boundary
            end
        end
    end
end


function alignment_byte_to_char(c::Corpus{<:Integer,OffsetT})::CrossMap{OffsetT} where {OffsetT}
    bo = _require_offsets(:byte,      c.byte_offsets)
    co = _require_offsets(:character, c.character_offsets)

    nbytes = bo[end] - 1
    b2c    = Vector{OffsetT}(undef, nbytes)

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


end # module


import ._Alignment: alignment_byte_to_word, alignment_char_to_word, alignment_byte_to_char