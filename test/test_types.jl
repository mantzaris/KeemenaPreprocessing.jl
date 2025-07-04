

function _vocab()
    Vocabulary(["a","b"], Dict("a"=>1, "b"=>2),
               [10, 5],
               Dict(:unk => 1))
end


function _corpus(token_ids::Vector{Int})
    n = length(token_ids)
    KeemenaPreprocessing.Corpus(token_ids,  # token_ids
           [1, n+1],                # document_offsets
           nothing, nothing,        # paragraph/sentence
           collect(1:n+1),          # word_offsets  (1-based sentinel)
           nothing, nothing)        # char / byte
end


@testset "LevelBundle" begin
    vocab = _vocab()

    good  = KeemenaPreprocessing.LevelBundle(_corpus([1,2]), vocab)
    @test good.corpus.token_ids == [1,2]

    @test_throws ErrorException KeemenaPreprocessing.LevelBundle(_corpus([1,3]), vocab)  # 3 > vocab size
    @test_throws ErrorException KeemenaPreprocessing.LevelBundle(_corpus([0,1]), vocab)  # id < 1
end


# validate_offsets helper
@testset "validate_offsets" begin
    corp_ok = _corpus([1,2,1])           # helper from earlier
    @test KeemenaPreprocessing.validate_offsets(corp_ok, :word) == true   # passes, returns Bool

    # build a corpus with a wrong word_offsets vector
    corp_bad = let c = corp_ok
        KeemenaPreprocessing.Corpus(c.token_ids, c.document_offsets, c.paragraph_offsets,
               c.sentence_offsets, [1,3,4],          # bad sentinel/length
               c.character_offsets, c.byte_offsets)
    end
    @test_throws ErrorException KeemenaPreprocessing.validate_offsets(corp_bad, :word)
end

# crossMap constructor and basics

@testset "CrossMap" begin
    cm = KeemenaPreprocessing.CrossMap(:byte, :word, [1,1,2,2])
    @test length(cm) == 4
    @test cm[3] == 2
    @test cm.source_level == :byte
end

#preprocessBundle construction and alignment checks

@testset "PreprocessBundle" begin
    lb   = KeemenaPreprocessing.LevelBundle(_corpus([1,2,1]), _vocab())
    lvl  = Dict(:word => lb)

    # alignment matches source length -> OK
    cm   = KeemenaPreprocessing.CrossMap(:word, :word, [1,2,3])   # identity (silly but valid)
    bun  = KeemenaPreprocessing.PreprocessBundle(lvl; alignments = Dict((:word,:word)=>cm))
    @test collect(keys(bun.levels)) == [:word]

    # wrong length triggers error
    bad_cm = KeemenaPreprocessing.CrossMap(:word, :word, [1,1])
    @test_throws ErrorException KeemenaPreprocessing.PreprocessBundle(lvl; alignments = Dict((:word,:word)=>bad_cm))
end

# add_level! duplicate-guard & with_extras

@testset "add_level! and with_extras" begin
    lb    = KeemenaPreprocessing.LevelBundle(_corpus([1]), _vocab())
    bun   = KeemenaPreprocessing.PreprocessBundle(Dict(:word => lb))

    @test_throws ErrorException KeemenaPreprocessing.add_level!(bun, :word, lb)  # duplicate

    new   = KeemenaPreprocessing.with_extras(bun, (note = "hello",))
    @test new.extras != bun.extras
    @test new.levels == bun.levels         # unchanged copy
end

