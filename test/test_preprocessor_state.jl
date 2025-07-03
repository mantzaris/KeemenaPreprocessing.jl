
@testset "_PreprocessorState Module Tests" begin

    # Test data
    train_docs = ["Hello world test", "Another document here", "Final training text"]
    test_docs = ["New document to encode", "Another test case"]
    
    @testset "Preprocessor struct" begin
        # Test basic structure
        cfg = PreprocessConfiguration(tokenizer_name=:whitespace)
        vocab = Vocabulary(
            ["<UNK>", "hello", "world"],
            Dict("hello" => 2, "world" => 3, "<UNK>" => 1),
            [0, 1, 1],
            Dict(:unk => 1)
        )
        
        prep = Preprocessor(cfg, vocab)
        @test prep.cfg === cfg
        @test prep.vocabulary === vocab
        @test prep isa Preprocessor
    end

    @testset "build_preprocessor basic functionality" begin
        prep, train_bundle = build_preprocessor(train_docs)
        
        # Test return types
        @test prep isa Preprocessor
        @test train_bundle isa PreprocessBundle
        
        # Test preprocessor structure
        @test prep.cfg isa PreprocessConfiguration
        @test prep.vocabulary isa Vocabulary
        
        # Test that bundle was created correctly
        @test haskey(train_bundle.levels, :word)
        @test length(train_bundle.levels[:word].corpus.token_ids) > 0
    end

    @testset "build_preprocessor with custom config" begin
        prep, train_bundle = build_preprocessor(
            train_docs,
            tokenizer_name=:whitespace,
            lowercase=false,
            remove_punctuation=false
        )
        
        @test prep.cfg.tokenizer_name == :whitespace
        @test prep.cfg.lowercase == false
        @test prep.cfg.remove_punctuation == false
        @test prep.vocabulary isa Vocabulary
    end

    @testset "encode_corpus with Preprocessor" begin
        # Build preprocessor from training data
        prep, train_bundle = build_preprocessor(train_docs)
        
        # Encode new corpus
        test_bundle = encode_corpus(prep, test_docs)
        
        # Test result structure
        @test test_bundle isa PreprocessBundle
        @test haskey(test_bundle.levels, :word)
        @test length(test_bundle.levels[:word].corpus.token_ids) > 0
        
        # Test that same vocabulary is used
        @test test_bundle.levels[:word].vocabulary === prep.vocabulary
        
        # Test that same configuration is used
        @test test_bundle.metadata.configuration === prep.cfg
    end

    @testset "encode_corpus with PreprocessBundle" begin
        # Build initial bundle
        prep, train_bundle = build_preprocessor(train_docs)
        
        # Encode using the bundle directly
        test_bundle = encode_corpus(train_bundle, test_docs)
        
        # Test result structure
        @test test_bundle isa PreprocessBundle
        @test haskey(test_bundle.levels, :word)
        @test length(test_bundle.levels[:word].corpus.token_ids) > 0
        
        # Should use same vocabulary and config as original bundle
        @test test_bundle.levels[:word].vocabulary.token_to_id_map == train_bundle.levels[:word].vocabulary.token_to_id_map
    end

    @testset "Unknown token handling" begin
        # Build preprocessor with limited vocabulary
        simple_docs = ["hello world"]
        prep, train_bundle = build_preprocessor(simple_docs)
        
        # Encode documents with unknown words
        unknown_docs = ["hello unknown words here"]
        test_bundle = encode_corpus(prep, unknown_docs)
        
        # Should handle unknown tokens gracefully
        @test test_bundle isa PreprocessBundle
        @test length(test_bundle.levels[:word].corpus.token_ids) > 0
        
        # Unknown words should map to UNK token
        token_ids = test_bundle.levels[:word].corpus.token_ids
        unk_id = prep.vocabulary.special_tokens[:unk]
        @test unk_id in token_ids  # Should contain UNK tokens
    end

    @testset "encode_corpus with save_to" begin
        prep, train_bundle = build_preprocessor(train_docs)
        
        # Create temporary file path
        temp_dir = mktempdir()
        save_path = joinpath(temp_dir, "encoded_bundle.jld2")
        
        # Encode and save
        test_bundle = encode_corpus(prep, test_docs, save_to=save_path)
        
        # Test that file was created
        @test isfile(save_path)
        
        # Test that saved bundle can be loaded
        loaded_bundle = load_preprocess_bundle(save_path)
        @test loaded_bundle isa PreprocessBundle
        @test haskey(loaded_bundle.levels, :word)
        
        # Clean up
        rm(temp_dir, recursive=true)
    end

    @testset "Consistency between methods" begin
        # Build preprocessor
        prep, train_bundle = build_preprocessor(train_docs)
        
        # Encode using both methods
        test_bundle1 = encode_corpus(prep, test_docs)
        test_bundle2 = encode_corpus(train_bundle, test_docs)
        
        # Results should be equivalent
        @test test_bundle1.levels[:word].corpus.token_ids == test_bundle2.levels[:word].corpus.token_ids
        @test test_bundle1.levels[:word].corpus.document_offsets == test_bundle2.levels[:word].corpus.document_offsets
    end

    @testset "Empty document handling" begin
        prep, train_bundle = build_preprocessor(train_docs)
        
        # Test with empty documents
        empty_docs = ["", "  ", "normal text"]
        test_bundle = encode_corpus(prep, empty_docs)
        
        @test test_bundle isa PreprocessBundle
        @test haskey(test_bundle.levels, :word)
        # Should handle gracefully without errors
    end

    @testset "Single document encoding" begin
        prep, train_bundle = build_preprocessor(train_docs)
        
        # Test with single document
        single_doc = ["Just one document"]
        test_bundle = encode_corpus(prep, single_doc)
        
        @test test_bundle isa PreprocessBundle
        @test haskey(test_bundle.levels, :word)
        @test length(test_bundle.levels[:word].corpus.document_offsets) == 2  # [1, end]
    end

end

