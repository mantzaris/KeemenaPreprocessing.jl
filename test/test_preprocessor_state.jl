
@testset "_PreprocessorState Module Tests" begin

    # test data
    train_docs = ["Hello world test", "Another document here", "Final training text"]
    test_docs = ["New document to encode", "Another test case"]
    
    @testset "Preprocessor struct" begin
        # test basic structure
        cfg = KeemenaPreprocessing.PreprocessConfiguration(tokenizer_name=:whitespace)
        vocab = KeemenaPreprocessing.Vocabulary(
            ["<UNK>", "hello", "world"],
            Dict("hello" => 2, "world" => 3, "<UNK>" => 1),
            [0, 1, 1],
            Dict(:unk => 1)
        )
        
        prep = KeemenaPreprocessing.Preprocessor(cfg, vocab)
        @test prep.cfg === cfg
        @test prep.vocabulary === vocab
        @test prep isa KeemenaPreprocessing.Preprocessor
    end

    @testset "build_preprocessor basic functionality" begin
        prep, train_bundle = KeemenaPreprocessing.build_preprocessor(train_docs)
        
        # test return types
        @test prep isa KeemenaPreprocessing.Preprocessor
        @test train_bundle isa KeemenaPreprocessing.PreprocessBundle
        
        # test preprocessor structure
        @test prep.cfg isa KeemenaPreprocessing.PreprocessConfiguration
        @test prep.vocabulary isa KeemenaPreprocessing.Vocabulary
        
        # test that bundle was created correctly
        @test haskey(train_bundle.levels, :word)
        @test length(train_bundle.levels[:word].corpus.token_ids) > 0
    end

    @testset "build_preprocessor with custom config" begin
        prep, train_bundle = KeemenaPreprocessing.build_preprocessor(
            train_docs,
            tokenizer_name=:whitespace,
            lowercase=false,
            remove_punctuation=false
        )
        
        @test prep.cfg.tokenizer_name == :whitespace
        @test prep.cfg.lowercase == false
        @test prep.cfg.remove_punctuation == false
        @test prep.vocabulary isa KeemenaPreprocessing.Vocabulary
    end

    @testset "encode_corpus with Preprocessor" begin
        # build preprocessor from training data
        prep, train_bundle = KeemenaPreprocessing.build_preprocessor(train_docs)
        
        # encode new corpus
        test_bundle = KeemenaPreprocessing.encode_corpus(prep, test_docs)
        
        # test result structure
        @test test_bundle isa KeemenaPreprocessing.PreprocessBundle
        @test haskey(test_bundle.levels, :word)
        @test length(test_bundle.levels[:word].corpus.token_ids) > 0
        
        # test that same vocabulary is used
        @test test_bundle.levels[:word].vocabulary === prep.vocabulary
        
        # test that same configuration is used
        @test test_bundle.metadata.configuration === prep.cfg
    end

    @testset "encode_corpus with PreprocessBundle" begin
        # build initial bundle
        prep, train_bundle = KeemenaPreprocessing.build_preprocessor(train_docs)
        
        # encode using the bundle directly
        test_bundle = KeemenaPreprocessing.encode_corpus(train_bundle, test_docs)
        
        # test result structure
        @test test_bundle isa KeemenaPreprocessing.PreprocessBundle
        @test haskey(test_bundle.levels, :word)
        @test length(test_bundle.levels[:word].corpus.token_ids) > 0
        
        #should use same vocabulary and config as original bundle
        @test test_bundle.levels[:word].vocabulary.token_to_id_map == train_bundle.levels[:word].vocabulary.token_to_id_map
    end

    @testset "Unknown token handling" begin
        # build preprocessor with limited vocabulary
        simple_docs = ["hello world"]
        prep, train_bundle = KeemenaPreprocessing.build_preprocessor(simple_docs)
        
        # encode documents with unknown words
        unknown_docs = ["hello unknown words here"]
        test_bundle = KeemenaPreprocessing.encode_corpus(prep, unknown_docs)
        
        # should handle unknown tokens gracefully
        @test test_bundle isa KeemenaPreprocessing.PreprocessBundle
        @test length(test_bundle.levels[:word].corpus.token_ids) > 0
        
        # unknown words should map to UNK token
        token_ids = test_bundle.levels[:word].corpus.token_ids
        unk_id = prep.vocabulary.special_tokens[:unk]
        @test unk_id in token_ids  # Should contain UNK tokens
    end

    @testset "encode_corpus with save_to" begin
        prep, train_bundle = KeemenaPreprocessing.build_preprocessor(train_docs)
        
        # create temporary file path
        temp_dir = mktempdir()
        save_path = joinpath(temp_dir, "encoded_bundle.jld2")
        
        # encode and save
        test_bundle = KeemenaPreprocessing.encode_corpus(prep, test_docs, save_to=save_path)
        
        # test that file was created
        @test isfile(save_path)
        
        #test that saved bundle can be loaded
        loaded_bundle = KeemenaPreprocessing.load_preprocess_bundle(save_path)
        @test loaded_bundle isa KeemenaPreprocessing.PreprocessBundle
        @test haskey(loaded_bundle.levels, :word)
        
        #clean up
        rm(temp_dir, recursive=true)
    end

    @testset "Consistency between methods" begin
        #build preprocessor
        prep, train_bundle = KeemenaPreprocessing.build_preprocessor(train_docs)
        
        #encode using both methods
        test_bundle1 = KeemenaPreprocessing.encode_corpus(prep, test_docs)
        test_bundle2 = KeemenaPreprocessing.encode_corpus(train_bundle, test_docs)
        
        #results should be equivalent
        @test test_bundle1.levels[:word].corpus.token_ids == test_bundle2.levels[:word].corpus.token_ids
        @test test_bundle1.levels[:word].corpus.document_offsets == test_bundle2.levels[:word].corpus.document_offsets
    end

    @testset "Empty document handling" begin
        prep, train_bundle = KeemenaPreprocessing.build_preprocessor(train_docs)
        
        #test with empty documents
        empty_docs = ["", "  ", "normal text"]
        test_bundle = KeemenaPreprocessing.encode_corpus(prep, empty_docs)
        
        @test test_bundle isa KeemenaPreprocessing.PreprocessBundle
        @test haskey(test_bundle.levels, :word)
    end

    @testset "Single document encoding" begin
        prep, train_bundle = KeemenaPreprocessing.build_preprocessor(train_docs)
        
        # test with single document
        single_doc = ["Just one document"]
        test_bundle = KeemenaPreprocessing.encode_corpus(prep, single_doc)
        
        @test test_bundle isa KeemenaPreprocessing.PreprocessBundle
        @test haskey(test_bundle.levels, :word)
        @test length(test_bundle.levels[:word].corpus.document_offsets) == 2  # [1, end]
    end

end

