@testset "Subword Integration" begin
    using KeemenaSubwords

    function _hf_wordpiece_fixture_path()
        root = normpath(joinpath(dirname(pathof(KeemenaSubwords)), ".."))
        fixture = joinpath(root, "test", "fixtures", "hf_json_wordpiece", "tokenizer.json")
        isfile(fixture) || error("Missing KeemenaSubwords fixture: $fixture")
        return fixture
    end

    @testset "SubwordOptions construction" begin
        fixture = _hf_wordpiece_fixture_path()
        opts = KeemenaPreprocessing.SubwordOptions(source = fixture, format = :hf_tokenizer_json)

        @test opts.source == fixture
        @test opts.format == :hf_tokenizer_json
        @test opts.mode == :tokenizer_native
        @test opts.level_name == :subword
        @test opts.add_special_tokens
        @test opts.apply_tokenization_view
        @test opts.return_offsets
        @test opts.return_masks
    end

    @testset "preprocess_corpus tokenizer-native subword path" begin
        fixture = _hf_wordpiece_fixture_path()
        docs = ["Hello world", "hello, world!"]

        cfg = KeemenaPreprocessing.PreprocessConfiguration(
            subword = KeemenaPreprocessing.SubwordOptions(
                source = fixture,
                format = :hf_tokenizer_json,
                mode = :tokenizer_native,
                level_name = :subword,
                add_special_tokens = true,
                apply_tokenization_view = true,
                return_offsets = true,
                return_masks = true,
            ),
        )

        bundle = KeemenaPreprocessing.preprocess_corpus(docs; config = cfg)
        @test KeemenaPreprocessing.has_level(bundle, :subword)

        # reference ids from direct KeemenaSubwords use on the same cleaned input
        tokenizer = KeemenaSubwords.load_tokenizer(fixture; format = :hf_tokenizer_json)
        clean_docs = KeemenaPreprocessing.clean_documents(docs, cfg)
        expected_ids = Int[]
        for doc in clean_docs
            tokenization_text = KeemenaSubwords.tokenization_view(tokenizer, doc)
            result = KeemenaSubwords.encode_result(
                tokenizer, tokenization_text;
                add_special_tokens = true,
                assume_normalized = true,
                return_offsets = true,
                return_masks = true,
            )
            append!(expected_ids, result.ids)
        end

        @test KeemenaPreprocessing.get_token_ids(bundle, :subword) == expected_ids

        offsets = KeemenaPreprocessing.get_subword_offsets(bundle)
        attn = KeemenaPreprocessing.get_subword_attention_mask(bundle)
        ttype = KeemenaPreprocessing.get_subword_token_type_ids(bundle)
        smask = KeemenaPreprocessing.get_subword_special_tokens_mask(bundle)
        meta = KeemenaPreprocessing.get_subword_metadata(bundle)

        @test offsets !== nothing
        @test attn !== nothing
        @test ttype !== nothing
        @test smask !== nothing
        @test length(offsets) == length(docs)
        @test length(attn) == length(docs)
        @test length(ttype) == length(docs)
        @test length(smask) == length(docs)
        @test meta.level_name == :subword
        @test meta.mode == :tokenizer_native
        @test haskey(meta, :tokenizer)

        mktempdir() do tmp
            path = joinpath(tmp, "subword_bundle.jld2")
            KeemenaPreprocessing.save_preprocess_bundle(bundle, path)
            reloaded = KeemenaPreprocessing.load_preprocess_bundle(path)
            @test KeemenaPreprocessing.get_subword_offsets(reloaded) == offsets
            @test KeemenaPreprocessing.get_subword_attention_mask(reloaded) == attn
            @test KeemenaPreprocessing.get_subword_token_type_ids(reloaded) == ttype
            @test KeemenaPreprocessing.get_subword_special_tokens_mask(reloaded) == smask
        end
    end

    @testset "preprocess_corpus bundle-reindexed subword path" begin
        fixture = _hf_wordpiece_fixture_path()
        docs = [
            "rarealpha common common",
            "common rarebeta and common",
        ]

        cfg = KeemenaPreprocessing.PreprocessConfiguration(
            minimum_token_frequency = 2,
            special_tokens = Dict(:unk => "<UNK>", :pad => "<PAD>"),
            subword = KeemenaPreprocessing.SubwordOptions(
                source = fixture,
                format = :hf_tokenizer_json,
                mode = :bundle_reindexed,
                level_name = :subword,
                add_special_tokens = false,
                apply_tokenization_view = true,
                return_offsets = true,
                return_masks = true,
            ),
        )

        bundle = KeemenaPreprocessing.preprocess_corpus(docs; config = cfg)
        @test KeemenaPreprocessing.has_level(bundle, :subword)

        tokenizer = KeemenaSubwords.load_tokenizer(fixture; format = :hf_tokenizer_json)
        clean_docs = KeemenaPreprocessing.clean_documents(docs, cfg)

        all_tokens = String[]
        expected_doc_offsets = Int[1]
        expected_offsets = Vector{Union{Nothing,Vector{Tuple{Int,Int}}}}()
        expected_attn = Vector{Union{Nothing,Vector{Int}}}()
        expected_ttype = Vector{Union{Nothing,Vector{Int}}}()
        expected_smask = Vector{Union{Nothing,Vector{Int}}}()
        for doc in clean_docs
            tokenization_text = KeemenaSubwords.tokenization_view(tokenizer, doc)
            result = KeemenaSubwords.encode_result(
                tokenizer, tokenization_text;
                add_special_tokens = false,
                assume_normalized = true,
                return_offsets = true,
                return_masks = true,
            )
            append!(all_tokens, result.tokens)
            push!(expected_doc_offsets, length(all_tokens) + 1)
            push!(expected_offsets, result.offsets)
            push!(expected_attn, result.attention_mask)
            push!(expected_ttype, result.token_type_ids)
            push!(expected_smask, result.special_tokens_mask)
        end

        vocab_cfg = KeemenaPreprocessing.PreprocessConfiguration(
            minimum_token_frequency = cfg.minimum_token_frequency,
            special_tokens = cfg.special_tokens,
            record_sentence_offsets = false,
        )
        expected_vocab = KeemenaPreprocessing.build_vocabulary(all_tokens; cfg = vocab_cfg)
        expected_unk = expected_vocab.special_tokens[:unk]
        expected_ids = [get(expected_vocab.token_to_id_map, tok, expected_unk) for tok in all_tokens]

        token_ids = KeemenaPreprocessing.get_token_ids(bundle, :subword)
        @test token_ids == expected_ids
        @test bundle.levels[:subword].corpus.document_offsets == expected_doc_offsets
        @test bundle.levels[:subword].vocabulary.id_to_token_strings == expected_vocab.id_to_token_strings
        @test bundle.levels[:subword].vocabulary.special_tokens == expected_vocab.special_tokens

        @test KeemenaPreprocessing.get_subword_offsets(bundle) == expected_offsets
        @test KeemenaPreprocessing.get_subword_attention_mask(bundle) == expected_attn
        @test KeemenaPreprocessing.get_subword_token_type_ids(bundle) == expected_ttype
        @test KeemenaPreprocessing.get_subword_special_tokens_mask(bundle) == expected_smask

        meta = KeemenaPreprocessing.get_subword_metadata(bundle)
        @test meta.mode == :bundle_reindexed
        @test meta.level_name == :subword
    end

    @testset "source forms and resolver coverage" begin
        fixture = _hf_wordpiece_fixture_path()
        docs = ["Tokenizer source forms should resolve consistently.", "Café HELLO, world!"]

        baseline_cfg = KeemenaPreprocessing.PreprocessConfiguration(
            subword = KeemenaPreprocessing.SubwordOptions(
                source = fixture,
                format = :hf_tokenizer_json,
                mode = :tokenizer_native,
                level_name = :subword,
                add_special_tokens = true,
                apply_tokenization_view = true,
                return_offsets = true,
                return_masks = true,
            ),
        )
        baseline_bundle = KeemenaPreprocessing.preprocess_corpus(docs; config = baseline_cfg)
        baseline_ids = KeemenaPreprocessing.get_token_ids(baseline_bundle, :subword)
        baseline_offsets = KeemenaPreprocessing.get_subword_offsets(baseline_bundle)

        loaded_tok = KeemenaSubwords.load_tokenizer(fixture; format = :hf_tokenizer_json)
        file_spec = KeemenaSubwords.FilesSpec(
            format = :hf_tokenizer_json,
            tokenizer_json = fixture,
        )
        named_spec = (format = :hf_tokenizer_json, path = fixture)

        cases = [
            ("named tuple", named_spec),
            ("files spec", file_spec),
            ("preloaded tokenizer", loaded_tok),
        ]

        for (label, src) in cases
            cfg = KeemenaPreprocessing.PreprocessConfiguration(
                subword = KeemenaPreprocessing.SubwordOptions(
                    source = src,
                    format = :hf_tokenizer_json,
                    mode = :tokenizer_native,
                    level_name = :subword,
                    add_special_tokens = true,
                    apply_tokenization_view = true,
                    return_offsets = true,
                    return_masks = true,
                ),
            )
            bundle = KeemenaPreprocessing.preprocess_corpus(docs; config = cfg)
            @test KeemenaPreprocessing.get_token_ids(bundle, :subword) == baseline_ids
            @test KeemenaPreprocessing.get_subword_offsets(bundle) == baseline_offsets
            @test KeemenaPreprocessing.get_subword_metadata(bundle).level_name == :subword
        end

        cfg_symbol = KeemenaPreprocessing.PreprocessConfiguration(
            subword = KeemenaPreprocessing.SubwordOptions(
                source = :core_bpe_en,
                mode = :tokenizer_native,
                level_name = :subword,
            ),
        )
        bundle_symbol = KeemenaPreprocessing.preprocess_corpus(docs; config = cfg_symbol)
        @test KeemenaPreprocessing.has_level(bundle_symbol, :subword)
        @test !isempty(KeemenaPreprocessing.get_token_ids(bundle_symbol, :subword))
        @test KeemenaPreprocessing.get_subword_metadata(bundle_symbol).source == ":core_bpe_en"

        cfg_no_view = KeemenaPreprocessing.PreprocessConfiguration(
            lowercase = false,
            strip_accents = false,
            remove_punctuation = false,
            subword = KeemenaPreprocessing.SubwordOptions(
                source = fixture,
                format = :hf_tokenizer_json,
                mode = :native,
                apply_tokenization_view = false,
                return_offsets = true,
            ),
        )
        bundle_no_view = KeemenaPreprocessing.preprocess_corpus(["Café HELLO, world!"]; config = cfg_no_view)
        meta_no_view = KeemenaPreprocessing.get_subword_metadata(bundle_no_view)
        clean_doc = KeemenaPreprocessing.clean_documents(["Café HELLO, world!"], cfg_no_view)[1]
        expected_tok_view = KeemenaSubwords.tokenization_view(loaded_tok, clean_doc)
        @test meta_no_view.tokenization_texts[1] == expected_tok_view
        @test meta_no_view.per_document[1].offsets_reference == :tokenizer_normalized_text

        docs_coop = ["Café HELLO, world! Visit https://example.com and email support@example.com."]
        cfg_coop = KeemenaPreprocessing.PreprocessConfiguration(
            cleaning_profile = :subword_cooperative,
            lowercase = true,
            strip_accents = true,
            remove_punctuation = true,
            replace_urls = true,
            replace_emails = true,
            subword = KeemenaPreprocessing.SubwordOptions(
                source = fixture,
                format = :hf_tokenizer_json,
                mode = :tokenizer_native,
                level_name = :subword,
                add_special_tokens = true,
                apply_tokenization_view = true,
                return_offsets = true,
                return_masks = true,
            ),
        )
        clean_coop = KeemenaPreprocessing.clean_documents(docs_coop, cfg_coop)
        @test occursin("Café HELLO, world!", clean_coop[1])
        @test occursin("https://example.com", clean_coop[1])
        @test occursin("support@example.com", clean_coop[1])
        @test cfg_coop.cleaning_profile == :subword_cooperative

        bundle_coop = KeemenaPreprocessing.preprocess_corpus(docs_coop; config = cfg_coop)
        tokenizer_coop = KeemenaSubwords.load_tokenizer(fixture; format = :hf_tokenizer_json)
        tok_view = KeemenaSubwords.tokenization_view(tokenizer_coop, clean_coop[1])
        expected_coop = KeemenaSubwords.encode_result(
            tokenizer_coop, tok_view;
            add_special_tokens = true,
            assume_normalized = true,
            return_offsets = true,
            return_masks = true,
        )
        @test KeemenaPreprocessing.get_token_ids(bundle_coop, :subword) == expected_coop.ids
        @test KeemenaPreprocessing.get_subword_offsets(bundle_coop)[1] == expected_coop.offsets
        @test KeemenaPreprocessing.get_subword_token_type_ids(bundle_coop)[1] == expected_coop.token_type_ids

        cfg_coop_alias = KeemenaPreprocessing.PreprocessConfiguration(
            cleaning_profile = :subword_safe,
            subword = KeemenaPreprocessing.SubwordOptions(
                source = fixture,
                format = :hf_tokenizer_json,
            ),
        )
        @test cfg_coop_alias.cleaning_profile == :subword_cooperative

        cfg_bad_src = KeemenaPreprocessing.PreprocessConfiguration(
            subword = KeemenaPreprocessing.SubwordOptions(
                source = 12345,
                format = :hf_tokenizer_json,
            ),
        )
        @test_throws ArgumentError KeemenaPreprocessing.preprocess_corpus(docs; config = cfg_bad_src)
    end

    @testset "realistic long text: cleaning, subwords, and alignment consistency" begin
        fixture = _hf_wordpiece_fixture_path()
        docs = [
            "Subword tokenization helps with rare compounds and morphology. " *
            "This paragraph includes rerunning and retokenization checks across several sentences for realistic coverage.",
            "Keemena preprocessing should normalize noisy text before subwords: " *
            "visit https://example.com/docs?v=2 and email support@example.com for updates. " *
            "Then we run alignment checks again on the cleaned text.",
        ]

        cfg = KeemenaPreprocessing.PreprocessConfiguration(
            subword = KeemenaPreprocessing.SubwordOptions(
                source = fixture,
                format = :hf_tokenizer_json,
                mode = :tokenizer_native,
                level_name = :subword,
                add_special_tokens = true,
                apply_tokenization_view = true,
                return_offsets = true,
                return_masks = true,
            ),
        )

        clean_once = KeemenaPreprocessing.clean_documents(docs, cfg)
        clean_twice = KeemenaPreprocessing.clean_documents(clean_once, cfg)
        @test clean_twice == clean_once

        bundle_raw = KeemenaPreprocessing.preprocess_corpus(docs; config = cfg)
        bundle_clean = KeemenaPreprocessing.preprocess_corpus(clean_once; config = cfg)

        @test KeemenaPreprocessing.get_token_ids(bundle_raw, :subword) ==
              KeemenaPreprocessing.get_token_ids(bundle_clean, :subword)
        @test KeemenaPreprocessing.get_subword_offsets(bundle_raw) ==
              KeemenaPreprocessing.get_subword_offsets(bundle_clean)

        tokenizer = KeemenaSubwords.load_tokenizer(fixture; format = :hf_tokenizer_json)
        offsets = KeemenaPreprocessing.get_subword_offsets(bundle_raw)
        attn = KeemenaPreprocessing.get_subword_attention_mask(bundle_raw)
        ttype = KeemenaPreprocessing.get_subword_token_type_ids(bundle_raw)
        smask = KeemenaPreprocessing.get_subword_special_tokens_mask(bundle_raw)
        meta = KeemenaPreprocessing.get_subword_metadata(bundle_raw)
        @test offsets !== nothing
        @test attn !== nothing
        @test ttype !== nothing
        @test smask !== nothing

        token_ids = KeemenaPreprocessing.get_token_ids(bundle_raw, :subword)
        doc_offsets = bundle_raw.levels[:subword].corpus.document_offsets

        for i in eachindex(clean_once)
            tokenization_text = KeemenaSubwords.tokenization_view(tokenizer, clean_once[i])
            @test meta.tokenization_texts[i] == tokenization_text

            result = KeemenaSubwords.encode_result(
                tokenizer, tokenization_text;
                add_special_tokens = true,
                assume_normalized = true,
                return_offsets = true,
                return_masks = true,
            )

            r = doc_offsets[i]:(doc_offsets[i + 1] - 1)
            @test token_ids[r] == result.ids
            @test offsets[i] == result.offsets
            @test attn[i] == result.attention_mask
            @test ttype[i] == result.token_type_ids
            @test smask[i] == result.special_tokens_mask

            @test length(offsets[i]) == length(result.ids)
            @test length(attn[i]) == length(result.ids)
            @test length(ttype[i]) == length(result.ids)
            @test length(smask[i]) == length(result.ids)

            # Alignment sanity: positive spans should be ordered and inside text bounds.
            max_pos = ncodeunits(tokenization_text) + 1
            prev_start = 1
            for (start_pos, end_pos) in offsets[i]
                if start_pos > 0 && end_pos > 0
                    @test start_pos <= end_pos
                    @test start_pos >= prev_start
                    @test end_pos <= max_pos
                    prev_start = start_pos
                else
                    # tokenizer-level special/sentinel offsets are allowed
                    @test start_pos <= 0 && end_pos <= 0
                end
            end
        end
    end

    @testset "end-to-end raw paragraph with line breaks" begin
        fixture = _hf_wordpiece_fixture_path()
        raw_paragraph = """
        Subword processing should be tested on realistic text.
        This paragraph has multiple sentences and deliberate line breaks.

        It also includes URLs like https://example.com/path?q=7 and mail contact@example.com.
        Final sentence checks end-to-end bundle consistency.
        """
        docs = [raw_paragraph]
        @test count(==('\n'), raw_paragraph) >= 3

        cfg = KeemenaPreprocessing.PreprocessConfiguration(
            subword = KeemenaPreprocessing.SubwordOptions(
                source = fixture,
                format = :hf_tokenizer_json,
                mode = :tokenizer_native,
                level_name = :subword,
                add_special_tokens = true,
                apply_tokenization_view = true,
                return_offsets = true,
                return_masks = true,
            ),
        )

        bundle = KeemenaPreprocessing.preprocess_corpus(docs; config = cfg)
        @test KeemenaPreprocessing.has_level(bundle, :subword)

        token_ids = KeemenaPreprocessing.get_token_ids(bundle, :subword)
        @test !isempty(token_ids)

        corpus = bundle.levels[:subword].corpus
        @test corpus.document_offsets == [1, length(token_ids) + 1]

        offsets = KeemenaPreprocessing.get_subword_offsets(bundle)
        attn = KeemenaPreprocessing.get_subword_attention_mask(bundle)
        ttype = KeemenaPreprocessing.get_subword_token_type_ids(bundle)
        smask = KeemenaPreprocessing.get_subword_special_tokens_mask(bundle)
        meta = KeemenaPreprocessing.get_subword_metadata(bundle)

        @test offsets !== nothing
        @test attn !== nothing
        @test ttype !== nothing
        @test smask !== nothing
        @test length(offsets) == 1
        @test length(attn) == 1
        @test length(ttype) == 1
        @test length(smask) == 1
        @test meta.level_name == :subword
        @test meta.mode == :tokenizer_native

        tokenizer = KeemenaSubwords.load_tokenizer(fixture; format = :hf_tokenizer_json)
        clean_doc = KeemenaPreprocessing.clean_documents(docs, cfg)[1]
        @test !isempty(clean_doc)

        tokenization_text = KeemenaSubwords.tokenization_view(tokenizer, clean_doc)
        @test meta.tokenization_texts[1] == tokenization_text

        expected = KeemenaSubwords.encode_result(
            tokenizer, tokenization_text;
            add_special_tokens = true,
            assume_normalized = true,
            return_offsets = true,
            return_masks = true,
        )

        @test token_ids == expected.ids
        @test offsets[1] == expected.offsets
        @test attn[1] == expected.attention_mask
        @test ttype[1] == expected.token_type_ids
        @test smask[1] == expected.special_tokens_mask
        @test length(offsets[1]) == length(token_ids)
        @test length(attn[1]) == length(token_ids)
        @test length(ttype[1]) == length(token_ids)
        @test length(smask[1]) == length(token_ids)

        max_pos = ncodeunits(tokenization_text) + 1
        prev_start = 1
        for (start_pos, end_pos) in offsets[1]
            if start_pos > 0 && end_pos > 0
                @test start_pos <= end_pos
                @test start_pos >= prev_start
                @test end_pos <= max_pos
                prev_start = start_pos
            else
                @test start_pos <= 0 && end_pos <= 0
            end
        end

        mktempdir() do tmp
            path = joinpath(tmp, "subword_paragraph_bundle.jld2")
            KeemenaPreprocessing.save_preprocess_bundle(bundle, path)
            reloaded = KeemenaPreprocessing.load_preprocess_bundle(path)
            @test KeemenaPreprocessing.get_token_ids(reloaded, :subword) == token_ids
            @test KeemenaPreprocessing.get_subword_offsets(reloaded) == offsets
            @test KeemenaPreprocessing.get_subword_attention_mask(reloaded) == attn
            @test KeemenaPreprocessing.get_subword_token_type_ids(reloaded) == ttype
            @test KeemenaPreprocessing.get_subword_special_tokens_mask(reloaded) == smask
        end
    end

    @testset "common ML/NLP config on one multi-sentence paragraph" begin
        fixture = _hf_wordpiece_fixture_path()
        raw_paragraph = """
        BERT-style NLP pipelines usually keep casing and punctuation for cased tokenizers.
        This single paragraph includes Café accents, mixedCase tokens, and realistic prose across several sentences.
        Contact ml-team@example.org and review https://nlp.example.org/docs/v2 for setup notes before training.
        Final sentence checks end-to-end ids, offsets, masks, and metadata in one common workflow.
        """
        docs = [raw_paragraph]
        @test count(==('.'), raw_paragraph) >= 4

        cfg = KeemenaPreprocessing.PreprocessConfiguration(
            lowercase = false,
            strip_accents = false,
            remove_punctuation = false,
            replace_urls = false,
            replace_emails = false,
            subword = KeemenaPreprocessing.SubwordOptions(
                source = fixture,
                format = :hf_tokenizer_json,
                mode = :tokenizer_native,
                level_name = :subword,
                add_special_tokens = true,
                apply_tokenization_view = true,
                return_offsets = true,
                return_masks = true,
            ),
        )

        bundle = KeemenaPreprocessing.preprocess_corpus(docs; config = cfg)
        @test KeemenaPreprocessing.has_level(bundle, :subword)

        clean_doc = KeemenaPreprocessing.clean_documents(docs, cfg)[1]
        @test occursin("Café", clean_doc)
        @test occursin("https://nlp.example.org/docs/v2", clean_doc)
        @test occursin("ml-team@example.org", clean_doc)

        token_ids = KeemenaPreprocessing.get_token_ids(bundle, :subword)
        offsets = KeemenaPreprocessing.get_subword_offsets(bundle)
        attn = KeemenaPreprocessing.get_subword_attention_mask(bundle)
        ttype = KeemenaPreprocessing.get_subword_token_type_ids(bundle)
        smask = KeemenaPreprocessing.get_subword_special_tokens_mask(bundle)
        meta = KeemenaPreprocessing.get_subword_metadata(bundle)

        @test !isempty(token_ids)
        @test bundle.levels[:subword].corpus.document_offsets == [1, length(token_ids) + 1]
        @test offsets !== nothing
        @test attn !== nothing
        @test ttype !== nothing
        @test smask !== nothing
        @test length(offsets) == 1
        @test length(attn) == 1
        @test length(ttype) == 1
        @test length(smask) == 1
        @test length(offsets[1]) == length(token_ids)
        @test length(attn[1]) == length(token_ids)
        @test length(ttype[1]) == length(token_ids)
        @test length(smask[1]) == length(token_ids)
        @test any(==(1), smask[1])
        @test meta.mode == :tokenizer_native
        @test meta.level_name == :subword

        tokenizer = KeemenaSubwords.load_tokenizer(fixture; format = :hf_tokenizer_json)
        tokenization_text = KeemenaSubwords.tokenization_view(tokenizer, clean_doc)
        expected = KeemenaSubwords.encode_result(
            tokenizer, tokenization_text;
            add_special_tokens = true,
            assume_normalized = true,
            return_offsets = true,
            return_masks = true,
        )

        @test meta.tokenization_texts[1] == tokenization_text
        @test token_ids == expected.ids
        @test offsets[1] == expected.offsets
        @test attn[1] == expected.attention_mask
        @test ttype[1] == expected.token_type_ids
        @test smask[1] == expected.special_tokens_mask
    end

    @testset "streaming tokenizer-native subword parity" begin
        fixture = _hf_wordpiece_fixture_path()
        docs = [
            "Streaming subword support should work end to end for larger corpora and realistic text.",
            "This second sentence-heavy document verifies merged offsets, masks, and metadata parity.",
            "Third document keeps tokenizer-native ids stable while chunked processing stays memory bounded.",
        ]
        cfg = KeemenaPreprocessing.PreprocessConfiguration(
            cleaning_profile = :subword_cooperative,
            subword = KeemenaPreprocessing.SubwordOptions(
                source = fixture,
                format = :hf_tokenizer_json,
                mode = :tokenizer_native,
                level_name = :subword,
                add_special_tokens = true,
                apply_tokenization_view = true,
                return_offsets = true,
                return_masks = true,
            ),
        )

        baseline = KeemenaPreprocessing.preprocess_corpus(docs; config = cfg)
        chunk_tokens = 12

        chunks = KeemenaPreprocessing.preprocess_corpus_streaming_chunks(
            docs; cfg = cfg, chunk_tokens = chunk_tokens)
        @test length(chunks) > 1
        vocab_ref = chunks[1].levels[:subword].vocabulary
        @test all(b -> b.levels[:subword].vocabulary === vocab_ref, chunks)

        merged = KeemenaPreprocessing.preprocess_corpus_streaming_full(
            docs; cfg = cfg, chunk_tokens = chunk_tokens)

        @test KeemenaPreprocessing.get_token_ids(merged, :subword) ==
              KeemenaPreprocessing.get_token_ids(baseline, :subword)
        @test merged.levels[:subword].corpus.document_offsets ==
              baseline.levels[:subword].corpus.document_offsets
        @test KeemenaPreprocessing.get_subword_offsets(merged) ==
              KeemenaPreprocessing.get_subword_offsets(baseline)
        @test KeemenaPreprocessing.get_subword_attention_mask(merged) ==
              KeemenaPreprocessing.get_subword_attention_mask(baseline)
        @test KeemenaPreprocessing.get_subword_token_type_ids(merged) ==
              KeemenaPreprocessing.get_subword_token_type_ids(baseline)
        @test KeemenaPreprocessing.get_subword_special_tokens_mask(merged) ==
              KeemenaPreprocessing.get_subword_special_tokens_mask(baseline)
        @test KeemenaPreprocessing.get_subword_metadata(merged).tokenization_texts ==
              KeemenaPreprocessing.get_subword_metadata(baseline).tokenization_texts
        @test length(KeemenaPreprocessing.get_subword_metadata(merged).per_document) == length(docs)

        total_chunk_tokens = sum(length(KeemenaPreprocessing.get_token_ids(b, :subword)) for b in chunks)
        @test total_chunk_tokens == length(KeemenaPreprocessing.get_token_ids(merged, :subword))

        prebuilt_vocab = baseline.levels[:subword].vocabulary
        chunks_with_vocab = collect(KeemenaPreprocessing.preprocess_corpus_streaming(
            docs; cfg = cfg, vocab = prebuilt_vocab, chunk_tokens = chunk_tokens))
        @test all(b -> b.levels[:subword].vocabulary === prebuilt_vocab, chunks_with_vocab)
    end

    @testset "streaming bundle-reindexed subword parity" begin
        fixture = _hf_wordpiece_fixture_path()
        docs = [
            "common common rarealpha common coreterms and shared tokens",
            "common rarebeta shared terms common and common again",
            "coreterms shared tokens appear here while raregamma appears once",
        ]

        cfg = KeemenaPreprocessing.PreprocessConfiguration(
            minimum_token_frequency = 2,
            special_tokens = Dict(:unk => "<UNK>", :pad => "<PAD>"),
            subword = KeemenaPreprocessing.SubwordOptions(
                source = fixture,
                format = :hf_tokenizer_json,
                mode = :bundle_reindexed,
                level_name = :subword,
                add_special_tokens = false,
                apply_tokenization_view = true,
                return_offsets = true,
                return_masks = true,
            ),
        )

        baseline = KeemenaPreprocessing.preprocess_corpus(docs; config = cfg)
        chunk_tokens = 10

        chunks = KeemenaPreprocessing.preprocess_corpus_streaming_chunks(
            docs; cfg = cfg, chunk_tokens = chunk_tokens)
        @test length(chunks) > 1
        vocab_ref = chunks[1].levels[:subword].vocabulary
        @test all(b -> b.levels[:subword].vocabulary === vocab_ref, chunks)

        merged = KeemenaPreprocessing.preprocess_corpus_streaming_full(
            docs; cfg = cfg, chunk_tokens = chunk_tokens)

        @test KeemenaPreprocessing.get_token_ids(merged, :subword) ==
              KeemenaPreprocessing.get_token_ids(baseline, :subword)
        @test merged.levels[:subword].corpus.document_offsets ==
              baseline.levels[:subword].corpus.document_offsets
        @test merged.levels[:subword].vocabulary.id_to_token_strings ==
              baseline.levels[:subword].vocabulary.id_to_token_strings
        @test merged.levels[:subword].vocabulary.special_tokens ==
              baseline.levels[:subword].vocabulary.special_tokens
        @test KeemenaPreprocessing.get_subword_offsets(merged) ==
              KeemenaPreprocessing.get_subword_offsets(baseline)
        @test KeemenaPreprocessing.get_subword_attention_mask(merged) ==
              KeemenaPreprocessing.get_subword_attention_mask(baseline)
        @test KeemenaPreprocessing.get_subword_token_type_ids(merged) ==
              KeemenaPreprocessing.get_subword_token_type_ids(baseline)
        @test KeemenaPreprocessing.get_subword_special_tokens_mask(merged) ==
              KeemenaPreprocessing.get_subword_special_tokens_mask(baseline)
        @test KeemenaPreprocessing.get_subword_metadata(merged).mode == :bundle_reindexed

        prebuilt_vocab = baseline.levels[:subword].vocabulary
        merged_with_vocab = KeemenaPreprocessing.preprocess_corpus_streaming_full(
            docs; cfg = cfg, vocab = prebuilt_vocab, chunk_tokens = chunk_tokens)
        @test merged_with_vocab.levels[:subword].vocabulary === prebuilt_vocab
        @test KeemenaPreprocessing.get_token_ids(merged_with_vocab, :subword) ==
              KeemenaPreprocessing.get_token_ids(baseline, :subword)
    end
end
