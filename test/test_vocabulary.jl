

_TOKENS      = ["hello", "world", "hello", "test", "world", "hello"]
_BYTES       = UInt8.('A':'C')           # ['A','B','C'] for the byte-path test
_SPECIALS    = Dict(:unk => "<UNK>", :pad => "<PAD>")  # mirrors library default


@testset "build_vocabulary - specials (default cfg)" begin
    cfg   = KeemenaPreprocessing.PreprocessConfiguration()          # record_sentence_offsets == true
    vocab = KeemenaPreprocessing.build_vocabulary(_TOKENS; cfg)

    #presence: first four entries must be the four specials, irrespective of order in the vector
    @test Set(vocab.id_to_token_strings[1:4]) ==
          Set(["<UNK>", "<PAD>", "<BOS>", "<EOS>"])

    #alphabetical ordering ->  ids(bos) < ids(eos) < ids(pad) < ids(unk)
    expected_syms = [:bos, :eos, :pad, :unk]
    @test sort(collect(keys(vocab.special_tokens))) == expected_syms
    @test [vocab.special_tokens[s] for s in expected_syms] == 1:4

    # 3.  Internal consistency (id <-> string <-> map) for every special token
    for (sym, id) in vocab.special_tokens
        str = vocab.id_to_token_strings[id]
        @test vocab.token_to_id_map[str] == id
    end
end


@testset "build_vocabulary - specials (no sentence offsets)" begin
    cfg   = KeemenaPreprocessing.PreprocessConfiguration(record_sentence_offsets = false)
    vocab = KeemenaPreprocessing.build_vocabulary(_TOKENS; cfg)     # only :unk & :pad expected

    #presence of the two user-supplied specials (order-agnostic)
    @test Set(vocab.id_to_token_strings[1:2]) == Set(["<UNK>", "<PAD>"])

    #alphabetical: ids(pad) < ids(unk)
    @test sort(collect(keys(vocab.special_tokens))) == [:pad, :unk]
    @test [vocab.special_tokens[s] for s in (:pad, :unk)] == 1:2

    #no sentence-markers were added
    @test !haskey(vocab.special_tokens, :bos)
    @test !haskey(vocab.special_tokens, :eos)
end


@testset "build_vocabulary - minimum_token_frequency" begin
    cfg   = KeemenaPreprocessing.PreprocessConfiguration(minimum_token_frequency = 2,    # filter singletons
                                    record_sentence_offsets  = false)
    vocab = KeemenaPreprocessing.build_vocabulary(_TOKENS; cfg)

    @test !haskey(vocab.token_to_id_map, "test")          # only appears once
    @test haskey(vocab.token_to_id_map, "hello")          # appears 3x
end


#ordering rules (stable and deterministic)
@testset "build_vocabulary _ deterministic ordering" begin
    tkns = ["b", "a", "z", "a"]
    cfg  = KeemenaPreprocessing.PreprocessConfiguration(record_sentence_offsets = false,
                                   minimum_token_frequency = 1,
                                   special_tokens = Dict(:unk => "<UNK>"))
    vocab = KeemenaPreprocessing.build_vocabulary(tkns; cfg)

    #specials first, sorted by Symbol; corpus tokens next, lexicographically
    @test vocab.id_to_token_strings == ["<UNK>", "a", "b", "z"]
end


#byte-vector overload path
@testset "build_vocabulary - byte tokens overload" begin
    cfg   = KeemenaPreprocessing.PreprocessConfiguration(tokenizer_name = :byte,
                                    record_byte_offsets = true,
                                    record_sentence_offsets = false)
    vocab = KeemenaPreprocessing.build_vocabulary(_BYTES; cfg)

    #ecah UInt8 maps to its ASCII string-equivalent
    @test vocab.id_to_token_strings[3:end] == ["A","B","C"]
end


@testset "build_vocabulary - empty token list" begin
    cfg   = KeemenaPreprocessing.PreprocessConfiguration(record_sentence_offsets = false)
    vocab = KeemenaPreprocessing.build_vocabulary(String[]; cfg)

    #both specials are present (order doesn't matter)
    @test Set(vocab.id_to_token_strings) == Set(["<UNK>", "<PAD>"])

    #alphabetical rule -> :pad gets ID 1, :unk gets ID 2
    @test sort(collect(keys(vocab.special_tokens))) == [:pad, :unk]
    @test vocab.special_tokens[:pad] == 1
    @test vocab.special_tokens[:unk] == 2

    #frequency vector is all zeros
    @test all(vocab.token_frequencies .== 0)
end

