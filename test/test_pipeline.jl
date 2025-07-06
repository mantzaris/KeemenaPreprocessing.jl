

@testset "Pipeline Tests (Minimal)" begin

    # test data
    test_docs = ["Hello world test", "Another document here", "Final test text"]
    
    @testset "preprocess_corpus basic functionality" begin
        # test with default configuration
        bundle = KeemenaPreprocessing.preprocess_corpus(test_docs)
        
        @test bundle isa KeemenaPreprocessing.PreprocessBundle
        @test haskey(bundle.levels, :word)
        @test length(bundle.levels[:word].corpus.token_ids) > 0
        @test bundle.levels[:word].vocabulary isa KeemenaPreprocessing.Vocabulary
    end

    @testset "preprocess_corpus with kwargs" begin
        #test with keyword arguments
        bundle = KeemenaPreprocessing.preprocess_corpus(test_docs, tokenizer_name=:whitespace, lowercase=false)
        
        @test bundle isa KeemenaPreprocessing.PreprocessBundle
        @test bundle.metadata.configuration.tokenizer_name == :whitespace
        @test bundle.metadata.configuration.lowercase == false
    end

    @testset "preprocess_corpus with config object" begin
        #test with explicit configuration
        cfg = KeemenaPreprocessing.PreprocessConfiguration(tokenizer_name=:whitespace, remove_punctuation=false)
        bundle = KeemenaPreprocessing.preprocess_corpus(test_docs, config=cfg)
        
        @test bundle isa KeemenaPreprocessing.PreprocessBundle
        @test bundle.metadata.configuration.tokenizer_name == :whitespace
        @test bundle.metadata.configuration.remove_punctuation == false
    end

    @testset "preprocess_corpus config method" begin
        # test the second method signature
        cfg = KeemenaPreprocessing.PreprocessConfiguration(tokenizer_name=:whitespace)
        bundle = KeemenaPreprocessing.preprocess_corpus(test_docs, cfg)
        
        @test bundle isa KeemenaPreprocessing.PreprocessBundle
        @test bundle.metadata.configuration === cfg
    end

    @testset "preprocess_corpus with save_to" begin
        #test saving functionality
        temp_dir = mktempdir()
        save_path = joinpath(temp_dir, "test_bundle.jld2")
        
        bundle = KeemenaPreprocessing.preprocess_corpus(test_docs, save_to=save_path)
        
        @test bundle isa KeemenaPreprocessing.PreprocessBundle
        @test isfile(save_path)
        
        #verify saved bundle can be loaded
        loaded_bundle = KeemenaPreprocessing._BundleIO.load_preprocess_bundle(save_path)
        @test loaded_bundle isa KeemenaPreprocessing.PreprocessBundle
        
        # clean up
        rm(temp_dir, recursive=true)
    end

    @testset "preprocess_corpus error handling" begin
        # test that config and kwargs can't be used together
        cfg = KeemenaPreprocessing.PreprocessConfiguration()
        @test_throws ErrorException KeemenaPreprocessing.preprocess_corpus(test_docs, config=cfg, lowercase=false)
    end




end
