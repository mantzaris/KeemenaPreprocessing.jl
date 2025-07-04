
_DOC_SIMPLE  = ["Hello world.  Bye!"]                    # 1 doc
_DOCS_MULTI  = ["One.\n\nTwo sentences here.",
                      "New doc—three sentences. OK?"]    # 2 docs
_ASCII_PAR   = "A  B\n\nC"                               #splitter demo
_UNICODE_TXT = "Café crème 😊."

#helper - asserts that last offset is len(tokens)+1
function _assert_sentinel(offsets, ntoks)
    @test offsets[end] == ntoks + 1
end

#whitespace tokenizer - doc / sentence / word offsets
@testset "tokenize_and_segment - whitespace defaults" begin
    cfg = KeemenaPreprocessing.PreprocessConfiguration()    # defaults: whitespace tok + all major offsets
    tokens, offs = KeemenaPreprocessing.tokenize_and_segment(_DOC_SIMPLE, cfg)

    @test tokens == ["Hello", "world.", "Bye!"]   # preserves punctuation
    _assert_sentinel(offs[:document],  length(tokens))
    _assert_sentinel(offs[:sentence],  length(tokens))
    _assert_sentinel(offs[:word],      length(tokens))

    # document -> doc offsets length == 2 (start+sentinel)
    @test length(offs[:document]) == 2
    # sentences -> sent offsets length == 3
    @test length(offs[:sentence]) == 3
end


#paragraph offsets enabled
@testset "tokenize_and_segment - paragraph split" begin
    cfg = KeemenaPreprocessing.PreprocessConfiguration(record_paragraph_offsets = true)
    tokens, offs = KeemenaPreprocessing.tokenize_and_segment([_ASCII_PAR], cfg)

    #expected token stream "A", "B", "C"
    @test tokens == ["A", "B", "C"]

    #two paragraphs -> offsets length == 3
    @test length(offs[:paragraph]) == 3
    _assert_sentinel(offs[:paragraph], length(tokens))
end


#unicode tokenizer (basic Latin , emoji)
@testset "tokenize_and_segment - unicode tokenizer" begin
    cfg = KeemenaPreprocessing.PreprocessConfiguration(
              tokenizer_name           = :unicode,
              record_word_offsets      = true,
              record_sentence_offsets  = false,
              record_document_offsets  = false)

    tokens, offs = KeemenaPreprocessing.tokenize_and_segment([_UNICODE_TXT], cfg)

    #expected tokens given the current regex (no emoji, no punctuation)
    @test tokens == ["Café", "crème"]

    #offsets vector must end with sentinel == length(tokens)+1
    _assert_sentinel(offs[:word], length(tokens))
end


#character tokenizer with character offsets
@testset "tokenize_and_segment - char tokenizer + char offsets" begin
    cfg = KeemenaPreprocessing.PreprocessConfiguration(tokenizer_name = :char,
                                  record_character_offsets = true,
                                  record_word_offsets      = false,
                                  record_sentence_offsets  = false,
                                  record_document_offsets  = false)
    tokens, offs = KeemenaPreprocessing.tokenize_and_segment(["ab"], cfg)

    @test tokens == ["a", "b"]
    @test haskey(offs, :character)
    _assert_sentinel(offs[:character], 2)
end


#byte tokenizer with byte offsets
@testset "tokenize_and_segment - byte tokenizer + byte offsets" begin
    cfg = KeemenaPreprocessing.PreprocessConfiguration(tokenizer_name = :byte,
                                  record_byte_offsets       = true,
                                  record_sentence_offsets   = false,
                                  record_document_offsets   = false)
    tokens, offs = KeemenaPreprocessing.tokenize_and_segment(["ABC"], cfg)

    @test tokens == UInt8.('A':'C')                # Vector{UInt8}
    _assert_sentinel(offs[:byte], 3)
end


#preserve-empty-tokens == false filters empties
@testset "tokenize_and_segment - empty token filtering" begin
    cfg = KeemenaPreprocessing.PreprocessConfiguration(preserve_empty_tokens = false)
    tokens, _ = KeemenaPreprocessing.tokenize_and_segment(["a  b   c"], cfg)
    @test tokens == ["a", "b", "c"]                # no empty strings
end


#mis-matched offset request triggers error
@testset "tokenize_and_segment - invalid char-offset request" begin
    cfg = KeemenaPreprocessing.PreprocessConfiguration(tokenizer_name = :whitespace,
                                  record_character_offsets = true)
    @test_throws ErrorException KeemenaPreprocessing.tokenize_and_segment(["abc"], cfg)
end
