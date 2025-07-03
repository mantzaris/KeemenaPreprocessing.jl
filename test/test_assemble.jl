
function _test_vocab(tokens::Vector{String}; include_unk=true)
    if include_unk && !("<UNK>" in tokens)
        tokens = ["<UNK>", tokens...]
    end
    
    token_to_id = Dict(tokens[i] => i for i in 1:length(tokens))
    freqs = ones(Int, length(tokens))
    special_tokens = include_unk ? Dict(:unk => 1) : Dict{Symbol,Int}()
    
    return Vocabulary(tokens, token_to_id, freqs, special_tokens)
end

@testset "_Assemble Module Tests (Corrected)" begin

    @testset "Basic functionality" begin
        # Simple test case with valid tokenizer
        tokens = ["hello", "world", "test"]
        vocab = _test_vocab(["hello", "world", "test"])
        offsets = Dict(:document => [1, 4])  # Single document
        cfg = PreprocessConfiguration(tokenizer_name=:whitespace)  # Valid tokenizer
        
        bundle = assemble_bundle(tokens, offsets, vocab, cfg)
        
        @test haskey(bundle.levels, :word)  # :whitespace maps to :word
        @test length(bundle.levels) == 1
        
        corpus = bundle.levels[:word].corpus
        @test corpus.token_ids == [2, 3, 4]  # Mapped to vocab IDs (1 is <UNK>)
        @test corpus.document_offsets == [1, 4]
        @test corpus.paragraph_offsets === nothing
        @test corpus.sentence_offsets === nothing
        @test corpus.word_offsets === nothing
        @test corpus.character_offsets === nothing
        @test corpus.byte_offsets === nothing
        
        @test bundle.levels[:word].vocabulary === vocab
        @test bundle.metadata isa PipelineMetadata
    end

    @testset "Different tokenizer types" begin
        tokens = ["a", "b", "c"]
        vocab = _test_vocab(["a", "b", "c"])
        offsets = Dict(:document => [1, 4])
        
        # Test byte tokenizer
        cfg_byte = PreprocessConfiguration(tokenizer_name=:byte)
        bundle_byte = assemble_bundle(tokens, offsets, vocab, cfg_byte)
        @test haskey(bundle_byte.levels, :byte)
        
        # Test char tokenizer
        cfg_char = PreprocessConfiguration(tokenizer_name=:char)
        bundle_char = assemble_bundle(tokens, offsets, vocab, cfg_char)
        @test haskey(bundle_char.levels, :character)
        
        # Test unicode tokenizer (maps to :word)
        cfg_unicode = PreprocessConfiguration(tokenizer_name=:unicode)
        bundle_unicode = assemble_bundle(tokens, offsets, vocab, cfg_unicode)
        @test haskey(bundle_unicode.levels, :word)
        
        # Test whitespace tokenizer (maps to :word)
        cfg_whitespace = PreprocessConfiguration(tokenizer_name=:whitespace)
        bundle_whitespace = assemble_bundle(tokens, offsets, vocab, cfg_whitespace)
        @test haskey(bundle_whitespace.levels, :word)
    end

    @testset "Byte tokens (UInt8)" begin
        # Test with UInt8 tokens (byte-level)
        byte_tokens = UInt8[72, 101, 108, 108, 111]  # "Hello" in bytes
        vocab = _test_vocab(["H", "e", "l", "o"])
        offsets = Dict(:document => [1, 6])
        cfg = PreprocessConfiguration(tokenizer_name=:byte)
        
        bundle = assemble_bundle(byte_tokens, offsets, vocab, cfg)
        
        corpus = bundle.levels[:byte].corpus
        @test corpus.token_ids == [2, 3, 4, 4, 5]  # H=2, e=3, l=4, l=4, o=5
    end

    @testset "Unknown token handling" begin
        tokens = ["known", "unknown", "also_known"]
        vocab = _test_vocab(["known", "also_known"])  # "unknown" not in vocab
        offsets = Dict(:document => [1, 4])
        cfg = PreprocessConfiguration(tokenizer_name=:whitespace)
        
        bundle = assemble_bundle(tokens, offsets, vocab, cfg)
        
        corpus = bundle.levels[:word].corpus
        @test corpus.token_ids == [2, 1, 3]  # known=2, unknown=1(<UNK>), also_known=3
    end

    @testset "Missing UNK token error" begin
        tokens = ["test"]
        vocab = _test_vocab(["test"], include_unk=false)  # No <UNK> token
        offsets = Dict(:document => [1, 2])
        cfg = PreprocessConfiguration(tokenizer_name=:whitespace)
        
        @test_throws ArgumentError assemble_bundle(tokens, offsets, vocab, cfg)
    end

    @testset "All offset types" begin
        tokens = ["hello", "world", "test", "sentence"]
        vocab = _test_vocab(["hello", "world", "test", "sentence"])
        
        # Include all possible offset types
        offsets = Dict(
            :document  => [1, 5],
            :paragraph => [1, 3, 5],
            :sentence  => [1, 3, 4, 5],
            :word      => [1, 2, 3, 4, 5],
            :character => [1, 6, 12, 17, 26],
            :byte      => [1, 6, 12, 17, 26]
        )
        cfg = PreprocessConfiguration(tokenizer_name=:whitespace)
        
        bundle = assemble_bundle(tokens, offsets, vocab, cfg)
        
        corpus = bundle.levels[:word].corpus
        @test corpus.document_offsets == [1, 5]
        @test corpus.paragraph_offsets == [1, 3, 5]
        @test corpus.sentence_offsets == [1, 3, 4, 5]
        @test corpus.word_offsets == [1, 2, 3, 4, 5]
        @test corpus.character_offsets == [1, 6, 12, 17, 26]
        @test corpus.byte_offsets == [1, 6, 12, 17, 26]
    end

    @testset "Default document offsets" begin
        # Test when document offsets are not provided
        tokens = ["a", "b", "c"]
        vocab = _test_vocab(["a", "b", "c"])
        offsets = Dict{Symbol,Vector{Int}}()  # Empty offsets
        cfg = PreprocessConfiguration(tokenizer_name=:whitespace)
        
        bundle = assemble_bundle(tokens, offsets, vocab, cfg)
        
        corpus = bundle.levels[:word].corpus
        @test corpus.document_offsets == [1, 4]  # Default: single document
    end

    @testset "Empty tokens" begin
        tokens = String[]
        vocab = _test_vocab(String[])
        offsets = Dict(:document => [1, 1])  # Empty document
        cfg = PreprocessConfiguration(tokenizer_name=:whitespace)
        
        bundle = assemble_bundle(tokens, offsets, vocab, cfg)
        
        corpus = bundle.levels[:word].corpus
        @test length(corpus.token_ids) == 0
        @test corpus.document_offsets == [1, 1]
    end

    @testset "Multiple documents" begin
        tokens = ["doc1", "word1", "doc2", "word2", "word3"]
        vocab = _test_vocab(["doc1", "word1", "doc2", "word2", "word3"])
        offsets = Dict(:document => [1, 3, 6])  # Two documents
        cfg = PreprocessConfiguration(tokenizer_name=:whitespace)
        
        bundle = assemble_bundle(tokens, offsets, vocab, cfg)
        
        corpus = bundle.levels[:word].corpus
        @test corpus.token_ids == [2, 3, 4, 5, 6]
        @test corpus.document_offsets == [1, 3, 6]
    end

    @testset "Function tokenizer name" begin
        # Test with function as tokenizer_name
        custom_tokenizer = x -> split(x)
        tokens = ["test", "tokens"]
        vocab = _test_vocab(["test", "tokens"])
        offsets = Dict(:document => [1, 3])
        cfg = PreprocessConfiguration(tokenizer_name=custom_tokenizer)
        
        bundle = assemble_bundle(tokens, offsets, vocab, cfg)
        
        # Should create level with function type name
        level_name = Symbol(typeof(custom_tokenizer))
        @test haskey(bundle.levels, level_name)
    end

    @testset "Metadata preservation" begin
        tokens = ["test"]
        vocab = _test_vocab(["test"])
        offsets = Dict(:document => [1, 2])
        cfg = PreprocessConfiguration(
            tokenizer_name=:whitespace,
            record_word_offsets=true,
            record_byte_offsets=false
        )
        
        bundle = assemble_bundle(tokens, offsets, vocab, cfg)
        
        @test bundle.metadata isa PipelineMetadata
    end

    @testset "Bundle structure validation" begin
        tokens = ["hello", "world"]
        vocab = _test_vocab(["hello", "world"])
        offsets = Dict(:document => [1, 3])
        cfg = PreprocessConfiguration(tokenizer_name=:whitespace)
        
        bundle = assemble_bundle(tokens, offsets, vocab, cfg)
        
        # Test bundle structure
        @test bundle isa PreprocessBundle
        @test bundle.levels isa Dict{Symbol, LevelBundle}
        @test bundle.metadata isa PipelineMetadata
        @test bundle.alignments isa Dict
        @test bundle.extras === nothing
        
        # Test level bundle structure
        level_bundle = bundle.levels[:word]
        @test level_bundle isa LevelBundle
        @test level_bundle.corpus isa Corpus
        @test level_bundle.vocabulary === vocab
    end

    @testset "Level mapping logic" begin
        # Test the level mapping logic in assemble_bundle
        tokens = ["test"]
        vocab = _test_vocab(["test"])
        offsets = Dict(:document => [1, 2])
        
        # Test each tokenizer -> level mapping
        test_cases = [
            (:byte, :byte),
            (:char, :character),
            (:unicode, :word),
            (:whitespace, :word)
        ]
        
        for (tokenizer, expected_level) in test_cases
            cfg = PreprocessConfiguration(tokenizer_name=tokenizer)
            bundle = assemble_bundle(tokens, offsets, vocab, cfg)
            @test haskey(bundle.levels, expected_level)
            @test length(bundle.levels) == 1
        end
    end

end

