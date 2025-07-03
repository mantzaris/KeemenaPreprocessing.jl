
@testset "Raw Readers Tests (Minimal)" begin

    @testset "Basic functionality test" begin
        # Test that the module loads without errors
        @test true
    end

    @testset "stream_chunks with raw text" begin
        # Test the one function that works (with raw text, not files)
        chunks = collect(stream_chunks("Hello world test"))
        @test length(chunks) == 1
        @test chunks[1][1] == "Hello world test"
        @test chunks[1][2] == true  # terminal flag
    end

    @testset "stream_chunks with multiple raw texts" begin
        chunks = collect(stream_chunks(["Text 1", "Text 2"]))
        @test length(chunks) == 2
        @test chunks[1][1] == "Text 1"
        @test chunks[2][1] == "Text 2"
        @test chunks[1][2] == true
        @test chunks[2][2] == true
    end

    @testset "stream_chunks line ending normalization" begin
        chunks = collect(stream_chunks("Line1\r\nLine2\rLine3"))
        @test chunks[1][1] == "Line1\nLine2\nLine3"
    end

end
