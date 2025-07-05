


ALICE_URL = "https://www.gutenberg.org/files/11/11-0.txt"
TIME_URL  = "https://www.gutenberg.org/files/35/35-0.txt"


@testset "Pipeline - real texts (Alice + Time Machine)" begin
    mktempdir() do tmp
        # 1 ▸ download the raw books to *files*
        alice_path = joinpath(tmp, "alice.txt")
        time_path  = joinpath(tmp, "time_machine.txt")
        Downloads.download(ALICE_URL, alice_path)
        Downloads.download(TIME_URL,  time_path)

        sources = [alice_path, time_path]

        # 2 ▸ configure a reasonably rich pipeline
        cfg = PreprocessConfiguration(
            tokenizer_name           = :unicode,   # word-ish tokens
            record_word_offsets      = true,
            record_sentence_offsets  = true,
            record_document_offsets  = true,
        )

        # 3 ▸  non-streaming API
        bundle = preprocess_corpus(sources; config = cfg)

        @test has_level(bundle, :word)
        corpus = get_corpus(bundle, :word)

        # sentinel convention: last offset == n_tokens + 1
        @test corpus.document_offsets[end]  == length(corpus.token_ids) + 1
        @test corpus.sentence_offsets[end] == length(corpus.token_ids) + 1
        @test issorted(corpus.document_offsets) && issorted(corpus.sentence_offsets)

        # 4 ▸  streaming API (small chunk size so we get >1 bundle)
        ch  = preprocess_corpus_streaming(sources;
                                          cfg          = cfg,
                                          chunk_tokens = 50_000)

        first_b = take!(ch)
        @test has_level(first_b, :word)
        scorp = get_corpus(first_b, :word)
        @test scorp.document_offsets[1] == 1
        @test scorp.document_offsets[end] == length(scorp.token_ids) + 1
    end
end


@testset "Raw-text sources of arbitrary length" begin
    raw_short = "Mary had a little lamb."
    raw_long  = repeat("Lorem ipsum dolor sit amet, ", 10_000)  # around 250 kB

    cfg = PreprocessConfiguration(tokenizer_name = :whitespace)

    bund = preprocess_corpus([raw_short, raw_long]; config = cfg)

    @test has_level(bund, :word)
    wc = get_corpus(bund, :word)
    @test wc.document_offsets[end] == length(wc.token_ids) + 1
end
