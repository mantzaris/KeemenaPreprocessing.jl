

@testset "Pipeline Tests (Minimal)" begin

    # Test data
    test_docs = ["Hello world test", "Another document here", "Final test text"]
    
    @testset "preprocess_corpus basic functionality" begin
        # Test with default configuration
        bundle = preprocess_corpus(test_docs)
        
        @test bundle isa PreprocessBundle
        @test haskey(bundle.levels, :word)
        @test length(bundle.levels[:word].corpus.token_ids) > 0
        @test bundle.levels[:word].vocabulary isa Vocabulary
    end

    @testset "preprocess_corpus with kwargs" begin
        # Test with keyword arguments
        bundle = preprocess_corpus(test_docs, tokenizer_name=:whitespace, lowercase=false)
        
        @test bundle isa PreprocessBundle
        @test bundle.metadata.configuration.tokenizer_name == :whitespace
        @test bundle.metadata.configuration.lowercase == false
    end

    @testset "preprocess_corpus with config object" begin
        # Test with explicit configuration
        cfg = PreprocessConfiguration(tokenizer_name=:whitespace, remove_punctuation=false)
        bundle = preprocess_corpus(test_docs, config=cfg)
        
        @test bundle isa PreprocessBundle
        @test bundle.metadata.configuration.tokenizer_name == :whitespace
        @test bundle.metadata.configuration.remove_punctuation == false
    end

    @testset "preprocess_corpus config method" begin
        # Test the second method signature
        cfg = PreprocessConfiguration(tokenizer_name=:whitespace)
        bundle = preprocess_corpus(test_docs, cfg)
        
        @test bundle isa PreprocessBundle
        @test bundle.metadata.configuration === cfg
    end

    @testset "preprocess_corpus with save_to" begin
        # Test saving functionality
        temp_dir = mktempdir()
        save_path = joinpath(temp_dir, "test_bundle.jld2")
        
        bundle = preprocess_corpus(test_docs, save_to=save_path)
        
        @test bundle isa PreprocessBundle
        @test isfile(save_path)
        
        # Verify saved bundle can be loaded
        loaded_bundle = load_preprocess_bundle(save_path)
        @test loaded_bundle isa PreprocessBundle
        
        # Clean up
        rm(temp_dir, recursive=true)
    end

    @testset "preprocess_corpus error handling" begin
        # Test that config and kwargs can't be used together
        cfg = PreprocessConfiguration()
        @test_throws ErrorException preprocess_corpus(test_docs, config=cfg, lowercase=false)
    end

    @testset "preprocess_corpus_streaming basic test" begin
        cfg = PreprocessConfiguration(tokenizer_name=:whitespace)
        
        # Test streaming preprocessing
        stream = preprocess_corpus_streaming(test_docs, cfg=cfg)
        bundles = collect(stream)
        
        @test length(bundles) >= 1
        @test all(bundle -> bundle isa PreprocessBundle, bundles)
        @test all(bundle -> haskey(bundle.levels, :word), bundles)
    end

    @testset "preprocess_corpus_streaming with vocab" begin
        # First create a vocabulary
        cfg = PreprocessConfiguration(tokenizer_name=:whitespace)
        initial_bundle = preprocess_corpus(test_docs, config=cfg)
        vocab = initial_bundle.levels[:word].vocabulary
        
        # Test streaming with pre-built vocabulary
        stream = preprocess_corpus_streaming(test_docs, cfg=cfg, vocab=vocab)
        bundles = collect(stream)
        
        @test length(bundles) >= 1
        @test all(bundle -> bundle.levels[:word].vocabulary === vocab, bundles)
    end

end
