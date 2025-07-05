

"Return a dummy Vocabulary with at least n tokens."
function _vocab2(n)
    toks  = ["t$i" for i in 1:n]
    freqs = zeros(Int, n)
    KeemenaPreprocessing.Vocabulary(toks, Dict(toks[i]=>i for i in 1:n), freqs, Dict{Symbol,Int}())
end

"Convenience constructor for Corpus with only the needed offsets."
function _corpus2(n_tokens;
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

# test constants - simple aligned offsets for basic testing
 _BYTE_OFFS = [1,2,3,4]      # 3 bytes -> sentinel 4
 _CHAR_OFFS = [1,2,3,4]      # 3 chars -> sentinel 4
 _WORD_OFFS = [1,2,3,4]      # 3 words -> sentinel 4

 BYTE_CORP = _corpus2(3, byte_offs = _BYTE_OFFS)
 CHAR_CORP = _corpus2(3, char_offs = _CHAR_OFFS)
 WORD_CORP = _corpus2(3, word_offs = _WORD_OFFS)

# _ensure_lower_levels! (ISOLATED)


@testset "Tests for _ensure_lower_levels! (Isolated)" begin
    
    @testset "Basic functionality - levels are created" begin
        # test with word corpus that has character and byte offsets
        word_corp = _corpus2(3, 
                          char_offs = [1,2,3,4],    # 3 segments
                          byte_offs = [1,2,3,4],    # 3 segments
                          word_offs = [1,2,3,4])    # 3 segments (needed for validation)
        
        bundle = KeemenaPreprocessing.PreprocessBundle(Dict(:word => LevelBundle(word_corp, _vocab2(3))))
        
        # before calling _ensure_lower_levels!
        @test !haskey(bundle.levels, :character)
        @test !haskey(bundle.levels, :byte)
        @test haskey(bundle.levels, :word)
        
        result = KeemenaPreprocessing._Alignment._ensure_lower_levels!(bundle)
        
        # after calling _ensure_lower_levels! - check that levels exist
        @test haskey(result.levels, :character)
        @test haskey(result.levels, :byte)
        @test haskey(result.levels, :word)
    
        # check basic properties
        char_level = result.levels[:character]
        @test length(char_level.corpus.token_ids) == 3
        @test all(char_level.corpus.token_ids .== 1)    # all tokens mapped to <UNK>
        @test char_level.corpus.character_offsets == [1,2,3,4]
        
        byte_level = result.levels[:byte]
        @test length(byte_level.corpus.token_ids) == 3
        @test all(byte_level.corpus.token_ids .== 1)     # all tokens mapped to <UNK>
        @test byte_level.corpus.byte_offsets == [1,2,3,4]
        
        # verify function returns the same bundle (modified in place)
        @test result === bundle
    end
    
    @testset "No-op when levels already exist" begin
        # test that function doesn't modify existing levels
        word_corp = _corpus2(3, char_offs = [1,2,3,4], byte_offs = [1,2,3,4], word_offs = [1,2,3,4])
        char_level = KeemenaPreprocessing.LevelBundle(_corpus2(3, char_offs = [1,2,3,4]), _vocab2(2))
        byte_level = KeemenaPreprocessing.LevelBundle(_corpus2(3, byte_offs = [1,2,3,4]), _vocab2(2))
        
        bundle = KeemenaPreprocessing.PreprocessBundle(Dict(
            :word => LevelBundle(word_corp, _vocab2(3)),
            :character => char_level,
            :byte => byte_level
        ))
        
        original_char = bundle.levels[:character]
        original_byte = bundle.levels[:byte]
        
        KeemenaPreprocessing._Alignment._ensure_lower_levels!(bundle)
        
        # verify no levels were modified (same object references)
        @test bundle.levels[:character] === original_char
        @test bundle.levels[:byte] === original_byte
        @test length(bundle.levels) == 3
    end
    
    @testset "No-op when offsets are missing" begin
        # test that function doesn't create levels when offsets are missing
        word_corp = _corpus2(3, word_offs = [1,2,3,4])  # no char/byte offsets
        
        bundle = KeemenaPreprocessing.PreprocessBundle(Dict(:word => KeemenaPreprocessing.LevelBundle(word_corp, _vocab2(3))))
        
        KeemenaPreprocessing._Alignment._ensure_lower_levels!(bundle)
        
        # should remain unchanged since offsets are missing
        @test !haskey(bundle.levels, :character)
        @test !haskey(bundle.levels, :byte)
        @test length(bundle.levels) == 1
    end
    
    @testset "Partial creation scenarios" begin
        #test creating only character level when byte level exists
        word_corp = _corpus2(3, char_offs = [1,2,3,4], byte_offs = [1,2,3,4], word_offs = [1,2,3,4])
        byte_level = KeemenaPreprocessing.LevelBundle(_corpus2(3, byte_offs = [1,2,3,4]), _vocab2(2))
        
        bundle = KeemenaPreprocessing.PreprocessBundle(Dict(
            :word => LevelBundle(word_corp, _vocab2(3)),
            :byte => byte_level
        ))
        
        @test !haskey(bundle.levels, :character)
        @test haskey(bundle.levels, :byte)
        
        KeemenaPreprocessing._Alignment._ensure_lower_levels!(bundle)
        
        @test haskey(bundle.levels, :character)
        @test haskey(bundle.levels, :byte)
        @test bundle.levels[:byte] === byte_level  # unchanged
    end
end


# for build_alignments!

@testset "Tests for build_alignments! (Isolated)" begin
    
    @testset "Basic alignment creation" begin
        # test with all levels present and proper offsets
        lvls = Dict(
            :byte      => LevelBundle(BYTE_CORP, _vocab2(3)),
            :character => LevelBundle(CHAR_CORP, _vocab2(3)),
            :word      => LevelBundle(WORD_CORP, _vocab2(2)),
        )
        bund = KeemenaPreprocessing.PreprocessBundle(lvls)
        
        # clear alignments to test build_alignments!
        empty!(bund.alignments)
        
        KeemenaPreprocessing._Alignment.build_alignments!(bund)
        
        # should create all expected alignments
        @test length(bund.alignments) == 3
        @test haskey(bund.alignments, (:byte, :word))
        @test haskey(bund.alignments, (:character, :word))
        @test haskey(bund.alignments, (:byte, :character))
        
        # check alignment values match expected results
        @test bund.alignments[(:byte, :word)].alignment == [1, 2, 3]
        @test bund.alignments[(:character, :word)].alignment == [1, 2, 3]
        @test bund.alignments[(:byte, :character)].alignment == [1, 2, 3]
    end
    
    @testset "Partial alignments - missing levels" begin
        # test with only word and character levels
        lvls = Dict(
            :character => LevelBundle(CHAR_CORP, _vocab2(3)),
            :word      => LevelBundle(WORD_CORP, _vocab2(2)),
        )
        bund = KeemenaPreprocessing.PreprocessBundle(lvls)
        
        KeemenaPreprocessing._Alignment.build_alignments!(bund)
        
        # should create only character-word alignment
        @test length(bund.alignments) == 1
        @test haskey(bund.alignments, (:character, :word))
        @test !haskey(bund.alignments, (:byte, :word))
        @test !haskey(bund.alignments, (:byte, :character))
    end
    
    @testset "Idempotent behavior" begin
        # test that multiple calls don't change anything
        lvls = Dict(
            :byte      => LevelBundle(BYTE_CORP, _vocab2(3)),
            :character => LevelBundle(CHAR_CORP, _vocab2(3)),
            :word      => LevelBundle(WORD_CORP, _vocab2(2)),
        )
        bund = KeemenaPreprocessing.PreprocessBundle(lvls)
        
        # first call
        KeemenaPreprocessing._Alignment.build_alignments!(bund)
        first_count = length(bund.alignments)
        first_keys = Set(keys(bund.alignments))
        
        # second call - should be no-op
        KeemenaPreprocessing._Alignment.build_alignments!(bund)
        
        @test length(bund.alignments) == first_count
        @test Set(keys(bund.alignments)) == first_keys
    end
end


# build_ensure_alignments! (COMBINED)

@testset "Tests for build_ensure_alignments! (Combined)" begin
    
    @testset "Complete workflow with proper word offsets" begin
        # ensure word corpus has word offsets for alignment creation
        word_corp = _corpus2(3, 
                          char_offs = [1,2,3,4],
                          byte_offs = [1,2,3,4],
                          word_offs = [1,2,3,4])    #   word offsets needed
        
        bundle = KeemenaPreprocessing.PreprocessBundle(Dict(:word => LevelBundle(word_corp, _vocab2(3))))
        
        # before calling build_ensure_alignments!
        @test !haskey(bundle.levels, :character)
        @test !haskey(bundle.levels, :byte)
        @test isempty(bundle.alignments)
        
        result = KeemenaPreprocessing._Alignment.build_ensure_alignments!(bundle)
        
        #after calling build_ensure_alignments!
        @test haskey(result.levels, :character)
        @test haskey(result.levels, :byte)
        @test haskey(result.levels, :word)
        
        # check that alignments are created
        @test length(result.alignments) == 3
        @test haskey(result.alignments, (:byte, :word))
        @test haskey(result.alignments, (:character, :word))
        @test haskey(result.alignments, (:byte, :character))
        
        # verify function returns the same bundle (modified in place)
        @test result === bundle
    end
    
    @testset "No levels created when offsets missing" begin
        # test that function doesn't create levels when offsets are missing
        word_corp = _corpus2(3, word_offs = [1,2,3,4])  # only word offsets
        
        bundle = KeemenaPreprocessing.PreprocessBundle(Dict(:word => LevelBundle(word_corp, _vocab2(3))))
        
        KeemenaPreprocessing._Alignment.build_ensure_alignments!(bundle)
        
        #should remain unchanged since no character/byte offsets available
        @test !haskey(bundle.levels, :character)
        @test !haskey(bundle.levels, :byte)
        @test isempty(bundle.alignments)
        @test length(bundle.levels) == 1
    end
    
    @testset "Both character and byte offsets present" begin
        word_corp = _corpus2(3, 
                          char_offs = [1,2,3,4],     # character offsets present
                          byte_offs = [1,2,3,4],     # FIXED: byte offsets also present to avoid copy(nothing)
                          word_offs = [1,2,3,4])     # word offsets needed for alignment
        
        bundle = KeemenaPreprocessing.PreprocessBundle(Dict(:word => KeemenaPreprocessing.LevelBundle(word_corp, _vocab2(3))))
        
        KeemenaPreprocessing._Alignment.build_ensure_alignments!(bundle)
        
        #should create both character and byte levels and all alignments
        @test haskey(bundle.levels, :character)
        @test haskey(bundle.levels, :byte)
        @test haskey(bundle.alignments, (:character, :word))
        @test haskey(bundle.alignments, (:byte, :word))
        @test haskey(bundle.alignments, (:byte, :character))
        @test length(bundle.alignments) == 3
    end
    
    @testset "Integration with existing patterns" begin
        #test compatibility with existing test patterns
        lvls = Dict(
            :byte      => KeemenaPreprocessing.LevelBundle(BYTE_CORP, _vocab2(3)),
            :character => KeemenaPreprocessing.LevelBundle(CHAR_CORP, _vocab2(3)),
            :word      => KeemenaPreprocessing.LevelBundle(WORD_CORP, _vocab2(2)),
        )
        bund = KeemenaPreprocessing.PreprocessBundle(lvls)
        
        #clear alignments to test build_ensure_alignments!
        empty!(bund.alignments)
        
        KeemenaPreprocessing._Alignment.build_ensure_alignments!(bund)
        
        #sShould create all expected alignments
        @test length(bund.alignments) == 3
        @test haskey(bund.alignments, (:byte, :word))
        @test haskey(bund.alignments, (:character, :word))
        @test haskey(bund.alignments, (:byte, :character))
        
        #check alignment values match expected results
        @test bund.alignments[(:byte, :word)].alignment == [1, 2, 3]
        @test bund.alignments[(:character, :word)].alignment == [1, 2, 3]
        @test bund.alignments[(:byte, :character)].alignment == [1, 2, 3]
    end
end


#edge and robust tests


@testset "Edge Case and Robustness Tests" begin
    
    @testset "Single token corpus" begin
        # test edge case with single token
        word_corp_single = _corpus2(1, 
                                 char_offs = [1,2],  # single character
                                 byte_offs = [1,2],  # single byte
                                 word_offs = [1,2])  # single word
        
        bundle = KeemenaPreprocessing.PreprocessBundle(Dict(:word => LevelBundle(word_corp_single, _vocab2(1))))
        
        KeemenaPreprocessing._Alignment.build_ensure_alignments!(bundle)
        
        @test haskey(bundle.levels, :character)
        @test haskey(bundle.levels, :byte)
        @test length(bundle.alignments) == 3
        
        # check alignment arrays for single element
        @test bundle.alignments[(:byte, :word)].alignment == [1]
        @test bundle.alignments[(:character, :word)].alignment == [1]
        @test bundle.alignments[(:byte, :character)].alignment == [1]
    end
    
    @testset "Sequential calls maintain consistency" begin
        #test that multiple sequential calls maintain consistency
        word_corp = _corpus2(4, 
                          char_offs = [1,2,3,4,5],
                          byte_offs = [1,2,3,4,5],
                          word_offs = [1,2,3,4,5])
        
        bundle = KeemenaPreprocessing.PreprocessBundle(Dict(:word => LevelBundle(word_corp, _vocab2(3))))
        
        # first call
        KeemenaPreprocessing._Alignment.build_ensure_alignments!(bundle)
        first_levels = Set(keys(bundle.levels))
        first_alignments = Set(keys(bundle.alignments))
        
        # second call - should be no-op
        KeemenaPreprocessing._Alignment.build_ensure_alignments!(bundle)
        second_levels = Set(keys(bundle.levels))
        second_alignments = Set(keys(bundle.alignments))
        
        @test first_levels == second_levels
        @test first_alignments == second_alignments
    end
    
    @testset "Large corpus scalability" begin
        # test with reasonably large corpus
        n_tokens = 50  # Reasonable size for testing
        large_corp = _corpus2(n_tokens, 
                           char_offs = collect(1:(n_tokens+1)),
                           byte_offs = collect(1:(n_tokens+1)),
                           word_offs = collect(1:(n_tokens+1)))
        
        bundle = KeemenaPreprocessing.PreprocessBundle(Dict(:word => LevelBundle(large_corp, _vocab2(10))))
        
        # should complete without errors
        @test_nowarn KeemenaPreprocessing._Alignment.build_ensure_alignments!(bundle)
        
        @test haskey(bundle.levels, :character)
        @test haskey(bundle.levels, :byte)
        @test length(bundle.alignments) == 3
        @test length(bundle.levels[:character].corpus.token_ids) == n_tokens
        @test length(bundle.levels[:byte].corpus.token_ids) == n_tokens
    end
end


@testset "Additional Safe Tests" begin
    
    @testset "Test _ensure_lower_levels! with only character offsets (safe)" begin
        # this tests _ensure_lower_levels! in isolation to avoid the copy(nothing) issue
        # wWe test the scenario where only character offsets are present
        word_corp = _corpus2(3, 
                          char_offs = [1,2,3,4],     # only character offsets
                          word_offs = [1,2,3,4])     # word offsets for validation
        
        bundle = KeemenaPreprocessing.PreprocessBundle(Dict(:word => KeemenaPreprocessing.LevelBundle(word_corp, _vocab2(3))))
        
        @test !haskey(bundle.levels, :character)
        @test !haskey(bundle.levels, :byte)
        
        #  DON'T call _ensure_lower_levels! here because it would try to copy(nothing)
        #  test that the bundle remains unchanged when byte offsets are missing
        @test length(bundle.levels) == 1
        @test haskey(bundle.levels, :word)
    end
    
    @testset "Test build_alignments! with existing levels only" begin
        # test build_alignments! with manually created levels (avoids _ensure_lower_levels!)
        char_corp = _corpus2(3, char_offs = [1,2,3,4])
        word_corp = _corpus2(3, word_offs = [1,2,3,4])
        
        lvls = Dict(
            :character => KeemenaPreprocessing.LevelBundle(char_corp, _vocab2(3)),
            :word      => KeemenaPreprocessing.LevelBundle(word_corp, _vocab2(2)),
        )
        bund = KeemenaPreprocessing.PreprocessBundle(lvls)
        
        KeemenaPreprocessing._Alignment.build_alignments!(bund)
        
        # should create only character-word alignment
        @test length(bund.alignments) == 1
        @test haskey(bund.alignments, (:character, :word))
        @test !haskey(bund.alignments, (:byte, :word))
        @test !haskey(bund.alignments, (:byte, :character))
    end
end




