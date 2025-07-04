

@testset "_Cleaning Module Tests (Corrected)" begin

    @testset "No cleaning applied" begin
        docs = ["Hello World!", "Test 123"]
        cfg = KeemenaPreprocessing.PreprocessConfiguration(
            lowercase=false, strip_accents=false, remove_control_characters=false,
            remove_punctuation=false, normalise_whitespace=false, trim_edges=false
        )
        result = KeemenaPreprocessing.clean_documents(docs, cfg)
        @test result == docs
    end

    @testset "Lowercase conversion only" begin
        docs = ["Hello WORLD!", "MiXeD CaSe"]
        cfg = KeemenaPreprocessing.PreprocessConfiguration(
            lowercase=true, strip_accents=false, remove_control_characters=false,
            remove_punctuation=false, normalise_whitespace=false, trim_edges=false
        )
        result = KeemenaPreprocessing.clean_documents(docs, cfg)
        @test result == ["hello world!", "mixed case"]
    end

    @testset "Strip accents only" begin
        docs = ["café", "résumé", "naïve"]
        cfg = KeemenaPreprocessing.PreprocessConfiguration(
            lowercase=false, strip_accents=true, remove_control_characters=false,
            remove_punctuation=false, normalise_whitespace=false, trim_edges=false
        )
        result = KeemenaPreprocessing.clean_documents(docs, cfg)
        @test result == ["cafe", "resume", "naive"]
    end

    @testset "Remove control characters only" begin
        docs = ["normal text", "with\ttab\nand newline"]
        cfg = KeemenaPreprocessing.PreprocessConfiguration(
            lowercase=false, strip_accents=false, remove_control_characters=true,
            remove_punctuation=false, normalise_whitespace=false, trim_edges=false
        )
        result = KeemenaPreprocessing.clean_documents(docs, cfg)
        @test result == ["normal text", "withtaband newline"]
    end

    @testset "Remove punctuation only" begin
        docs = ["Hello, world!", "Test... 123?"]
        cfg = KeemenaPreprocessing.PreprocessConfiguration(
            lowercase=false, strip_accents=false, remove_control_characters=false,
            remove_punctuation=true, normalise_whitespace=false, trim_edges=false
        )
        result = KeemenaPreprocessing.clean_documents(docs, cfg)
        @test result == ["Hello world", "Test 123"]
    end

    @testset "Normalize whitespace only" begin
        docs = ["multiple   spaces", "mixed\t\nwhitespace"]
        cfg = KeemenaPreprocessing.PreprocessConfiguration(
            lowercase=false, strip_accents=false, remove_control_characters=false,
            remove_punctuation=false, normalise_whitespace=true, trim_edges=false
        )
        result = KeemenaPreprocessing.clean_documents(docs, cfg)
        @test result == ["multiple spaces", "mixed whitespace"]
    end

    @testset "Trim edges only" begin
        docs = ["  leading", "trailing  ", "  both  "]
        cfg = PreprocessConfiguration(
            lowercase=false, strip_accents=false, remove_control_characters=false,
            remove_punctuation=false, normalise_whitespace=false, trim_edges=true
        )
        result = KeemenaPreprocessing.clean_documents(docs, cfg)
        @test result == ["leading", "trailing", "both"]
    end

    @testset "All operations combined" begin
        docs = ["  Hello, WORLD!  ", "  Café... TEST  "]
        cfg = KeemenaPreprocessing.PreprocessConfiguration(
            lowercase=true, strip_accents=true, remove_control_characters=true,
            remove_punctuation=true, normalise_whitespace=true, trim_edges=true
        )
        result = KeemenaPreprocessing.clean_documents(docs, cfg)
        @test result == ["hello world", "cafe test"]
    end

    @testset "Default configuration behavior" begin
        # Test with default PreprocessConfiguration to see what it actually does
        docs = ["  Hello, WORLD!  "]
        cfg = KeemenaPreprocessing.PreprocessConfiguration()  # Use defaults
        result = KeemenaPreprocessing.clean_documents(docs, cfg)
        
        # Just verify it returns a vector of the same length
        @test length(result) == 1
        @test result isa Vector{String}
    end

    @testset "Vector structure preservation" begin
        docs = ["doc1", "doc2", "doc3"]
        cfg = KeemenaPreprocessing.PreprocessConfiguration(
            lowercase=false, strip_accents=false, remove_control_characters=false,
            remove_punctuation=false, normalise_whitespace=false, trim_edges=false
        )
        result = KeemenaPreprocessing.clean_documents(docs, cfg)
        
        @test length(result) == length(docs)
        @test result !== docs  # Different vector object
        @test result == docs   # Same content when no cleaning applied
    end

end
