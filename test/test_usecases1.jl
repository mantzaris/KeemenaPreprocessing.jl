const ALICE_SNIPPET = """
Alice was beginning to get very tired of sitting by her sister on the bank,
and of having nothing to do. Once or twice she had peeped into the book her
sister was reading, but it had no pictures or conversations in it.

So she was considering in her own mind whether the pleasure of making a
daisy-chain would be worth the trouble of getting up and picking the daisies,
when suddenly a White Rabbit with pink eyes ran close by her.
"""

const TIME_MACHINE_SNIPPET = """
The Time Traveller was expounding a recondite matter to us. His grey eyes shone
and twinkled, and his usually pale face was flushed and animated.

You must follow me carefully, he said, because I shall have to controvert one
or two ideas that are almost universally accepted.
"""

function _write_local_book_fixtures(tmp::AbstractString; repeats::Int = 300)
    alice_path = joinpath(tmp, "alice.txt")
    time_path  = joinpath(tmp, "time_machine.txt")
    write(alice_path, join(fill(ALICE_SNIPPET, repeats), "\n\n"))
    write(time_path,  join(fill(TIME_MACHINE_SNIPPET, repeats), "\n\n"))
    return alice_path, time_path
end


@testset "Pipeline - real texts (Alice + Time Machine)" begin
    mktempdir() do tmp
        # deterministic local fixtures (no network dependency)
        alice_path, time_path = _write_local_book_fixtures(tmp)

        sources = [alice_path, time_path]

        #  configure a reasonably rich pipeline
        cfg = KeemenaPreprocessing.PreprocessConfiguration(
            tokenizer_name           = :unicode,   # word-ish tokens
            record_word_offsets      = true,
            record_sentence_offsets  = true,
            record_document_offsets  = true,
        )

        #  non-streaming API
        bundle = KeemenaPreprocessing.preprocess_corpus(sources; config = cfg)

        @test KeemenaPreprocessing.has_level(bundle, :word)
        corpus = KeemenaPreprocessing.get_corpus(bundle, :word)

        # sentinel convention: last offset == n_tokens + 1
        @test corpus.document_offsets[end]  == length(corpus.token_ids) + 1
        @test corpus.sentence_offsets[end] == length(corpus.token_ids) + 1
        @test issorted(corpus.document_offsets) && issorted(corpus.sentence_offsets)

        #  streaming API (small chunk size so we get >1 bundle)
        ch  = KeemenaPreprocessing.preprocess_corpus_streaming(sources;
                                          cfg          = cfg,
                                          chunk_tokens = 50_000)

        first_b = take!(ch)
        @test KeemenaPreprocessing.has_level(first_b, :word)
        scorp = KeemenaPreprocessing.get_corpus(first_b, :word)
        @test scorp.document_offsets[1] == 1
        @test scorp.document_offsets[end] == length(scorp.token_ids) + 1
    end
end


@testset "Raw-text sources of arbitrary length" begin
    raw_short = "Mary had a little lamb."
    raw_long  = repeat("Lorem ipsum dolor sit amet, ", 10_000)  # around 250 kB

    cfg = KeemenaPreprocessing.PreprocessConfiguration(tokenizer_name = :whitespace)

    bund = KeemenaPreprocessing.preprocess_corpus([raw_short, raw_long]; config = cfg)

    @test KeemenaPreprocessing.has_level(bund, :word)
    wc = KeemenaPreprocessing.get_corpus(bund, :word)
    @test wc.document_offsets[end] == length(wc.token_ids) + 1
end





@testset "preprocess_corpus_streaming_full - real texts (Alice + Time)" begin
    mktempdir() do tmp
        # 1 deterministic local fixtures (no network dependency)
        alice_path, time_path = _write_local_book_fixtures(tmp)

        sources = [alice_path, time_path]

        # 2 rich configuration (records word / sentence / document offsets)
        cfg = KeemenaPreprocessing.PreprocessConfiguration(
                  tokenizer_name          = :unicode,
                  record_word_offsets     = true,
                  record_sentence_offsets = true,
                  record_document_offsets = true,
              )

        # 3 non-streaming baseline (ground truth for counts)
        baseline   = KeemenaPreprocessing.preprocess_corpus(sources; config = cfg)
        base_wc    = KeemenaPreprocessing.get_corpus(baseline, :word)
        ntok_base  = length(base_wc.token_ids)
        vocab_base = baseline.levels[:word].vocabulary

        # 4 streaming-FULL helper under test
        merged = KeemenaPreprocessing.preprocess_corpus_streaming_full(
                     sources; cfg = cfg, chunk_tokens = 8_000)   # force >1 chunk

        @test merged isa KeemenaPreprocessing.PreprocessBundle
        @test merged.levels[:word].vocabulary.id_to_token_strings ==
              vocab_base.id_to_token_strings                    # same lexicon
        @test length(KeemenaPreprocessing.get_token_ids(merged, :word)) == ntok_base

        # 5 offset and alignment sanity on merged bundle
        wc = KeemenaPreprocessing.get_corpus(merged, :word)

        # document offsets: 1-based, sorted, last >= n_tokens
        @test wc.document_offsets[1] == 1
        @test issorted(wc.document_offsets)
        @test wc.document_offsets[end] >= ntok_base

        # sentence offsets: same guarantees
        @test issorted(wc.sentence_offsets)
        @test wc.sentence_offsets[end] >= ntok_base

        # quick bijection check on byte <-> word cross-map (if present)
        if haskey(merged.alignments, (:byte, :word))
            cmap = merged.alignments[(:byte, :word)]
            src_ids = KeemenaPreprocessing.get_token_ids(merged, :byte)
            dst_ids = KeemenaPreprocessing.get_token_ids(merged, :word)

            @test cmap.source_level == :byte
            @test cmap.destination_level == :word
            @test length(cmap.alignment) == length(src_ids)

            if !isempty(src_ids)
                @test !isempty(dst_ids)
                @test issorted(cmap.alignment)
                @test all(w -> 1 <= w <= length(dst_ids), cmap.alignment)

                for i in rand(1:length(src_ids), min(20, length(src_ids)))
                    w = cmap.alignment[i]
                    @test 1 <= w <= length(dst_ids)
                end
            end
        end
    end
end
