module CSS
  # Tokenizer based on CSS Syntax Module Level 3/4 §4.
  # https://www.w3.org/TR/css-syntax-3/#tokenization
  #
  # Not thread-safe: an instance carries a mutable cursor (`@pos`) that
  # advances over the input. Allocate one tokenizer per thread.
  class Tokenizer
    include CodePoints

    PUNCTUATION = {
      '(' => :lparen,
      ')' => :rparen,
      ',' => :comma,
      ':' => :colon,
      ';' => :semicolon,
      '[' => :lbracket,
      ']' => :rbracket,
      '{' => :lbrace,
      '}' => :rbrace
    }.freeze

    # CR / FF (and CR LF) collapse to LF; NUL collapses to U+FFFD. Done in
    # one pass.
    PREPROCESS_RE = /\r\n?|\f|\0/.freeze

    def initialize(input, preserve_comments: false)
      @chars             = preprocess(input)
      @pos               = 0
      @newlines          = collect_newline_offsets(@chars)
      @preserve_comments = preserve_comments
    end

    def tokenize
      tokens = []

      loop do
        token = next_token
        break if token.type == :eof

        tokens << token
      end

      tokens
    end

    def next_token
      consume_comments unless @preserve_comments

      return Token.new(:eof) if @pos >= @chars.length

      start_offset = @pos
      tok          = consume_one_token

      tok.assign_source!(start_offset, @pos, @newlines)
    end

    private

    def consume_one_token
      return consume_comment_token if peek == '/' && peek(1) == '*'

      c = consume

      return consume_whitespace      if whitespace?(c)
      return consume_string_token(c) if c == '"' || c == "'"

      if (c == '+' || c == '-' || c == '.') && number_starts?(c, peek, peek(1))
        reconsume
        return consume_numeric_token
      end

      if (type = PUNCTUATION[c])
        return Token.new(type)
      end

      case c
      when '#'
        if ident_code_point?(peek) || valid_escape?(peek, peek(1))
          flag = ident_sequence_starts?(peek, peek(1), peek(2)) ? :id : :unrestricted
          Token.new(:hash, consume_ident_sequence, flag:)
        else
          Token.new(:delim, c)
        end
      when '+', '.'
        Token.new(:delim, c)
      when '-'
        if peek == '-' && peek(1) == '>'
          consume
          consume
          Token.new(:cdc)
        elsif ident_sequence_starts?(c, peek, peek(1))
          reconsume
          consume_ident_like_token
        else
          Token.new(:delim, c)
        end
      when '<'
        if peek == '!' && peek(1) == '-' && peek(2) == '-'
          consume
          consume
          consume
          Token.new(:cdo)
        else
          Token.new(:delim, c)
        end
      when '@'
        if ident_sequence_starts?(peek, peek(1), peek(2))
          Token.new(:at_keyword, consume_ident_sequence)
        else
          Token.new(:delim, c)
        end
      when '\\'
        if valid_escape?(c, peek)
          reconsume
          consume_ident_like_token
        else
          Token.new(:delim, c)
        end
      when '0'..'9'
        reconsume
        consume_numeric_token
      else
        if ident_start_code_point?(c)
          reconsume
          consume_ident_like_token
        else
          Token.new(:delim, c)
        end
      end
    end

    # Random access on a non-ascii-only UTF-8 String is O(distance from
    # the cached character index), and the peek-ahead pattern (`peek`,
    # `peek(1)`, `peek(2)`) defeats the cache — empirically ~200× slower
    # than indexing a flat Array. Splitting into `chars` once amortizes
    # the UTF-8 walk and gives us O(1) random access for the rest of
    # tokenization.
    def preprocess(input)
      input
        .encode('UTF-8')
        .gsub(PREPROCESS_RE) { $~[0] == "\0" ? CodePoints::REPLACEMENT : "\n" }
        .chars
    end

    def peek(offset = 0)
      @chars[@pos + offset]
    end

    def consume
      c = @chars[@pos]
      return nil if c.nil?

      @pos += 1
      c
    end

    def reconsume
      @pos -= 1
    end

    def collect_newline_offsets(chars)
      offsets = []
      i       = 0
      n       = chars.length

      while i < n
        offsets << i if chars[i] == "\n"
        i += 1
      end

      offsets
    end

    def whitespace?(c)
      c == ' ' || c == "\n" || c == "\t"
    end

    def non_printable?(c)
      return false if c.nil?

      o = c.ord
      o <= 0x08 || o == 0x0B || (0x0E..0x1F).cover?(o) || o == 0x7F
    end

    # §4.3.8.
    def valid_escape?(c1, c2)
      c1 == '\\' && c2 != "\n" && !c2.nil?
    end

    # §4.3.9.
    def ident_sequence_starts?(c1, c2, c3)
      case c1
      when '-'
        ident_start_code_point?(c2) || c2 == '-' || valid_escape?(c2, c3)
      when '\\'
        valid_escape?(c1, c2)
      else
        ident_start_code_point?(c1)
      end
    end

    # §4.3.10.
    def number_starts?(c1, c2, c3)
      case c1
      when '+', '-'
        digit?(c2) || (c2 == '.' && digit?(c3))
      when '.'
        digit?(c2)
      else
        digit?(c1)
      end
    end

    # §4.3.2. Skips through `/* ... */` comments without producing tokens.
    def consume_comments
      while peek == '/' && peek(1) == '*'
        consume
        consume

        until eof?
          if consume == '*' && peek == '/'
            consume
            break
          end
        end
      end
    end

    # When `preserve_comments` is on, comments are emitted as tokens whose
    # value is the body between `/*` and `*/`.
    def consume_comment_token
      consume
      consume
      buf = +''

      until eof?
        c = consume
        if c == '*' && peek == '/'
          consume
          break
        end

        buf << c
      end

      Token.new(:comment, buf)
    end

    def eof?
      @pos >= @chars.length
    end

    def consume_whitespace
      consume while whitespace?(peek)

      Token.new(:whitespace)
    end

    # §4.3.5.
    def consume_string_token(ending)
      buf = +''

      loop do
        c = consume

        case c
        when nil, ending
          return Token.new(:string, buf)
        when "\n"
          reconsume
          return Token.new(:bad_string)
        when '\\'
          n = peek

          if n.nil?
            next
          elsif n == "\n"
            consume
          else
            buf << consume_escaped_code_point
          end
        else
          buf << c
        end
      end
    end

    # §4.3.7. Assumes the backslash has already been consumed.
    def consume_escaped_code_point
      c = consume

      return CodePoints::REPLACEMENT if c.nil?
      return c                       unless hex_digit?(c)

      hex = c.dup
      hex << consume while hex.length < 6 && hex_digit?(peek)
      consume if whitespace?(peek)

      n = hex.to_i(16)

      if n.zero? || (0xD800..0xDFFF).cover?(n) || n > 0x10FFFF
        CodePoints::REPLACEMENT
      else
        [n].pack('U')
      end
    end

    # §4.3.11.
    def consume_ident_sequence
      buf = +''

      loop do
        c = consume

        if ident_code_point?(c)
          buf << c
        elsif valid_escape?(c, peek)
          buf << consume_escaped_code_point
        else
          reconsume unless c.nil?
          return buf
        end
      end
    end

    # §4.3.4.
    def consume_ident_like_token
      name = consume_ident_sequence

      if name.casecmp('url').zero? && peek == '('
        consume

        consume while whitespace?(peek) && whitespace?(peek(1))

        n1 = peek
        n2 = whitespace?(n1) ? peek(1) : n1

        if n1 == '"' || n1 == "'" || (whitespace?(n1) && (n2 == '"' || n2 == "'"))
          Token.new(:function, name)
        else
          consume_url_token
        end
      elsif peek == '('
        consume
        Token.new(:function, name)
      else
        Token.new(:ident, name)
      end
    end

    # §4.3.6. Assumes "url(" has already been consumed.
    def consume_url_token
      buf = +''

      consume while whitespace?(peek)

      loop do
        c = consume

        case c
        when nil, ')'
          return Token.new(:url, buf)
        when '"', "'", '('
          consume_bad_url_remnants
          return Token.new(:bad_url)
        when ' ', "\t", "\n"
          consume while whitespace?(peek)

          n = peek

          if n.nil? || n == ')'
            consume unless n.nil?
            return Token.new(:url, buf)
          else
            consume_bad_url_remnants
            return Token.new(:bad_url)
          end
        when '\\'
          if valid_escape?(c, peek)
            buf << consume_escaped_code_point
          else
            consume_bad_url_remnants
            return Token.new(:bad_url)
          end
        else
          if non_printable?(c)
            consume_bad_url_remnants
            return Token.new(:bad_url)
          end

          buf << c
        end
      end
    end

    # §4.3.14.
    def consume_bad_url_remnants
      loop do
        c = consume

        return if c.nil? || c == ')'

        consume_escaped_code_point if valid_escape?(c, peek)
      end
    end

    # §4.3.3.
    def consume_numeric_token
      number, flag = consume_number

      if ident_sequence_starts?(peek, peek(1), peek(2))
        Token.new(:dimension, number, flag:, unit: consume_ident_sequence)
      elsif peek == '%'
        consume
        Token.new(:percentage, number)
      else
        Token.new(:number, number, flag:)
      end
    end

    # §4.3.12. Returns [numeric_value, :integer | :number].
    def consume_number
      repr = +''
      flag = :integer

      repr << consume if peek == '+' || peek == '-'
      repr << consume while digit?(peek)

      if peek == '.' && digit?(peek(1))
        repr << consume
        repr << consume while digit?(peek)
        flag = :number
      end

      if (peek == 'E' || peek == 'e') &&
          (digit?(peek(1)) || ((peek(1) == '+' || peek(1) == '-') && digit?(peek(2))))
        repr << consume
        repr << consume if peek == '+' || peek == '-'
        repr << consume while digit?(peek)
        flag = :number
      end

      [flag == :integer ? repr.to_i : repr.to_f, flag]
    end
  end
end
