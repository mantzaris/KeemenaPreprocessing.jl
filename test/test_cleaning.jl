
@testset "Cleaning Module Tests" begin
    
    @testset "normalize_unicode" begin
        @test KeemenaPreprocessing._Cleaning.normalize_unicode("hello") == "hello"
        @test KeemenaPreprocessing._Cleaning.normalize_unicode("hello"; form=:none) == "hello"
        @test KeemenaPreprocessing._Cleaning.normalize_unicode("café"; form=:NFC) == "café"
        @test KeemenaPreprocessing._Cleaning.normalize_unicode("café"; form=:NFD) != "café"  # decomposed form
        @test_throws ArgumentError KeemenaPreprocessing._Cleaning.normalize_unicode("test"; form=:invalid)
    end

    @testset "_strip_accents" begin
        @test KeemenaPreprocessing._Cleaning._strip_accents("hello") == "hello"
        @test KeemenaPreprocessing._Cleaning._strip_accents("café") == "cafe"
        @test KeemenaPreprocessing._Cleaning._strip_accents("naïve") == "naive"
        @test KeemenaPreprocessing._Cleaning._strip_accents("résumé") == "resume"
        @test KeemenaPreprocessing._Cleaning._strip_accents("Zürich") == "Zurich"
        @test KeemenaPreprocessing._Cleaning._strip_accents("") == ""
    end

    @testset "normalize_whitespace" begin
        #basic whitespace normalization
        @test KeemenaPreprocessing._Cleaning.normalize_whitespace("hello   world") == "hello world"
        @test KeemenaPreprocessing._Cleaning.normalize_whitespace("  hello world  ") == "hello world"
        @test KeemenaPreprocessing._Cleaning.normalize_whitespace("hello\t\tworld") == "hello world"
        @test KeemenaPreprocessing._Cleaning.normalize_whitespace("hello\n\nworld") == "hello world"
        
        #preserve newlines
        @test KeemenaPreprocessing._Cleaning.normalize_whitespace("hello\nworld"; preserve_newlines=true) == "hello\nworld"
        @test KeemenaPreprocessing._Cleaning.normalize_whitespace("hello  \n  world"; preserve_newlines=true) == "hello\nworld"
        @test KeemenaPreprocessing._Cleaning.normalize_whitespace("hello\t\nworld"; preserve_newlines=true) == "hello\nworld"
        
        #don't strip ends
        @test KeemenaPreprocessing._Cleaning.normalize_whitespace("  hello world  "; strip_ends=false) == "  hello world  "
        
        #remove zero-width characters
        @test KeemenaPreprocessing._Cleaning.normalize_whitespace("hello\u200Bworld"; remove_zero_width=true) == "hello world"
        @test KeemenaPreprocessing._Cleaning.normalize_whitespace("hello\u200C\u200Dworld"; remove_zero_width=true) == "hello world"
        @test KeemenaPreprocessing._Cleaning.normalize_whitespace("hello\uFEFFworld"; remove_zero_width=true) == "hello world"
        
        #don't collapse spaces
        @test KeemenaPreprocessing._Cleaning.normalize_whitespace("hello   world"; collapse_spaces=false) == "hello   world"
        
        #empty string
        @test KeemenaPreprocessing._Cleaning.normalize_whitespace("") == ""
    end
    
    @testset "map_unicode_punctuation" begin
        @test KeemenaPreprocessing._Cleaning.map_unicode_punctuation("hello") == "hello"
        @test KeemenaPreprocessing._Cleaning.map_unicode_punctuation("\"hello\"") == "\"hello\""
        @test KeemenaPreprocessing._Cleaning.map_unicode_punctuation("'hello'") == "'hello'"
        @test KeemenaPreprocessing._Cleaning.map_unicode_punctuation("«hello»") == "\"hello\""
        @test KeemenaPreprocessing._Cleaning.map_unicode_punctuation("hello–world") == "hello-world"
        @test KeemenaPreprocessing._Cleaning.map_unicode_punctuation("hello—world") == "hello-world"
        @test KeemenaPreprocessing._Cleaning.map_unicode_punctuation("hello…") == "hello..."
        @test KeemenaPreprocessing._Cleaning.map_unicode_punctuation("‹hello›") == "<hello>"
    end
        
    @testset "emoji functions" begin
        #  in_emoji_codepoint
        @test KeemenaPreprocessing._Cleaning.in_emoji_codepoint('😀') == true
        @test KeemenaPreprocessing._Cleaning.in_emoji_codepoint('a') == false
        @test KeemenaPreprocessing._Cleaning.in_emoji_codepoint('1') == false
        
        #  isEmoji
        @test KeemenaPreprocessing._Cleaning.isEmoji("😀") == true
        @test KeemenaPreprocessing._Cleaning.isEmoji("hello") == false
        @test KeemenaPreprocessing._Cleaning.isEmoji("a") == false
        @test KeemenaPreprocessing._Cleaning.isEmoji("") == true  # empty string should return true
        
        #  _rewrite_emojis
        cfg_keep = KeemenaPreprocessing.PreprocessConfiguration(emoji_handling=:keep)
        cfg_remove = KeemenaPreprocessing.PreprocessConfiguration(emoji_handling=:remove)
        cfg_sentinel = KeemenaPreprocessing.PreprocessConfiguration(emoji_handling=:sentinel, emoji_sentinel="<EMOJI>")
        
        @test KeemenaPreprocessing._Cleaning._rewrite_emojis("hello 😀 world", cfg_keep) == "hello 😀 world"
        @test KeemenaPreprocessing._Cleaning._rewrite_emojis("hello 😀 world", cfg_remove) == "hello  world"
        @test KeemenaPreprocessing._Cleaning._rewrite_emojis("hello 😀 world", cfg_sentinel) == "hello <EMOJI> world"
        @test KeemenaPreprocessing._Cleaning._rewrite_emojis("hello world", cfg_sentinel) == "hello world"
    end
    
    @testset "squeeze_char_runs" begin
        @test KeemenaPreprocessing._Cleaning.squeeze_char_runs("hello") == "hello"
        @test KeemenaPreprocessing._Cleaning.squeeze_char_runs("hellooo") == "hellooo"
        @test KeemenaPreprocessing._Cleaning.squeeze_char_runs("helloooo") == "hellooo"
        @test KeemenaPreprocessing._Cleaning.squeeze_char_runs("helloooooo") == "hellooo"
        @test KeemenaPreprocessing._Cleaning.squeeze_char_runs("aaaaaa") == "aaa"
        @test KeemenaPreprocessing._Cleaning.squeeze_char_runs("aaaaaa"; max_run=2) == "aa"
        @test KeemenaPreprocessing._Cleaning.squeeze_char_runs("aaaaaa"; max_run=1) == "a"
        @test KeemenaPreprocessing._Cleaning.squeeze_char_runs("") == ""
        @test KeemenaPreprocessing._Cleaning.squeeze_char_runs("abc") == "abc"
    end
    
    @testset "normalize_confusables" begin
        @test KeemenaPreprocessing._Cleaning.normalize_confusables("hello") == "hello"
        @test KeemenaPreprocessing._Cleaning.normalize_confusables("Αlpha") == "Alpha"  # Greek Alpha to Latin A
        @test KeemenaPreprocessing._Cleaning.normalize_confusables("Βeta") == "Beta"    # Greek Beta to Latin B
        @test KeemenaPreprocessing._Cleaning.normalize_confusables("аpple") == "apple"  # Cyrillic a to Latin a
        @test KeemenaPreprocessing._Cleaning.normalize_confusables("") == ""
    end

end
    
    # @testset "Main Cleaning Functions" begin
        
    #     @testset "replace_urls_emails" begin
    #         # Basic URL replacement
    #         @test _Cleaning.replace_urls_emails("Visit https://example.com") == "Visit <URL>"
    #         @test _Cleaning.replace_urls_emails("Visit http://example.com") == "Visit <URL>"
    #         @test _Cleaning.replace_urls_emails("Visit example.com") == "Visit <URL>"
    #         @test _Cleaning.replace_urls_emails("Visit www.example.com") == "Visit <URL>"
            
    #         # URL with path
    #         @test _Cleaning.replace_urls_emails("Visit https://example.com/path/to/page") == "Visit <URL>"
    #         @test _Cleaning.replace_urls_emails("Visit example.com/path") == "Visit <URL>"
            
    #         # Email replacement
    #         @test _Cleaning.replace_urls_emails("Contact user@example.com") == "Contact <EMAIL>"
    #         @test _Cleaning.replace_urls_emails("Email test.user+tag@domain.co.uk") == "Email <EMAIL>"
            
    #         # Both URLs and emails
    #         @test _Cleaning.replace_urls_emails("Visit https://example.com or email user@example.com") == "Visit <URL> or email <EMAIL>"
            
    #         # Custom sentinels
    #         @test _Cleaning.replace_urls_emails("Visit https://example.com"; url_sentinel="[LINK]") == "Visit [LINK]"
    #         @test _Cleaning.replace_urls_emails("Email user@example.com"; mail_sentinel="[MAIL]") == "Email [MAIL]"
            
    #         # Keep scheme
    #         @test _Cleaning.replace_urls_emails("Visit https://example.com"; keep_scheme=true) == "Visit https://<URL>"
    #         @test _Cleaning.replace_urls_emails("Visit http://example.com"; keep_scheme=true) == "Visit http://<URL>"
    #         @test _Cleaning.replace_urls_emails("Visit example.com"; keep_scheme=true) == "Visit <URL>"
            
    #         # No URLs or emails
    #         @test _Cleaning.replace_urls_emails("Hello world") == "Hello world"
    #         @test _Cleaning.replace_urls_emails("") == ""
    #     end
        
    #     @testset "replace_numbers" begin
    #         # Basic number replacement
    #         @test _Cleaning.replace_numbers("I have 5 apples") == "I have <NUM> apples"
    #         @test _Cleaning.replace_numbers("The year is 2023") == "The year is <NUM>"
    #         @test _Cleaning.replace_numbers("Price: 19.99") == "Price: <NUM>"
            
    #         # Multiple numbers
    #         @test _Cleaning.replace_numbers("I have 5 apples and 3 oranges") == "I have <NUM> apples and <NUM> oranges"
            
    #         # Numbers with signs
    #         @test _Cleaning.replace_numbers("Temperature: -5 degrees") == "Temperature: <NUM> degrees"
    #         @test _Cleaning.replace_numbers("Profit: +100 dollars") == "Profit: <NUM> dollars"
            
    #         # Keep decimal
    #         @test _Cleaning.replace_numbers("Price: 19.99"; keep_decimal=true) == "Price: <NUM>.99"
    #         @test _Cleaning.replace_numbers("Value: 123.456"; keep_decimal=true) == "Value: <NUM>.456"
            
    #         # Keep sign
    #         @test _Cleaning.replace_numbers("Temperature: -5"; keep_sign=true) == "Temperature: -<NUM>"
    #         @test _Cleaning.replace_numbers("Profit: +100"; keep_sign=true) == "Profit: +<NUM>"
            
    #         # Keep both sign and decimal
    #         @test _Cleaning.replace_numbers("Value: -123.45"; keep_sign=true, keep_decimal=true) == "Value: -<NUM>.45"
            
    #         # Custom sentinel
    #         @test _Cleaning.replace_numbers("I have 5 apples"; sentinel="[NUMBER]") == "I have [NUMBER] apples"
            
    #         # Numbers with commas (thousands separators)
    #         @test _Cleaning.replace_numbers("Population: 1,234,567") == "Population: <NUM>"
    #         @test _Cleaning.replace_numbers("Population: 1,234,567"; keep_commas=true) == "Population: <NUM>"
            
    #         # No numbers
    #         @test _Cleaning.replace_numbers("Hello world") == "Hello world"
    #         @test _Cleaning.replace_numbers("") == ""
    #     end
        
    #     @testset "strip_html" begin
    #         # Basic tag removal
    #         @test _Cleaning.strip_html("<p>Hello world</p>") == "Hello world"
    #         @test _Cleaning.strip_html("<div>Hello <span>world</span></div>") == "Hello world"
    #         @test _Cleaning.strip_html("<h1>Title</h1><p>Content</p>") == "TitleContent"
            
    #         # Self-closing tags
    #         @test _Cleaning.strip_html("Line 1<br/>Line 2") == "Line 1Line 2"
    #         @test _Cleaning.strip_html("Image: <img src='test.jpg' alt='test'/>") == "Image: "
            
    #         # Tags with attributes
    #         @test _Cleaning.strip_html("<div class='container' id='main'>Content</div>") == "Content"
    #         @test _Cleaning.strip_html("<a href='http://example.com' target='_blank'>Link</a>") == "Link"
            
    #         # HTML entities (decode by default)
    #         @test _Cleaning.strip_html("Hello&nbsp;world") == "Hello\u00A0world"
    #         @test _Cleaning.strip_html("&lt;tag&gt;") == "<tag>"
    #         @test _Cleaning.strip_html("&amp;") == "&"
    #         @test _Cleaning.strip_html("&quot;hello&quot;") == "\"hello\""
    #         @test _Cleaning.strip_html("&#39;hello&#39;") == "'hello'"
            
    #         # Don't decode entities
    #         @test _Cleaning.strip_html("Hello&nbsp;world"; decode_entities=false) == "Hello&nbsp;world"
    #         @test _Cleaning.strip_html("&lt;tag&gt;"; decode_entities=false) == "&lt;tag&gt;"
            
    #         # Comments
    #         @test _Cleaning.strip_html("<!-- comment -->Hello") == "Hello"
    #         @test _Cleaning.strip_html("Hello<!-- comment -->world") == "Helloworld"
            
    #         # No HTML
    #         @test _Cleaning.strip_html("Hello world") == "Hello world"
    #         @test _Cleaning.strip_html("") == ""
    #     end
        
    #     @testset "strip_markdown" begin
    #         # Links
    #         @test _Cleaning.strip_markdown("[Google](https://google.com)") == "Google"
    #         @test _Cleaning.strip_markdown("Visit [Google](https://google.com) for search") == "Visit Google for search"
            
    #         # Images
    #         @test _Cleaning.strip_markdown("![Alt text](image.jpg)") == "Alt text"
    #         @test _Cleaning.strip_markdown("![](image.jpg)") == ""
    #         @test _Cleaning.strip_markdown("See ![diagram](chart.png) above") == "See diagram above"
            
    #         # Bold and italic
    #         @test _Cleaning.strip_markdown("**bold text**") == "bold text"
    #         @test _Cleaning.strip_markdown("__bold text__") == "bold text"
    #         @test _Cleaning.strip_markdown("*italic text*") == "italic text"
    #         @test _Cleaning.strip_markdown("_italic text_") == "italic text"
    #         @test _Cleaning.strip_markdown("***bold italic***") == "bold italic"
            
    #         # Headings
    #         @test _Cleaning.strip_markdown("# Heading 1") == "Heading 1"
    #         @test _Cleaning.strip_markdown("## Heading 2") == "Heading 2"
    #         @test _Cleaning.strip_markdown("### Heading 3") == "Heading 3"
            
    #         # Code blocks (preserve by default)
    #         @test _Cleaning.strip_markdown("```julia\ncode here\n```") == "<CODE>"
    #         @test _Cleaning.strip_markdown("`inline code`") == "<CODE>"
    #         @test _Cleaning.strip_markdown("Text with `code` inside") == "Text with <CODE> inside"
            
    #         # Code blocks (don't preserve)
    #         @test _Cleaning.strip_markdown("```julia\ncode here\n```"; preserve_code=false) == ""
    #         @test _Cleaning.strip_markdown("`inline code`"; preserve_code=false) == ""
    #         @test _Cleaning.strip_markdown("Text with `code` inside"; preserve_code=false) == "Text with  inside"
            
    #         # Custom code sentinel
    #         @test _Cleaning.strip_markdown("`code`"; code_sentinel="[CODE_BLOCK]") == "[CODE_BLOCK]"
            
    #         # Blockquotes
    #         @test _Cleaning.strip_markdown("> This is a quote") == "This is a quote"
    #         @test _Cleaning.strip_markdown(">> Nested quote") == "Nested quote"
            
    #         # Lists
    #         @test _Cleaning.strip_markdown("- Item 1") == "Item 1"
    #         @test _Cleaning.strip_markdown("* Item 2") == "Item 2"
    #         @test _Cleaning.strip_markdown("+ Item 3") == "Item 3"
            
    #         # Horizontal rules
    #         @test _Cleaning.strip_markdown("---") == ""
    #         @test _Cleaning.strip_markdown("***") == ""
    #         @test _Cleaning.strip_markdown("___") == ""
            
    #         # Complex example
    #         markdown_text = """
    #         # Title
            
    #         This is **bold** and *italic* text.
            
    #         Visit [Google](https://google.com) for more info.
            
    #         ```python
    #         print("Hello")
    #         ```
            
    #         - List item 1
    #         - List item 2
            
    #         > Quote here
    #         """
            
    #         expected = """
    #         Title
            
    #         This is bold and italic text.
            
    #         Visit Google for more info.
            
    #         <CODE>
            
    #         List item 1
    #         List item 2
            
    #         Quote here
    #         """
            
    #         @test strip(_Cleaning.strip_markdown(markdown_text)) == strip(expected)
            
    #         # No markdown
    #         @test _Cleaning.strip_markdown("Hello world") == "Hello world"
    #         @test _Cleaning.strip_markdown("") == ""
    #     end
    # end
    
    # @testset "Integration Tests - clean_documents" begin
        
    #     @testset "Default Configuration" begin
    #         cfg = KeemenaPreprocessing.PreprocessConfiguration()
            
    #         # Basic cleaning with default settings
    #         docs = ["Hello World!", "  CAFÉ  ", "Visit https://example.com"]
    #         result = clean_documents(docs, cfg)
            
    #         @test result[1] == "hello world"  # lowercase, remove punctuation
    #         @test result[2] == "cafe"         # lowercase, strip accents, trim
    #         @test result[3] == "visit <url>"  # lowercase, replace URLs
            
    #         # Empty documents
    #         @test clean_documents(String[], cfg) == String[]
    #         @test clean_documents([""], cfg) == [""]
            
    #         # Single document
    #         @test clean_documents(["Hello World!"], cfg) == ["hello world"]
    #     end
        
    #     @testset "Custom Configurations" begin
            
    #         # Configuration with numbers enabled
    #         cfg_numbers = KeemenaPreprocessing.PreprocessConfiguration(
    #             replace_numbers=true,
    #             number_sentinel="<NUM>",
    #             lowercase=false,
    #             remove_punctuation=false
    #         )
            
    #         docs = ["I have 5 apples and 10 oranges."]
    #         result = clean_documents(docs, cfg_numbers)
    #         @test result[1] == "I have <NUM> apples and <NUM> oranges."
            
    #         # Configuration with HTML stripping
    #         cfg_html = KeemenaPreprocessing.PreprocessConfiguration(
    #             strip_html_tags=true,
    #             html_entity_decode=true,
    #             lowercase=false,
    #             remove_punctuation=false
    #         )
            
    #         docs = ["<p>Hello&nbsp;<strong>world</strong>!</p>"]
    #         result = clean_documents(docs, cfg_html)
    #         @test result[1] == "Hello\u00A0world!"
            
    #         # Configuration with Markdown stripping
    #         cfg_md = KeemenaPreprocessing.PreprocessConfiguration(
    #             strip_markdown=true,
    #             preserve_md_code=true,
    #             lowercase=false,
    #             remove_punctuation=false
    #         )
            
    #         docs = ["# Title\n\nThis is **bold** text with `code`."]
    #         result = clean_documents(docs, cfg_md)
    #         @test result[1] == "Title\n\nThis is bold text with <CODE>."
            
    #         # Configuration with emoji handling
    #         cfg_emoji_remove = KeemenaPreprocessing.PreprocessConfiguration(
    #             emoji_handling=:remove,
    #             lowercase=false,
    #             remove_punctuation=false
    #         )
            
    #         cfg_emoji_sentinel = KeemenaPreprocessing.PreprocessConfiguration(
    #             emoji_handling=:sentinel,
    #             emoji_sentinel="<EMOJI>",
    #             lowercase=false,
    #             remove_punctuation=false
    #         )
            
    #         docs = ["Hello 😀 world 🌍!"]
    #         result_remove = clean_documents(docs, cfg_emoji_remove)
    #         result_sentinel = clean_documents(docs, cfg_emoji_sentinel)
            
    #         @test result_remove[1] == "Hello  world !"
    #         @test result_sentinel[1] == "Hello <EMOJI> world <EMOJI>!"
            
    #         # Configuration with character run squeezing
    #         cfg_squeeze = KeemenaPreprocessing.PreprocessConfiguration(
    #             squeeze_repeat_chars=true,
    #             max_char_run=2,
    #             lowercase=false,
    #             remove_punctuation=false
    #         )
            
    #         docs = ["Helloooooo woooorld!!!"]
    #         result = clean_documents(docs, cfg_squeeze)
    #         @test result[1] == "Helloo woorld!!"
            
    #         # Configuration with confusables mapping
    #         cfg_confusables = KeemenaPreprocessing.PreprocessConfiguration(
    #             map_confusables=true,
    #             lowercase=false,
    #             remove_punctuation=false
    #         )
            
    #         docs = ["Αpple with Cyrillic а"]
    #         result = clean_documents(docs, cfg_confusables)
    #         @test result[1] == "Apple with Cyrillic a"
            
    #         # Configuration with Unicode punctuation mapping
    #         cfg_unicode_punct = KeemenaPreprocessing.PreprocessConfiguration(
    #             map_unicode_punctuation=true,
    #             lowercase=false,
    #             remove_punctuation=false
    #         )
            
    #         docs = ["\"Hello\" and 'world' — with em-dash…"]
    #         result = clean_documents(docs, cfg_unicode_punct)
    #         @test result[1] == "\"Hello\" and 'world' - with em-dash..."
    #     end
        
    #     @testset "Complex Integration Tests" begin
            
    #         # Test with all cleaning features enabled
    #         cfg_all = KeemenaPreprocessing.PreprocessConfiguration(
    #             lowercase=true,
    #             strip_accents=true,
    #             remove_control_characters=true,
    #             remove_punctuation=true,
    #             normalise_whitespace=true,
    #             remove_zero_width_chars=true,
    #             preserve_newlines=false,
    #             collapse_spaces=true,
    #             trim_edges=true,
    #             replace_urls=true,
    #             replace_emails=true,
    #             replace_numbers=true,
    #             strip_html_tags=true,
    #             strip_markdown=true,
    #             emoji_handling=:sentinel,
    #             squeeze_repeat_chars=true,
    #             map_confusables=true,
    #             map_unicode_punctuation=true,
    #             unicode_normalisation_form=:NFC
    #         )
            
    #         complex_doc = """
    #         # Héllo Wörld! 😀
            
    #         Visit [Google](https://google.com) or email test@example.com.
            
    #         <p>Price: \$19.99 for 5 items.</p>
            
    #         ```python
    #         print("Hello")
    #         ```
            
    #         Helloooo woooorld!!!
            
    #         "Smart quotes" and em—dash…
    #         """
            
    #         result = clean_documents([complex_doc], cfg_all)
    #         cleaned = result[1]
            
    #         # Check that various transformations occurred
    #         @test occursin("hello world", cleaned)
    #         @test occursin("<url>", cleaned)
    #         @test occursin("<email>", cleaned)
    #         @test occursin("<num>", cleaned)
    #         @test occursin("<emoji>", cleaned)
    #         @test occursin("<code>", cleaned)
    #         @test !occursin("héllo", lowercase(cleaned))
    #         @test !occursin("\$", cleaned)
    #         @test !occursin("```", cleaned)
    #         @test !occursin("<p>", cleaned)
    #         @test !occursin("#", cleaned)
    #     end
        
    #     @testset "Whitespace and Newline Handling" begin
            
    #         # Preserve newlines
    #         cfg_preserve_nl = KeemenaPreprocessing.PreprocessConfiguration(
    #             preserve_newlines=true,
    #             normalise_whitespace=true,
    #             lowercase=false,
    #             remove_punctuation=false
    #         )
            
    #         docs = ["Line 1\n\nLine 2\n   Line 3   "]
    #         result = clean_documents(docs, cfg_preserve_nl)
    #         @test result[1] == "Line 1\n\nLine 2\nLine 3"
            
    #         # Don't preserve newlines
    #         cfg_no_nl = KeemenaPreprocessing.PreprocessConfiguration(
    #             preserve_newlines=false,
    #             normalise_whitespace=true,
    #             lowercase=false,
    #             remove_punctuation=false
    #         )
            
    #         result = clean_documents(docs, cfg_no_nl)
    #         @test result[1] == "Line 1 Line 2 Line 3"
            
    #         # Zero-width character removal
    #         cfg_zero_width = KeemenaPreprocessing.PreprocessConfiguration(
    #             remove_zero_width_chars=true,
    #             normalise_whitespace=true,
    #             lowercase=false,
    #             remove_punctuation=false
    #         )
            
    #         docs = ["Hello\u200B\u200C\u200D\uFEFFworld"]
    #         result = clean_documents(docs, cfg_zero_width)
    #         @test result[1] == "Hello world"
    #     end
        
    #     @testset "Edge Cases and Error Handling" begin
    #         cfg = KeemenaPreprocessing.PreprocessConfiguration()
            
    #         # Very long documents
    #         long_doc = "word " ^ 1000  # 1000 repetitions
    #         result = clean_documents([long_doc], cfg)
    #         @test length(result) == 1
    #         @test occursin("word", result[1])
            
    #         # Documents with only whitespace
    #         whitespace_docs = ["   ", "\t\n\r", ""]
    #         result = clean_documents(whitespace_docs, cfg)
    #         @test all(isempty, result)
            
    #         # Documents with only punctuation
    #         punct_docs = ["!!!", "???", "..."]
    #         result = clean_documents(punct_docs, cfg)
    #         @test all(isempty, result)
            
    #         # Mixed content types
    #         mixed_docs = [
    #             "Normal text",
    #             "<html>HTML content</html>",
    #             "# Markdown content",
    #             "Text with 123 numbers",
    #             "Email: user@example.com",
    #             "URL: https://example.com",
    #             "😀 Emoji content 🌍"
    #         ]
            
    #         result = clean_documents(mixed_docs, cfg)
    #         @test length(result) == length(mixed_docs)
    #         @test all(s -> isa(s, String), result)
    #     end
        
    #     @testset "Unicode Normalization Forms" begin
    #         # Test different Unicode normalization forms
    #         accented_text = "café"  # é as single character
    #         decomposed_text = "cafe\u0301"  # e + combining acute accent
            
    #         cfg_nfc = KeemenaPreprocessing.PreprocessConfiguration(
    #             unicode_normalisation_form=:NFC,
    #             strip_accents=false,
    #             lowercase=false,
    #             remove_punctuation=false
    #         )
            
    #         cfg_nfd = KeemenaPreprocessing.PreprocessConfiguration(
    #             unicode_normalisation_form=:NFD,
    #             strip_accents=false,
    #             lowercase=false,
    #             remove_punctuation=false
    #         )
            
    #         cfg_none = KeemenaPreprocessing.PreprocessConfiguration(
    #             unicode_normalisation_form=:none,
    #             strip_accents=false,
    #             lowercase=false,
    #             remove_punctuation=false
    #         )
            
    #         result_nfc = clean_documents([decomposed_text], cfg_nfc)
    #         result_nfd = clean_documents([accented_text], cfg_nfd)
    #         result_none = clean_documents([accented_text], cfg_none)
            
    #         @test result_nfc[1] == accented_text  # Should normalize to composed form
    #         @test result_nfd[1] == decomposed_text  # Should normalize to decomposed form
    #         @test result_none[1] == accented_text  # Should remain unchanged
    #     end
    # end


