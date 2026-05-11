// Port of lib/css/tokenizer.rb (CSS Syntax Module Level 3/4 §4).
// Position tracking is intentionally omitted in this first cut — only
// type/value/flag/unit parity with the pure-Ruby Token is targeted.

const REPLACEMENT: char = '\u{FFFD}';

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    Ident, Function, AtKeyword, Hash, String_, BadString, Url, BadUrl,
    Delim, Number, Percentage, Dimension, Whitespace, Cdo, Cdc, Comment,
    Colon, Semicolon, Comma,
    LBracket, RBracket, LParen, RParen, LBrace, RBrace,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum HashFlag { Id, Unrestricted }

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NumberFlag { Integer, Number }

#[derive(Clone, Debug)]
pub enum TokenValue {
    None,
    Str(String),
    Delim(char),
    Int(i64),
    Float(f64),
}

#[derive(Clone, Debug)]
pub struct Token {
    pub kind:        Kind,
    pub value:       TokenValue,
    pub number_flag: Option<NumberFlag>,
    pub hash_flag:   Option<HashFlag>,
    pub unit:        Option<String>,
}

impl Token {
    fn bare(kind: Kind) -> Self {
        Self { kind, value: TokenValue::None, number_flag: None, hash_flag: None, unit: None }
    }

    fn delim(c: char) -> Self {
        Self { value: TokenValue::Delim(c), ..Self::bare(Kind::Delim) }
    }

    fn with_str(kind: Kind, s: String) -> Self {
        Self { value: TokenValue::Str(s), ..Self::bare(kind) }
    }
}

pub struct Tokenizer {
    chars:             Vec<char>,
    pos:               usize,
    preserve_comments: bool,
}

impl Tokenizer {
    pub fn new(input: &str, preserve_comments: bool) -> Self {
        Self {
            chars:             preprocess(input),
            pos:               0,
            preserve_comments,
        }
    }

    pub fn tokenize(&mut self) -> Vec<Token> {
        let mut out = Vec::new();

        loop {
            if !self.preserve_comments {
                self.consume_comments();
            }

            if self.eof() {
                break;
            }

            out.push(self.consume_one_token());
        }

        out
    }

    // --- cursor primitives -----------------------------------------

    fn peek(&self, offset: usize) -> Option<char> {
        self.chars.get(self.pos + offset).copied()
    }

    fn consume(&mut self) -> Option<char> {
        let c = self.chars.get(self.pos).copied();

        if c.is_some() {
            self.pos += 1;
        }

        c
    }

    fn reconsume(&mut self) {
        self.pos -= 1;
    }

    fn eof(&self) -> bool {
        self.pos >= self.chars.len()
    }

    // --- main dispatch ---------------------------------------------

    fn consume_one_token(&mut self) -> Token {
        if self.peek(0) == Some('/') && self.peek(1) == Some('*') {
            return self.consume_comment_token();
        }

        let c = self.consume().expect("eof handled by caller");

        if is_whitespace(c) {
            return self.consume_whitespace();
        }

        if c == '"' || c == '\'' {
            return self.consume_string_token(c);
        }

        if (c == '+' || c == '-' || c == '.') && number_starts(Some(c), self.peek(0), self.peek(1)) {
            self.reconsume();
            return self.consume_numeric_token();
        }

        if let Some(kind) = punctuation_kind(c) {
            return Token::bare(kind);
        }

        match c {
            '#' => {
                if is_ident_code_point(self.peek(0)) || valid_escape(self.peek(0), self.peek(1)) {
                    let flag = if ident_sequence_starts(self.peek(0), self.peek(1), self.peek(2)) {
                        HashFlag::Id
                    } else {
                        HashFlag::Unrestricted
                    };

                    let name = self.consume_ident_sequence();

                    Token {
                        hash_flag: Some(flag),
                        ..Token::with_str(Kind::Hash, name)
                    }
                } else {
                    Token::delim(c)
                }
            }
            '+' | '.' => Token::delim(c),
            '-' => {
                if self.peek(0) == Some('-') && self.peek(1) == Some('>') {
                    self.consume();
                    self.consume();
                    Token::bare(Kind::Cdc)
                } else if ident_sequence_starts(Some(c), self.peek(0), self.peek(1)) {
                    self.reconsume();
                    self.consume_ident_like_token()
                } else {
                    Token::delim(c)
                }
            }
            '<' => {
                if self.peek(0) == Some('!') && self.peek(1) == Some('-') && self.peek(2) == Some('-') {
                    self.consume();
                    self.consume();
                    self.consume();
                    Token::bare(Kind::Cdo)
                } else {
                    Token::delim(c)
                }
            }
            '@' => {
                if ident_sequence_starts(self.peek(0), self.peek(1), self.peek(2)) {
                    Token::with_str(Kind::AtKeyword, self.consume_ident_sequence())
                } else {
                    Token::delim(c)
                }
            }
            '\\' => {
                if valid_escape(Some(c), self.peek(0)) {
                    self.reconsume();
                    self.consume_ident_like_token()
                } else {
                    Token::delim(c)
                }
            }
            '0'..='9' => {
                self.reconsume();
                self.consume_numeric_token()
            }
            _ => {
                if is_ident_start_code_point(Some(c)) {
                    self.reconsume();
                    self.consume_ident_like_token()
                } else {
                    Token::delim(c)
                }
            }
        }
    }

    // --- comments --------------------------------------------------

    fn consume_comments(&mut self) {
        while self.peek(0) == Some('/') && self.peek(1) == Some('*') {
            self.consume();
            self.consume();

            while !self.eof() {
                if self.consume() == Some('*') && self.peek(0) == Some('/') {
                    self.consume();
                    break;
                }
            }
        }
    }

    fn consume_comment_token(&mut self) -> Token {
        self.consume();
        self.consume();
        let mut buf = String::new();

        while !self.eof() {
            let c = self.consume().unwrap();

            if c == '*' && self.peek(0) == Some('/') {
                self.consume();
                break;
            }

            buf.push(c);
        }

        Token::with_str(Kind::Comment, buf)
    }

    fn consume_whitespace(&mut self) -> Token {
        while is_whitespace_opt(self.peek(0)) {
            self.consume();
        }

        Token::bare(Kind::Whitespace)
    }

    // --- strings ---------------------------------------------------

    fn consume_string_token(&mut self, ending: char) -> Token {
        let mut buf = String::new();

        loop {
            match self.consume() {
                None => return Token::with_str(Kind::String_, buf),
                Some(c) if c == ending => return Token::with_str(Kind::String_, buf),
                Some('\n') => {
                    self.reconsume();
                    return Token::bare(Kind::BadString);
                }
                Some('\\') => {
                    let n = self.peek(0);

                    if n.is_none() {
                        continue;
                    } else if n == Some('\n') {
                        self.consume();
                    } else {
                        buf.push(self.consume_escaped_code_point());
                    }
                }
                Some(c) => buf.push(c),
            }
        }
    }

    // --- escape ----------------------------------------------------

    fn consume_escaped_code_point(&mut self) -> char {
        let c = match self.consume() {
            None    => return REPLACEMENT,
            Some(c) => c,
        };

        if !is_hex_digit(Some(c)) {
            return c;
        }

        let mut hex = String::with_capacity(6);
        hex.push(c);

        while hex.len() < 6 && is_hex_digit(self.peek(0)) {
            hex.push(self.consume().unwrap());
        }

        if is_whitespace_opt(self.peek(0)) {
            self.consume();
        }

        let n = u32::from_str_radix(&hex, 16).unwrap_or(0);

        if n == 0 || (0xD800..=0xDFFF).contains(&n) || n > 0x10FFFF {
            REPLACEMENT
        } else {
            char::from_u32(n).unwrap_or(REPLACEMENT)
        }
    }

    // --- ident-like ------------------------------------------------

    fn consume_ident_sequence(&mut self) -> String {
        let mut buf = String::new();

        loop {
            let c = self.consume();

            if is_ident_code_point(c) {
                buf.push(c.unwrap());
            } else if valid_escape(c, self.peek(0)) {
                buf.push(self.consume_escaped_code_point());
            } else {
                if c.is_some() {
                    self.reconsume();
                }
                return buf;
            }
        }
    }

    fn consume_ident_like_token(&mut self) -> Token {
        let name = self.consume_ident_sequence();

        if name.eq_ignore_ascii_case("url") && self.peek(0) == Some('(') {
            self.consume();

            while is_whitespace_opt(self.peek(0)) && is_whitespace_opt(self.peek(1)) {
                self.consume();
            }

            let n1 = self.peek(0);
            let n2 = if is_whitespace_opt(n1) { self.peek(1) } else { n1 };

            let is_quote = |c: Option<char>| c == Some('"') || c == Some('\'');

            if is_quote(n1) || (is_whitespace_opt(n1) && is_quote(n2)) {
                Token::with_str(Kind::Function, name)
            } else {
                self.consume_url_token()
            }
        } else if self.peek(0) == Some('(') {
            self.consume();
            Token::with_str(Kind::Function, name)
        } else {
            Token::with_str(Kind::Ident, name)
        }
    }

    fn consume_url_token(&mut self) -> Token {
        let mut buf = String::new();

        while is_whitespace_opt(self.peek(0)) {
            self.consume();
        }

        loop {
            let c = self.consume();

            match c {
                None | Some(')') => return Token::with_str(Kind::Url, buf),
                Some('"') | Some('\'') | Some('(') => {
                    self.consume_bad_url_remnants();
                    return Token::bare(Kind::BadUrl);
                }
                Some(' ') | Some('\t') | Some('\n') => {
                    while is_whitespace_opt(self.peek(0)) {
                        self.consume();
                    }

                    let n = self.peek(0);

                    if n.is_none() || n == Some(')') {
                        if n.is_some() {
                            self.consume();
                        }
                        return Token::with_str(Kind::Url, buf);
                    } else {
                        self.consume_bad_url_remnants();
                        return Token::bare(Kind::BadUrl);
                    }
                }
                Some('\\') => {
                    if valid_escape(c, self.peek(0)) {
                        buf.push(self.consume_escaped_code_point());
                    } else {
                        self.consume_bad_url_remnants();
                        return Token::bare(Kind::BadUrl);
                    }
                }
                Some(c) => {
                    if is_non_printable(c) {
                        self.consume_bad_url_remnants();
                        return Token::bare(Kind::BadUrl);
                    }
                    buf.push(c);
                }
            }
        }
    }

    fn consume_bad_url_remnants(&mut self) {
        loop {
            let c = self.consume();

            if c.is_none() || c == Some(')') {
                return;
            }

            if valid_escape(c, self.peek(0)) {
                self.consume_escaped_code_point();
            }
        }
    }

    // --- numbers ---------------------------------------------------

    fn consume_numeric_token(&mut self) -> Token {
        let (value, flag) = self.consume_number();

        if ident_sequence_starts(self.peek(0), self.peek(1), self.peek(2)) {
            let unit = self.consume_ident_sequence();

            Token {
                number_flag: Some(flag),
                unit:        Some(unit),
                ..Self::with_number_value(Kind::Dimension, value, flag)
            }
        } else if self.peek(0) == Some('%') {
            self.consume();
            Self::with_number_value(Kind::Percentage, value, flag)
        } else {
            Token {
                number_flag: Some(flag),
                ..Self::with_number_value(Kind::Number, value, flag)
            }
        }
    }

    fn with_number_value(kind: Kind, value: TokenValue, _flag: NumberFlag) -> Token {
        Token { value, ..Token::bare(kind) }
    }

    fn consume_number(&mut self) -> (TokenValue, NumberFlag) {
        let mut repr = String::new();
        let mut flag = NumberFlag::Integer;

        if self.peek(0) == Some('+') || self.peek(0) == Some('-') {
            repr.push(self.consume().unwrap());
        }

        while is_digit(self.peek(0)) {
            repr.push(self.consume().unwrap());
        }

        if self.peek(0) == Some('.') && is_digit(self.peek(1)) {
            repr.push(self.consume().unwrap());
            while is_digit(self.peek(0)) {
                repr.push(self.consume().unwrap());
            }
            flag = NumberFlag::Number;
        }

        let exp = self.peek(0);
        let after_exp = self.peek(1);

        if (exp == Some('E') || exp == Some('e'))
            && (is_digit(after_exp)
                || ((after_exp == Some('+') || after_exp == Some('-')) && is_digit(self.peek(2))))
        {
            repr.push(self.consume().unwrap());
            if self.peek(0) == Some('+') || self.peek(0) == Some('-') {
                repr.push(self.consume().unwrap());
            }
            while is_digit(self.peek(0)) {
                repr.push(self.consume().unwrap());
            }
            flag = NumberFlag::Number;
        }

        let value = match flag {
            NumberFlag::Integer => TokenValue::Int(repr.parse().unwrap_or(0)),
            NumberFlag::Number  => TokenValue::Float(repr.parse().unwrap_or(0.0)),
        };

        (value, flag)
    }
}

// --- preprocessing ----------------------------------------------

fn preprocess(input: &str) -> Vec<char> {
    let mut out  = Vec::with_capacity(input.len());
    let mut iter = input.chars().peekable();

    while let Some(c) = iter.next() {
        match c {
            '\r' => {
                out.push('\n');
                if iter.peek() == Some(&'\n') {
                    iter.next();
                }
            }
            '\x0C' => out.push('\n'),
            '\0'   => out.push(REPLACEMENT),
            _      => out.push(c),
        }
    }

    out
}

// --- code point classifiers -------------------------------------

fn is_whitespace(c: char) -> bool {
    c == ' ' || c == '\n' || c == '\t'
}

fn is_whitespace_opt(c: Option<char>) -> bool {
    matches!(c, Some(' ') | Some('\n') | Some('\t'))
}

fn is_digit(c: Option<char>) -> bool {
    matches!(c, Some('0'..='9'))
}

fn is_hex_digit(c: Option<char>) -> bool {
    matches!(c, Some('0'..='9' | 'A'..='F' | 'a'..='f'))
}

fn is_ident_start_code_point(c: Option<char>) -> bool {
    match c {
        Some(c) if c.is_ascii_alphabetic() => true,
        Some('_') => true,
        Some(c) if (c as u32) >= 0x80 => true,
        _ => false,
    }
}

fn is_ident_code_point(c: Option<char>) -> bool {
    is_ident_start_code_point(c) || is_digit(c) || c == Some('-')
}

fn is_non_printable(c: char) -> bool {
    let o = c as u32;
    o <= 0x08 || o == 0x0B || (0x0E..=0x1F).contains(&o) || o == 0x7F
}

// §4.3.8
fn valid_escape(c1: Option<char>, c2: Option<char>) -> bool {
    c1 == Some('\\') && c2.is_some() && c2 != Some('\n')
}

// §4.3.9
fn ident_sequence_starts(c1: Option<char>, c2: Option<char>, c3: Option<char>) -> bool {
    match c1 {
        Some('-')  => is_ident_start_code_point(c2) || c2 == Some('-') || valid_escape(c2, c3),
        Some('\\') => valid_escape(c1, c2),
        _          => is_ident_start_code_point(c1),
    }
}

// §4.3.10
fn number_starts(c1: Option<char>, c2: Option<char>, c3: Option<char>) -> bool {
    match c1 {
        Some('+') | Some('-') => is_digit(c2) || (c2 == Some('.') && is_digit(c3)),
        Some('.')             => is_digit(c2),
        _                     => is_digit(c1),
    }
}

fn punctuation_kind(c: char) -> Option<Kind> {
    Some(match c {
        '(' => Kind::LParen,
        ')' => Kind::RParen,
        ',' => Kind::Comma,
        ':' => Kind::Colon,
        ';' => Kind::Semicolon,
        '[' => Kind::LBracket,
        ']' => Kind::RBracket,
        '{' => Kind::LBrace,
        '}' => Kind::RBrace,
        _   => return None,
    })
}
