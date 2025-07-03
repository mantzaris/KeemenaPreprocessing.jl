

_default_cfg() = PreprocessConfiguration()


@testset "PreprocessConfiguration - defaults" begin
    cfg = _default_cfg()

    @test cfg.lowercase
    @test cfg.strip_accents
    @test cfg.remove_punctuation
    @test cfg.normalise_whitespace
    @test cfg.trim_edges

    @test cfg.tokenizer_name == :whitespace
    @test !cfg.preserve_empty_tokens

    @test cfg.minimum_token_frequency == 1
    @test cfg.special_tokens[:unk] == "<UNK>"
    @test cfg.special_tokens[:pad] == "<PAD>"

    @test !cfg.record_byte_offsets
    @test !cfg.record_character_offsets
    @test  cfg.record_word_offsets
    @test  cfg.record_sentence_offsets
    @test !cfg.record_paragraph_offsets
    @test  cfg.record_document_offsets
end


@testset "PreprocessConfiguration - keyword overrides" begin
    cfg = PreprocessConfiguration(lowercase = false,
                                  tokenizer_name = :byte,
                                  record_byte_offsets = true,
                                  record_word_offsets = false,
                                  minimum_token_frequency = 5)

    @test !cfg.lowercase
    @test cfg.tokenizer_name == :byte
    @test cfg.record_byte_offsets
    @test !cfg.record_word_offsets
    @test cfg.minimum_token_frequency == 5
end


@testset "PreprocessConfiguration - argument checks" begin
    # minimum_token_frequency must be >= 1
    @test_throws AssertionError PreprocessConfiguration(minimum_token_frequency = 0)

    # tokenizer_name must be valid Symbol or Function
    @test_throws AssertionError PreprocessConfiguration(tokenizer_name = :invalid_tok)
end