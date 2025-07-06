

@testset "Process Streaming Tests (basic and deep tests)" begin

    test_docs = ["Hello world test", "Another document here", "Final test text"]


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
        for batch in KeemenaPreprocessing.doc_chunk_iterator(docs, cfg; chunk_tokens)
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
        clean      = KeemenaPreprocessing._Cleaning.clean_documents(docs, cfg)
        toks, _    = KeemenaPreprocessing._Tokenization.tokenize_and_segment(clean, cfg)
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
        vocab  = KeemenaPreprocessing._Vocabulary.build_vocabulary(freqs; cfg = cfg)

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





    #streaming chunks and full

    @testset "preprocess_corpus_streaming_chunks & _full" begin
        #build a synthetic corpus large enough to force >1 chunk
        docs         = make_corpus(80_000)                      # approx. 80 K tokens
        chunk_tokens = 5_000                                    # -> many chunks
        cfg          = KeemenaPreprocessing.PreprocessConfiguration(
                        tokenizer_name = :whitespace)

        # vector-of-bundles helper
        bundles_vec = KeemenaPreprocessing.preprocess_corpus_streaming_chunks(
                        docs; cfg = cfg, chunk_tokens = chunk_tokens)

        @test bundles_vec isa Vector{KeemenaPreprocessing.PreprocessBundle}
        @test length(bundles_vec) > 1                           # really chunked

        vocab_ref = bundles_vec[1].levels[:word].vocabulary
        @test all(b -> b.levels[:word].vocabulary === vocab_ref, bundles_vec)

        total_tokens = sum(length(KeemenaPreprocessing.get_token_ids(b, :word))
                        for b in bundles_vec)

        #single-bundle merge helper
        merged = KeemenaPreprocessing.preprocess_corpus_streaming_full(
                    docs; cfg = cfg, chunk_tokens = chunk_tokens)

        @test merged isa KeemenaPreprocessing.PreprocessBundle
        
        @test merged.levels[:word].vocabulary.id_to_token_strings ==
            vocab_ref.id_to_token_strings

        @test merged.levels[:word].vocabulary.token_to_id_map ==
            vocab_ref.token_to_id_map
            
        @test length(KeemenaPreprocessing.get_token_ids(merged, :word)) == total_tokens
    end

    @testset "preprocess_corpus_streaming_full (single-chunk fallback)" begin
        #  Force everything into one chunk and compare to the non-streaming path
        docs          = make_corpus(3_000)                      # small corpus
        huge_chunkcap = 1_000_000
        cfg           = KeemenaPreprocessing.PreprocessConfiguration(
                            tokenizer_name = :whitespace)

        merged  = KeemenaPreprocessing.preprocess_corpus_streaming_full(
                    docs; cfg = cfg, chunk_tokens = huge_chunkcap)
        direct  = KeemenaPreprocessing.preprocess_corpus(docs, config = cfg)

        @test length(KeemenaPreprocessing.get_token_ids(merged, :word)) ==
            length(KeemenaPreprocessing.get_token_ids(direct, :word))

        @test merged.levels[:word].vocabulary.id_to_token_strings ==
            direct.levels[:word].vocabulary.id_to_token_strings

        @test merged.levels[:word].vocabulary.token_to_id_map ==
            direct.levels[:word].vocabulary.token_to_id_map

    end



    function check_bundle_integrity(b::PreprocessBundle)
        # 1 token IDs vs vocabulary 
        for (lvl, lb) in b.levels
            corp, vocab = lb.corpus, lb.vocabulary
            @test minimum(corp.token_ids) >= 1
            @test maximum(corp.token_ids) <= length(vocab.id_to_token_strings)

            # random round-trip id -> string -> id
            for i in rand(1:length(corp.token_ids), min(10,length(corp.token_ids)))
                id  = corp.token_ids[i]
                tok = vocab.id_to_token_strings[id]
                @test vocab.token_to_id_map[tok] == id
            end
        end

        # 2 offset vectors
        for (lvl, lb) in b.levels
            corp   = lb.corpus
            ntok   = length(corp.token_ids)

            for fld in fieldnames(Corpus)
                fld === :token_ids && continue
                offs = getfield(corp, fld)
                offs === nothing && continue          # level doesn't store this map

                @test issorted(offs)                  # monotone ↑ (allows repeats)
                @test first(offs)  in (0, 1)          # typical sentinel choices
                @test last(offs)  >= ntok              # covers all tokens
                @test all(offs .>= 0)                 # no negative indices
                @test all(offs .<= ntok + 1)          # never outruns ntok+1
            end
        end

        # 3 alignment maps 
        for ((src,dst), cmap) in b.alignments
            src_ids = get_token_ids(b, src)
            dst_ids = get_token_ids(b, dst)

            @test length(cmap.forward) == length(src_ids)
            @test length(cmap.backward) == length(dst_ids)

            # spot-check bijection on 20 random src indices (or all if tiny)
            for i in rand(1:length(src_ids), min(20,length(src_ids)))
                j = cmap.forward[i]
                @test cmap.backward[j] == i
            end
        end
    end


    @testset "deep integrity tests (IDs, Offsets, Alignments)" begin
        docs         = make_corpus(50_000)                # approx 50 k tokens
        chunk_tokens = 4_000
        cfg          = KeemenaPreprocessing.PreprocessConfiguration(
                        tokenizer_name = :whitespace)

        # streaming chunks 
        for b in KeemenaPreprocessing.preprocess_corpus_streaming_chunks(
                    docs; cfg, chunk_tokens)
            check_bundle_integrity(b)
        end

        # merged bundle
        merged = KeemenaPreprocessing.preprocess_corpus_streaming_full(
                    docs; cfg, chunk_tokens)
        check_bundle_integrity(merged)
    end



end



