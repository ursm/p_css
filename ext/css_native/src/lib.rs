mod matcher;
mod selectors;
mod snapshot;
mod tokenizer;

use magnus::{
    function, kwargs, prelude::*, value::ReprValue, Error, RArray, RClass, Ruby, Value,
};
use tokenizer::{HashFlag, Kind, NumberFlag, Token, TokenValue, Tokenizer};

fn hello() -> &'static str {
    "hello from rust"
}

fn tokenize(ruby: &Ruby, input: String, preserve_comments: bool) -> Result<RArray, Error> {
    let tokens = Tokenizer::new(&input, preserve_comments).tokenize();
    let array  = ruby.ary_new_capa(tokens.len());
    let klass  = token_class(ruby)?;

    for t in tokens {
        array.push(build_token(ruby, klass, t)?)?;
    }

    Ok(array)
}

fn token_class(ruby: &Ruby) -> Result<RClass, Error> {
    let css: Value = ruby.class_object().funcall("const_get", ("CSS",))?;
    css.funcall("const_get", ("Token",))
}

fn build_token(ruby: &Ruby, klass: RClass, token: Token) -> Result<Value, Error> {
    let kind_sym = kind_to_symbol(ruby, token.kind);
    let value    = value_to_ruby(ruby, &token.value);
    let flag_sym = flag_to_symbol(ruby, token.number_flag, token.hash_flag);
    let unit_val = unit_to_ruby(ruby, token.unit.as_deref());

    klass.funcall(
        "new",
        (kind_sym, value, kwargs!("flag" => flag_sym, "unit" => unit_val))
    )
}

fn kind_to_symbol(ruby: &Ruby, kind: Kind) -> magnus::value::StaticSymbol {
    let name = match kind {
        Kind::Ident      => "ident",
        Kind::Function   => "function",
        Kind::AtKeyword  => "at_keyword",
        Kind::Hash       => "hash",
        Kind::String_    => "string",
        Kind::BadString  => "bad_string",
        Kind::Url        => "url",
        Kind::BadUrl     => "bad_url",
        Kind::Delim      => "delim",
        Kind::Number     => "number",
        Kind::Percentage => "percentage",
        Kind::Dimension  => "dimension",
        Kind::Whitespace => "whitespace",
        Kind::Cdo        => "cdo",
        Kind::Cdc        => "cdc",
        Kind::Comment    => "comment",
        Kind::Colon      => "colon",
        Kind::Semicolon  => "semicolon",
        Kind::Comma      => "comma",
        Kind::LBracket   => "lbracket",
        Kind::RBracket   => "rbracket",
        Kind::LParen     => "lparen",
        Kind::RParen     => "rparen",
        Kind::LBrace     => "lbrace",
        Kind::RBrace     => "rbrace",
    };

    ruby.sym_new(name)
}

fn value_to_ruby(ruby: &Ruby, v: &TokenValue) -> Value {
    match v {
        TokenValue::None     => ruby.qnil().as_value(),
        TokenValue::Str(s)   => ruby.str_new(s).as_value(),
        TokenValue::Delim(c) => ruby.str_new(&c.to_string()).as_value(),
        TokenValue::Int(i)   => ruby.integer_from_i64(*i).as_value(),
        TokenValue::Float(f) => ruby.float_from_f64(*f).as_value(),
    }
}

fn flag_to_symbol(ruby: &Ruby, num: Option<NumberFlag>, hash: Option<HashFlag>) -> Value {
    match (num, hash) {
        (Some(NumberFlag::Integer), _) => ruby.sym_new("integer").as_value(),
        (Some(NumberFlag::Number),  _) => ruby.sym_new("number").as_value(),
        (_, Some(HashFlag::Id))        => ruby.sym_new("id").as_value(),
        (_, Some(HashFlag::Unrestricted)) => ruby.sym_new("unrestricted").as_value(),
        _                              => ruby.qnil().as_value(),
    }
}

fn unit_to_ruby(ruby: &Ruby, unit: Option<&str>) -> Value {
    match unit {
        Some(s) => ruby.str_new(s).as_value(),
        None    => ruby.qnil().as_value(),
    }
}

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let css    = ruby.define_module("CSS")?;
    let native = css.define_module("Native")?;

    native.define_singleton_method("hello",    function!(hello, 0))?;
    native.define_singleton_method("tokenize", function!(tokenize, 2))?;

    selectors::init(ruby)?;
    snapshot::init(ruby)?;

    Ok(())
}
