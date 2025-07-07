module _Alignment

using ..KeemenaPreprocessing: Corpus, CrossMap, PreprocessBundle, LevelBundle, get_corpus, add_level!, Vocabulary

"return validated offset vector or throw"
_require_offsets(name, v) =
    (v isa AbstractVector && length(v) >= 2) ? v : throw(ArgumentError("Corpus is missing valid $name offsets (need >= 2 entries)."))


"""
    alignment_byte_to_word(byte_c, word_c) -> CrossMap

Construct a byte -> word `CrossMap` that projects each **byte index**
in `byte_c` onto the **word index** in `word_c` that contains it.

### Preconditions
* `byte_c` **must** have a **non-`nothing`** `byte_offsets` vector  
  (checked via the private helper `_require_offsets`).
* `word_c` **must** have a **non-`nothing`** `word_offsets` vector.
* Both corpora must span the **same token range**  
  `byte_offsets[end] == word_offsets[end]`; otherwise an
  `ArgumentError` is thrown.

### Arguments
| name     | type      | description |
|----------|-----------|-------------|
| `byte_c` | `Corpus`  | Corpus tokenised at the **byte** level. |
| `word_c` | `Corpus`  | Corpus tokenised at the **word** level. |

### Algorithm
1. Retrieve the sentinel-terminated offset vectors  
   `bo = byte_c.byte_offsets` and `wo = word_c.word_offsets`.
2. Allocate `b2w :: Vector{Int}(undef, n_bytes)` where
   `n_bytes = length(bo) - 1`.
3. For each word index `w_idx` fill the slice
   `wo[w_idx] : wo[w_idx+1]-1` with `w_idx`, thereby assigning every byte
   position to the word that begins at `wo[w_idx]`.
4. Return `CrossMap(:byte, :word, b2w)`.

The output vector has length **`n_bytes`** (no sentinel) because every byte
token receives one word identifier.

### Returns
A `CrossMap` whose fields are:

```julia
source_level      == :byte
destination_level == :word
alignment         :: Vector{Int}  # length = n_bytes
```

### Errors
* `ArgumentError` if either corpus lacks the necessary offsets.
* `ArgumentError` when the overall spans differ.

### Example
```julia
b2w = alignment_byte_to_word(byte_corpus, word_corpus)
word_index_of_42nd_byte = b2w.alignment[42]
```
"""
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



const _DUMMY_VOCAB = Vocabulary(["<UNK>"], Dict("<UNK>" => 1),
                                [0], Dict(:unk => 1))

"""
    _ensure_lower_levels!(bundle)

Populate :character and :byte levels (and vocabularies) if they are missing but
the necessary offset vectors are already stored in the *word* corpus.
"""
function _ensure_lower_levels!(bundle::PreprocessBundle)
    wcorp  = get_corpus(bundle, :word)

    add_lvl(lvl, offs) = !haskey(bundle.levels, lvl) && offs !== nothing

    # character level 
    if add_lvl(:character, wcorp.character_offsets)
        n  = length(wcorp.character_offsets) - 1
        lb = LevelBundle(
                 Corpus(fill(1,n),                      # token_ids -> <UNK>
                        wcorp.document_offsets,        # share doc segmentation
                        nothing, nothing, nothing,
                        copy(wcorp.character_offsets), # character_offsets
                        copy(wcorp.byte_offsets)),     # also carry byte_offsets
                 _DUMMY_VOCAB)
        add_level!(bundle, :character, lb)
    end

    # byte level 
    if add_lvl(:byte, wcorp.byte_offsets)
        n  = length(wcorp.byte_offsets) - 1
        lb = LevelBundle(
                 Corpus(fill(1,n),
                        wcorp.document_offsets,
                        nothing, nothing, nothing,
                        nothing, copy(wcorp.byte_offsets)),
                 _DUMMY_VOCAB)
        add_level!(bundle, :byte, lb)
    end

    return bundle
end


"""
    build_ensure_alignments!(bundle)

Guarantee that :byte, :character, and :word levels (if offsets exist) and their
default alignments are present.  Idempotent.
"""
function build_ensure_alignments!(bundle::PreprocessBundle)
    _ensure_lower_levels!(bundle)
    build_alignments!(bundle)
    return bundle
end


end # module

import ._Alignment: alignment_byte_to_word, alignment_char_to_word, alignment_byte_to_char, build_alignments!, _ensure_lower_levels!, build_ensure_alignments!
