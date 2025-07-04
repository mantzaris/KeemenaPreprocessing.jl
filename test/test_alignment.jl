
"Return a dummy Vocabulary with at least n tokens."
function _vocab(n)
    toks  = ["t$i" for i in 1:n]
    freqs = zeros(Int, n)
    KeemenaPreprocessing.Vocabulary(toks, Dict(toks[i]=>i for i in 1:n), freqs, Dict{Symbol,Int}())
end

"Convenience constructor for Corpus with only the needed offsets."
function _corpus(n_tokens;
                 byte_offs      = nothing,
                 char_offs      = nothing,
                 word_offs      = nothing)

    KeemenaPreprocessing.Corpus(ones(Int, n_tokens),              # token_ids (irrelevant to alignment)
           [1, n_tokens+1],                  # document_offsets
           nothing, nothing,                 # paragraph / sentence
           word_offs,
           char_offs,
           byte_offs)
end

# offsets for toy example:  word1 = bytes 1-2, word2 = byte 3
_BYTE_OFFS = [1,2,3,4]      # 3 bytes -> sentinel 4
_CHAR_OFFS = [1,2,3,4]      # 3 chars -> sentinel 4
_WORD_OFFS = [1,2,3,4]      # 3 words -> sentinel 4

BYTE_CORP = _corpus(3, byte_offs = _BYTE_OFFS)
CHAR_CORP = _corpus(3, char_offs = _CHAR_OFFS)
WORD_CORP = _corpus(3, word_offs = _WORD_OFFS)

#individual alignment constructors
@testset "alignment functions" begin
    cm_bw = KeemenaPreprocessing.alignment_byte_to_word(BYTE_CORP, WORD_CORP)
    @test cm_bw.source_level      == :byte
    @test cm_bw.destination_level == :word
    @test cm_bw.alignment         == [1, 2, 3]   # ← updated

    cm_cw = KeemenaPreprocessing.alignment_char_to_word(CHAR_CORP, WORD_CORP)
    @test cm_cw.alignment == [1, 2, 3]           # ← updated

    cm_bc = KeemenaPreprocessing.alignment_byte_to_char(BYTE_CORP, CHAR_CORP)
    @test cm_bc.alignment == [1, 2, 3]           # unchanged

    wrong_word = _corpus(1, word_offs = [1, 2])
    @test_throws ArgumentError KeemenaPreprocessing.alignment_byte_to_word(BYTE_CORP, wrong_word)
end


#build_alignments! helper
@testset "build_alignments!" begin
    # minimal LevelBundles for :byte, :character, :word
    lvls = Dict(
        :byte      => KeemenaPreprocessing.LevelBundle(BYTE_CORP, _vocab(3)),
        :character => KeemenaPreprocessing.LevelBundle(CHAR_CORP, _vocab(3)),
        :word      => KeemenaPreprocessing.LevelBundle(WORD_CORP, _vocab(2)),
    )
    bund = KeemenaPreprocessing.PreprocessBundle(lvls)

    KeemenaPreprocessing.build_alignments!(bund)         # populate
    @test keys(bund.alignments) == Set([
        (:byte, :word), (:character, :word), (:byte, :character)
    ])

    @test bund.alignments[(:byte, :word)].alignment == [1, 2, 3]
end


#------------------------------------------------

