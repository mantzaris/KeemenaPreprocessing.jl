

using KeemenaPreprocessing
using Test


# include("cleaning.jl")
# include("tokenization.jl")
include("assemble.jl")
include("preprocessor_state.jl")


@testset "basic cleaning" begin
    raw = ["Héllö  WORLD!\n\n", "  \tFoO…  "]
    cfg = PreprocessConfiguration(strip_accents = true,
                                  lowercase = true,
                                  remove_punctuation = true,
                                  normalise_whitespace = true, trim_edges=false)

    clean = KeemenaPreprocessing.clean_documents(raw, cfg)
    @test clean == ["hello world", " foo "]
end


@testset "basic tokenization" begin
    cfg = PreprocessConfiguration(record_sentence_offsets  = true,
                                  record_paragraph_offsets = true,
                                  record_document_offsets  = true,
                                  record_character_offsets = true)

    docs   = ["ab cd", "ef. gh"]
    tokens, offs = tokenize_and_segment(docs, cfg)

    @test tokens == ["ab", "cd", "ef.", "gh"]          # keep the dot

    @test offs[:document]  == [1, 3, 5]                # unchanged
    @test offs[:sentence]  == [1, 3, 4, 5]             # extra sentence split
    @test offs[:character] == [1, 3, 6, 9, 11]         # 4 tokens + sentinel
    @test length(offs[:character]) == length(tokens) + 1
end


"""
    specials_ok(vocab, specials)

Return `true` iff every (sym => tok) entry in `specials` appears in
`vocab.special_tokens` and has frequency 0.
"""
function specials_ok(vocab, specials)
    for (sym, tok) in specials
        haskey(vocab.special_tokens, sym)      || return false
        id = vocab.special_tokens[sym]
        vocab.id_to_token_strings[id] == tok   || return false
        vocab.token_frequencies[id] == 0       || return false
        vocab.token_to_id_map[tok] == id       || return false
    end
    return true
end


@testset "basic vocabulary" begin
    # 1 build with user-supplied special tokens
    toks = ["a","b","b","c","c","c"]           # counts 1,2,3
    user_specials = Dict(:unk=>"<UNK>", :pad=>"<PAD>")
    cfg  = PreprocessConfiguration(minimum_token_frequency = 1,
                                   special_tokens = user_specials)

    vocab = build_vocabulary(toks; cfg = cfg, id_type = UInt8)

    @test specials_ok(vocab, user_specials)        # user tokens present
    @test all(freq ≥ 0 for freq in vocab.token_frequencies)

    # 2 min-frequency filter removes infrequent tokens
    cfg2   = PreprocessConfiguration(minimum_token_frequency = 2)
    vocab2 = build_vocabulary(toks; cfg = cfg2, id_type = UInt8)

    @test !haskey(vocab2.token_to_id_map, "a")     # "a" appears only once -> gone
    @test haskey(vocab2.token_to_id_map, "b")      # kept
    @test haskey(vocab2.token_to_id_map, "c")      # kept

    # size check:   (# kept tokens)  +  (# special tokens inserted by builder)
    num_specials = length(vocab2.id_to_token_strings) -
                   length(filter(t -> t in ("b","c"), vocab2.id_to_token_strings))
    @test length(vocab2.id_to_token_strings) ==
          num_specials + 2                        # b, c

    # 3 internal consistency round-trip
    for (id, tok) in enumerate(vocab.id_to_token_strings)
        @test vocab.token_to_id_map[tok] == id
        @test 0 <= vocab.token_frequencies[id]
    end
end


@testset "assemble_bundle" begin
    # 1 happy-path with full offsets (doc + para + sent + char)
    toks = ["α", "β", "γ", "δ"]          # four tokens
    offs = Dict( :document  => [1, 5],
                 :paragraph => [1, 3, 5],
                 :sentence  => [1, 3, 5],
                 :character => [1, 3,   5, 7,  9])  # sentinel = len+1

    #build a tiny vocabulary with specials + tokens
    specials = Dict(:unk => "<UNK>", :pad => "<PAD>")
    cfg      = PreprocessConfiguration(special_tokens = specials)
    vocab    = build_vocabulary(toks; cfg = cfg, id_type = UInt8)

    #assemble bundle
    bundle = assemble_bundle(toks, offs, vocab, cfg; offset_type = UInt16)

    #assertions 
    @test bundle.corpus_storage.token_ids isa Vector{UInt8}
    @test bundle.corpus_storage.document_offsets == UInt16[1, 5]
    @test bundle.corpus_storage.paragraph_offsets == UInt16[1, 3, 5]
    @test bundle.corpus_storage.sentence_offsets  == UInt16[1, 3, 5]
    @test bundle.corpus_storage.character_offsets == UInt16[1, 3, 5, 7, 9]

    @test bundle.levels_present[:word]
    @test bundle.levels_present[:sentence]
    @test bundle.levels_present[:paragraph]
    @test bundle.levels_present[:character]
    @test bundle.levels_present[:document]

    # 2 OOV token is mapped to <UNK> ID
    toks2  = ["α", "ζ"]                      # ζ not in vocab
    offs2  = Dict(:document => [1, 3])
    bundle2 = assemble_bundle(toks2, offs2, vocab, cfg; offset_type = Int)

    unk_id = vocab.special_tokens[:unk]
    id_vec = bundle2.corpus_storage.token_ids
    @test id_vec[1] == vocab.token_to_id_map["α"]
    @test id_vec[2] == unk_id   # ζ to <UNK>

    # 3 No paragraph / sentence offsets supplied
    offs3 = Dict(:document => [1, 4])
    b3    = assemble_bundle(toks, offs3, vocab, cfg)
    @test b3.corpus_storage.paragraph_offsets === nothing
    @test b3.levels_present[:paragraph] == false
end


@testset "build & encode" begin
    prep, train = build_preprocessor(["ab cd", "ef"]; lowercase=false)
    val         = encode_corpus(prep, ["cd gh"])

    @test prep.vocabulary === train.vocabulary === val.vocabulary
    @test train.levels_present[:document] && val.levels_present[:document]
end


@testset "pipeline entry points" begin
    raw_docs = ["Héllö  WORLD!\nab", "cd ef"]

    # 1 preprocess_corpus with keyword overrides
    bundle_kw = preprocess_corpus(raw_docs;
                                  strip_accents = true,
                                  lowercase     = true,
                                  remove_punctuation = true,
                                  record_character_offsets = true,
                                  id_type     = UInt16,
                                  offset_type = UInt32)

    @test bundle_kw.corpus_storage.token_ids isa Vector{UInt16}
    @test bundle_kw.corpus_storage.document_offsets isa Vector{UInt32}
    @test bundle_kw.levels_present[:character]            # requested
    @test bundle_kw.vocabulary isa Vocabulary

    # 2 preprocess_corpus with an explicit PreprocessConfiguration
    cfg = PreprocessConfiguration(lowercase=false,
                                  strip_accents=false,
                                  tokenizer_name = :unicode,
                                  record_sentence_offsets=false)

    bundle_cfg = preprocess_corpus(raw_docs, cfg; id_type = UInt8)

    @test !bundle_cfg.levels_present[:sentence]
    @test bundle_cfg.pipeline_metadata.configuration == cfg

    # 3 build_preprocessor -> encode_corpus
    prep, train = build_preprocessor(raw_docs; lowercase=true)
    val         = encode_corpus(prep, ["ab cd", "gh"])

    # same vocabulary object reused
    @test prep.vocabulary === train.vocabulary === val.vocabulary

    # OOV token 'gh' maps to <UNK>
    unk_id = prep.vocabulary.special_tokens[:unk]
    @test val.corpus_storage.token_ids[end] == unk_id
end


@testset "basic paths for the chunks/docs" begin
    cfg = PreprocessConfiguration(      # ← add this
        record_sentence_offsets  = true,
        record_paragraph_offsets = true,
        record_document_offsets  = true,
        record_character_offsets = true)

    #  batch path 
    docs   = ["foo bar", "baz"]
    tok1, off1 = tokenize_and_segment(docs, cfg)
    @test tok1 == ["foo", "bar", "baz"]

    #  streaming path 
    chunks = [("foo ", false), ("bar\n", true), ("baz", true)]
    tok2, off2 = tokenize_and_segment(chunks, cfg)
    @test tok2 == ["foo", "bar", "baz"]
end


@testset "basic chunk/streaming" begin
    cfg  = PreprocessConfiguration(chunk_size = 4)  # tiny for test
    bund = collect(preprocess_corpus_streaming(["a b", "c d e", "f"]; cfg = cfg))
    @test length(bund) == 2            # first chunk 'a b c d', second 'e f'
    total = sum(length(b.corpus_storage.token_ids) for b in bund)
    @test total == 6
end