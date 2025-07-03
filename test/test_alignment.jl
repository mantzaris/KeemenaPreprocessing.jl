
"Return a dummy Vocabulary with at least n tokens."
function _vocab(n)
    toks  = ["t$i" for i in 1:n]
    freqs = zeros(Int, n)
    Vocabulary(toks, Dict(toks[i]=>i for i in 1:n), freqs, Dict{Symbol,Int}())
end

"Convenience constructor for Corpus with only the needed offsets."
function _corpus(n_tokens;
                 byte_offs      = nothing,
                 char_offs      = nothing,
                 word_offs      = nothing)

    Corpus(ones(Int, n_tokens),              # token_ids (irrelevant to alignment)
           [1, n_tokens+1],                  # document_offsets
           nothing, nothing,                 # paragraph / sentence
           word_offs,
           char_offs,
           byte_offs)
end

# Offsets for toy example:  word1 = bytes 1-2, word2 = byte 3
const _BYTE_OFFS = [1,2,3,4]      # 3 bytes -> sentinel 4
const _CHAR_OFFS = [1,2,3,4]      # 3 chars -> sentinel 4
const _WORD_OFFS = [1,2,3,4]      # 3 words -> sentinel 4

const BYTE_CORP = _corpus(3, byte_offs = _BYTE_OFFS)
const CHAR_CORP = _corpus(3, char_offs = _CHAR_OFFS)
const WORD_CORP = _corpus(3, word_offs = _WORD_OFFS)

#individual alignment constructors
@testset "alignment functions" begin
    cm_bw = alignment_byte_to_word(BYTE_CORP, WORD_CORP)
    @test cm_bw.source_level      == :byte
    @test cm_bw.destination_level == :word
    @test cm_bw.alignment         == [1, 2, 3]   # ← updated

    cm_cw = alignment_char_to_word(CHAR_CORP, WORD_CORP)
    @test cm_cw.alignment == [1, 2, 3]           # ← updated

    cm_bc = alignment_byte_to_char(BYTE_CORP, CHAR_CORP)
    @test cm_bc.alignment == [1, 2, 3]           # unchanged

    wrong_word = _corpus(1, word_offs = [1, 2])
    @test_throws ArgumentError alignment_byte_to_word(BYTE_CORP, wrong_word)
end


#build_alignments! helper
@testset "build_alignments!" begin
    # Minimal LevelBundles for :byte, :character, :word
    lvls = Dict(
        :byte      => LevelBundle(BYTE_CORP, _vocab(3)),
        :character => LevelBundle(CHAR_CORP, _vocab(3)),
        :word      => LevelBundle(WORD_CORP, _vocab(2)),
    )
    bund = PreprocessBundle(lvls)

    build_alignments!(bund)         # populate
    @test keys(bund.alignments) == Set([
        (:byte, :word), (:character, :word), (:byte, :character)
    ])

    @test bund.alignments[(:byte, :word)].alignment == [1, 2, 3]
end











function _word_offsets_from_bytes(bytes::Vector{UInt8})
    offs = Int[1]
    for i in 2:length(bytes)
        # A new word starts at `i` if the previous char was space and the current is not.
        if isspace(Char(bytes[i-1])) && !isspace(Char(bytes[i]))
            push!(offs, i)
        end
    end
    push!(offs, length(bytes) + 1) #final sentinel
    return offs
end


@testset "build_alignments! on multi-doc bundle (Simple)" begin
    docs = ["Hello world.", " Another test."]  # Clear separation
    
    cfg_byte = PreprocessConfiguration(tokenizer_name=:byte, record_byte_offsets=true, record_document_offsets=true)
    btoks, boffs = tokenize_and_segment(docs, cfg_byte)
    n_bytes = length(btoks)

    byte_offs = boffs[:byte]
    doc_offs  = boffs[:document]
    char_offs = byte_offs
    word_offs = _word_offsets_from_bytes(btoks)

    n_words = length(word_offs) - 1
    n_chars = length(char_offs) - 1

    bc = Corpus(fill(1, n_bytes), doc_offs, nothing, nothing, nothing, nothing, byte_offs)
    cc = Corpus(fill(1, n_chars), doc_offs, nothing, nothing, nothing, char_offs, nothing)
    wc = Corpus(fill(1, n_words), doc_offs, nothing, nothing, word_offs, nothing, nothing)

    lvls = Dict(
        :byte      => LevelBundle(bc, _vocab(n_bytes)),
        :character => LevelBundle(cc, _vocab(n_chars)),
        :word      => LevelBundle(wc, _vocab(n_words)),
    )
    bund = PreprocessBundle(lvls)
    build_alignments!(bund)

    @test haskey(bund.alignments, (:byte, :word))
    @test haskey(bund.alignments, (:character, :word))
    @test haskey(bund.alignments, (:byte, :character))
    
    bw_alignment = bund.alignments[(:byte, :word)].alignment
    @test length(bw_alignment) == n_bytes

    println("Combined text: '", join(docs), "'")
    println("Word offsets: ", word_offs)
    println("Alignment: ", bw_alignment)
end









