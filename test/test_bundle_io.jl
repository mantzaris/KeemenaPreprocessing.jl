

# helper function to create a test bundle
function _create_test_bundle()
    # create a simple test bundle
    tokens = ["hello", "world", "test"]
    vocab = KeemenaPreprocessing.Vocabulary(
        ["<UNK>", "hello", "world", "test"],
        Dict("hello" => 2, "world" => 3, "test" => 4, "<UNK>" => 1),
        [0, 1, 1, 1],
        Dict(:unk => 1)
    )
    offsets = Dict(:document => [1, 4])
    cfg = KeemenaPreprocessing.PreprocessConfiguration(tokenizer_name=:whitespace)
    
    return assemble_bundle(tokens, offsets, vocab, cfg)
end

@testset "_BundleIO Module Tests" begin

    # create a temporary directory for test files
    test_dir = mktempdir()
    
    @testset "Basic save and load" begin
        bundle = _create_test_bundle()
        test_path = joinpath(test_dir, "test_bundle.jld2")
        
        #test save
        saved_path = KeemenaPreprocessing.save_preprocess_bundle(bundle, test_path)
        @test saved_path == abspath(test_path)
        @test isfile(saved_path)
        
        # test load
        loaded_bundle = KeemenaPreprocessing.load_preprocess_bundle(saved_path)
        @test loaded_bundle isa KeemenaPreprocessing.PreprocessBundle
        
        # verify basic structure is preserved
        @test haskey(loaded_bundle.levels, :word)
        @test loaded_bundle.levels[:word].corpus.token_ids == bundle.levels[:word].corpus.token_ids
        @test loaded_bundle.levels[:word].vocabulary.token_to_id_map == bundle.levels[:word].vocabulary.token_to_id_map
    end

    @testset "Save with compression options" begin
        bundle = _create_test_bundle()
        
        # test with compression
        compressed_path = joinpath(test_dir, "compressed.jld2")
        KeemenaPreprocessing.save_preprocess_bundle(bundle, compressed_path, compress=true)
        @test isfile(compressed_path)
        
        # test without compression
        uncompressed_path = joinpath(test_dir, "uncompressed.jld2")
        KeemenaPreprocessing.save_preprocess_bundle(bundle, uncompressed_path, compress=false)
        @test isfile(uncompressed_path)
        
        #both should load successfully
        loaded1 = KeemenaPreprocessing.load_preprocess_bundle(compressed_path)
        loaded2 = KeemenaPreprocessing.load_preprocess_bundle(uncompressed_path)
        @test loaded1.levels[:word].corpus.token_ids == loaded2.levels[:word].corpus.token_ids
    end

    @testset "Directory creation" begin
        bundle = _create_test_bundle()
        nested_path = joinpath(test_dir, "nested", "deep", "bundle.jld2")
        
        #should create directories automatically
        saved_path = KeemenaPreprocessing.save_preprocess_bundle(bundle, nested_path)
        @test isfile(saved_path)
        @test isdir(dirname(saved_path))
    end

    @testset "Format validation" begin
        bundle = _create_test_bundle()
        test_path = joinpath(test_dir, "format_test.jld2")
        
        # valid format should work
        @test_nowarn KeemenaPreprocessing.save_preprocess_bundle(bundle, test_path, format=:jld2)
        
        # invalid format should error
        @test_throws ErrorException KeemenaPreprocessing.save_preprocess_bundle(bundle, test_path, format=:invalid)
        @test_throws ErrorException KeemenaPreprocessing.load_preprocess_bundle(test_path, format=:invalid)
    end

    @testset "File existence validation" begin
        nonexistent_path = joinpath(test_dir, "does_not_exist.jld2")
        
        #loading non-existent file should error
        @test_throws ArgumentError KeemenaPreprocessing.load_preprocess_bundle(nonexistent_path)
    end

    @testset "Version handling" begin
        bundle = _create_test_bundle()
        test_path = joinpath(test_dir, "version_test.jld2")
        
        # save bundle
        KeemenaPreprocessing.save_preprocess_bundle(bundle, test_path)
        
        #check that version information is stored
        jldopen(test_path, "r") do file
            @test haskey(file, "__bundle_version__")
            @test haskey(file, "__schema_version__")
            @test haskey(file, "bundle")
        end
        
        # should load without issues
        @test_nowarn KeemenaPreprocessing.load_preprocess_bundle(test_path)
    end

    @testset "Round-trip consistency" begin
        #create a more complex bundle
        tokens = ["hello", "world", "test", "document"]
        vocab = KeemenaPreprocessing.Vocabulary(
            ["<UNK>", "<PAD>", "hello", "world", "test", "document"],
            Dict("hello" => 3, "world" => 4, "test" => 5, "document" => 6, "<UNK>" => 1, "<PAD>" => 2),
            [0, 0, 2, 1, 1, 1],
            Dict(:unk => 1, :pad => 2)
        )
        offsets = Dict(
            :document => [1, 3, 5],
            :word => [1, 2, 3, 4, 5]
        )
        cfg = KeemenaPreprocessing.PreprocessConfiguration(
            tokenizer_name=:whitespace,
            lowercase=false,
            record_word_offsets=true
        )
        
        original_bundle = KeemenaPreprocessing.assemble_bundle(tokens, offsets, vocab, cfg)
        test_path = joinpath(test_dir, "roundtrip.jld2")
        
        # save and load
        KeemenaPreprocessing.save_preprocess_bundle(original_bundle, test_path)
        loaded_bundle = KeemenaPreprocessing.load_preprocess_bundle(test_path)
        
        # verify detailed consistency
        @test loaded_bundle.levels[:word].corpus.token_ids == original_bundle.levels[:word].corpus.token_ids
        @test loaded_bundle.levels[:word].corpus.document_offsets == original_bundle.levels[:word].corpus.document_offsets
        @test loaded_bundle.levels[:word].corpus.word_offsets == original_bundle.levels[:word].corpus.word_offsets
        @test loaded_bundle.levels[:word].vocabulary.token_to_id_map == original_bundle.levels[:word].vocabulary.token_to_id_map
        @test loaded_bundle.levels[:word].vocabulary.special_tokens == original_bundle.levels[:word].vocabulary.special_tokens
    end

    @testset "Path handling" begin
        bundle = _create_test_bundle()
        
        # test relative path
        relative_path = "relative_bundle.jld2"
        saved_path = KeemenaPreprocessing.save_preprocess_bundle(bundle, relative_path)
        @test isabspath(saved_path)
        @test isfile(saved_path)
        
        # should be able to load with both relative and absolute paths
        @test_nowarn KeemenaPreprocessing.load_preprocess_bundle(relative_path)
        @test_nowarn KeemenaPreprocessing.load_preprocess_bundle(saved_path)
        
        # clean up
        rm(saved_path)
    end

    # clean up test directory
    rm(test_dir, recursive=true)

end

