



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
        loaded_bundle = KeemenaPreprocessing.load_preprocess_bundle(save_path)
        @test loaded_bundle isa KeemenaPreprocessing.PreprocessBundle
        
        # clean up
        rm(temp_dir, recursive=true)
    end

    @testset "preprocess_corpus error handling" begin
        # test that config and kwargs can't be used together
        cfg = KeemenaPreprocessing.PreprocessConfiguration()
        @test_throws ErrorException KeemenaPreprocessing.preprocess_corpus(test_docs, config=cfg, lowercase=false)
    end

    @testset "preprocess_corpus_streaming basic test" begin
        cfg = KeemenaPreprocessing.PreprocessConfiguration(tokenizer_name=:whitespace)
        
        # test streaming preprocessing
        stream = KeemenaPreprocessing.preprocess_corpus_streaming(test_docs, cfg=cfg)
        bundles = collect(stream)
        
        @test length(bundles) >= 1
        @test all(bundle -> bundle isa KeemenaPreprocessing.PreprocessBundle, bundles)
        @test all(bundle -> haskey(bundle.levels, :word), bundles)
    end

    @testset "preprocess_corpus_streaming with vocab" begin
        #first create a vocabulary
        cfg = KeemenaPreprocessing.PreprocessConfiguration(tokenizer_name=:whitespace)
        initial_bundle = KeemenaPreprocessing.preprocess_corpus(test_docs, config=cfg)
        vocab = initial_bundle.levels[:word].vocabulary
        
        # test streaming with pre-built vocabulary
        stream = KeemenaPreprocessing.preprocess_corpus_streaming(test_docs, cfg=cfg, vocab=vocab)
        bundles = collect(stream)
        
        @test length(bundles) >= 1
        @test all(bundle -> bundle.levels[:word].vocabulary === vocab, bundles)
    end


    # -------------------------------------------------------------------
    
    function make_corpus(ntoks; vocab = ["foo","bar","baz","qux","quux"])
        rng = MersenneTwister(1234)
        toks = [vocab[rand(rng, 1:length(vocab))] for _ in 1:ntoks]
        docs = String[]
        i    = 1
        while i <= ntoks
            len   = rand(rng, 5:15)                        # doc length
            stop  = min(i+len-1, ntoks)
            push!(docs, join(toks[i:stop], ' '))
            i = stop + 1
        end
        return docs
    end

    # small utility to count tokens quickly
    count_tokens(doc) = count(isspace, doc) + 1

    @testset "doc_chunk_iterator splits correctly" begin
        docs           = make_corpus(100_000)              # around 100 K tokens
        cfg            = KeemenaPreprocessing.PreprocessConfiguration(tokenizer_name = :whitespace)
        chunk_tokens   = 7_500
        total_count    = 0
        max_chunk_size = 0
        for batch in doc_chunk_iterator(docs, cfg; chunk_tokens)
            batch_tokens = sum(count_tokens, batch)
            total_count += batch_tokens
            max_chunk_size = max(max_chunk_size, batch_tokens)
            @test batch_tokens <= chunk_tokens
        end
        @test total_count == sum(count_tokens, docs)
        @test max_chunk_size <= chunk_tokens                # sanity
    end


    @testset "_streaming_counts equals naïve counts" begin
        docs = make_corpus(200_000)                        # larger
        cfg  = KeemenaPreprocessing.PreprocessConfiguration(tokenizer_name = :whitespace)

        #
        clean      = KeemenaPreprocessing.clean_documents(docs, cfg)
        toks, _    = KeemenaPreprocessing.tokenize_and_segment(clean, cfg)
        ref_freqs  = Dict{String,Int}()
        foreach(t-> ref_freqs[t] = get(ref_freqs,t,0)+1, toks)

        # streaming
        stream_freqs = KeemenaPreprocessing._streaming_counts(docs, cfg; chunk_tokens = 10_000)

        @test stream_freqs == ref_freqs
    end

    @testset "preprocess_corpus_streaming large corpus" begin
        big_docs      = make_corpus(1_000_000)             # ~1 M tokens
        cfg           = KeemenaPreprocessing.PreprocessConfiguration(tokenizer_name = :whitespace)

        #build vocabulary once (streaming path)
        freqs  = KeemenaPreprocessing._streaming_counts(big_docs, cfg; chunk_tokens = 20_000)
        vocab  = KeemenaPreprocessing.build_vocabulary(freqs; cfg = cfg)

        #preprocess corpus in small bundles
        chunk_tokens = 15_000                              # force many bundles
        stream = KeemenaPreprocessing.preprocess_corpus_streaming(big_docs;
                                            cfg   = cfg,
                                            vocab = vocab,
                                            chunk_tokens = chunk_tokens)

        bundles = collect(stream)

        @test !isempty(bundles)                            # got something
        @test all(b -> b isa KeemenaPreprocessing.PreprocessBundle, bundles)
        @test all(b -> b.levels[:word].vocabulary === vocab, bundles)
        # 
        @test length(bundles) > 1
    end






end
