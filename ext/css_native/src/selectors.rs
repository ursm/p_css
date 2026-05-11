use magnus::{
    exception::ExceptionClass, prelude::*, value::ReprValue, Error, RArray, RClass, Ruby, TryConvert, Value,
};

#[derive(Debug, Clone, Copy)]
pub enum Combinator {
    Descendant,
    Child,
    NextSibling,
    SubsequentSibling,
}

#[derive(Debug, Clone, Copy)]
pub enum AttrMatcher {
    Exact,
    Includes,
    Dash,
    Prefix,
    Suffix,
    Substring,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CaseFlag {
    I,
    S,
}

#[derive(Debug)]
pub struct AttrSel {
    pub name:      String, // ASCII-lowercased
    pub matcher:   Option<AttrMatcher>,
    pub value:     Option<String>,
    pub case_flag: Option<CaseFlag>,
}

#[derive(Debug)]
pub enum Simple {
    Type(String), // ASCII-lowercased
    Universal,
    Id(String),
    Class(String),
    Attribute(AttrSel),
}

#[derive(Debug)]
pub struct Compound {
    pub components: Vec<Simple>,
}

#[derive(Debug)]
pub struct Complex {
    pub compounds:   Vec<Compound>,
    pub combinators: Vec<Combinator>,
}

#[magnus::wrap(class = "CSS::Native::Selector", free_immediately, size)]
pub struct Selector {
    list: Vec<Complex>,
}

impl Selector {
    pub fn list(&self) -> &[Complex] {
        &self.list
    }

    pub fn compile(ast: Value) -> Result<Selector, Error> {
        let list = match class_name(ast)?.as_str() {
            "CSS::Selectors::SelectorList" => {
                let selectors: RArray = ast.funcall("selectors", ())?;
                let mut out = Vec::with_capacity(selectors.len());
                for s in selectors {
                    out.push(convert_complex(s)?);
                }
                out
            }
            "CSS::Selectors::ComplexSelector" => vec![convert_complex(ast)?],
            "CSS::Selectors::CompoundSelector" => vec![Complex {
                compounds:   vec![convert_compound(ast)?],
                combinators: vec![],
            }],
            other => return Err(unsupported(&format!("expected SelectorList/Complex/Compound, got {}", other))),
        };

        Ok(Selector { list })
    }
}

fn convert_complex(value: Value) -> Result<Complex, Error> {
    let compounds_arr:   RArray = value.funcall("compounds",   ())?;
    let combinators_arr: RArray = value.funcall("combinators", ())?;

    let mut compounds = Vec::with_capacity(compounds_arr.len());
    for c in compounds_arr {
        compounds.push(convert_compound(c)?);
    }

    let mut combinators = Vec::with_capacity(combinators_arr.len());
    for c in combinators_arr {
        combinators.push(convert_combinator(c)?);
    }

    Ok(Complex { compounds, combinators })
}

fn convert_compound(value: Value) -> Result<Compound, Error> {
    let components_arr: RArray = value.funcall("components", ())?;
    let mut components = Vec::with_capacity(components_arr.len());

    for c in components_arr {
        components.push(convert_simple(c)?);
    }

    Ok(Compound { components })
}

fn convert_simple(value: Value) -> Result<Simple, Error> {
    let class = class_name(value)?;

    match class.as_str() {
        "CSS::Selectors::TypeSelector" => {
            let name: String = value.funcall("name", ())?;
            Ok(Simple::Type(ascii_lower(name)))
        }
        "CSS::Selectors::UniversalSelector" => Ok(Simple::Universal),
        "CSS::Selectors::IdSelector" => {
            let name: String = value.funcall("name", ())?;
            Ok(Simple::Id(name))
        }
        "CSS::Selectors::ClassSelector" => {
            let name: String = value.funcall("name", ())?;
            Ok(Simple::Class(name))
        }
        "CSS::Selectors::AttributeSelector" => Ok(Simple::Attribute(convert_attr(value)?)),
        other => Err(unsupported(&format!("{} not supported by native matcher", other))),
    }
}

fn convert_attr(value: Value) -> Result<AttrSel, Error> {
    let name: String = value.funcall("name", ())?;
    let matcher = convert_attr_matcher(value.funcall("matcher", ())?)?;
    let value_str = optional_string(value.funcall("value", ())?)?;
    let case_flag = convert_case_flag(value.funcall("case_flag", ())?)?;

    Ok(AttrSel {
        name: ascii_lower(name),
        matcher,
        value: value_str,
        case_flag,
    })
}

fn convert_attr_matcher(value: Value) -> Result<Option<AttrMatcher>, Error> {
    if value.is_nil() {
        return Ok(None);
    }

    let s: String = value.funcall("to_s", ())?;

    Ok(Some(match s.as_str() {
        "exact"     => AttrMatcher::Exact,
        "includes"  => AttrMatcher::Includes,
        "dash"      => AttrMatcher::Dash,
        "prefix"    => AttrMatcher::Prefix,
        "suffix"    => AttrMatcher::Suffix,
        "substring" => AttrMatcher::Substring,
        other       => return Err(unsupported(&format!("unknown attribute matcher: {}", other))),
    }))
}

fn convert_case_flag(value: Value) -> Result<Option<CaseFlag>, Error> {
    if value.is_nil() {
        return Ok(None);
    }

    let s: String = value.funcall("to_s", ())?;

    Ok(Some(match s.as_str() {
        "i" => CaseFlag::I,
        "s" => CaseFlag::S,
        other => return Err(unsupported(&format!("unknown case flag: {}", other))),
    }))
}

fn convert_combinator(value: Value) -> Result<Combinator, Error> {
    let s: String = value.funcall("to_s", ())?;

    Ok(match s.as_str() {
        "descendant"         => Combinator::Descendant,
        "child"              => Combinator::Child,
        "next_sibling"       => Combinator::NextSibling,
        "subsequent_sibling" => Combinator::SubsequentSibling,
        other                => return Err(unsupported(&format!("unknown combinator: {}", other))),
    })
}

fn class_name(value: Value) -> Result<String, Error> {
    let klass: RClass = value.class();
    let name: Value = klass.funcall("name", ())?;
    TryConvert::try_convert(name)
}

fn optional_string(value: Value) -> Result<Option<String>, Error> {
    if value.is_nil() {
        Ok(None)
    } else {
        Ok(Some(TryConvert::try_convert(value)?))
    }
}

fn ascii_lower(s: String) -> String {
    if s.chars().any(|c| c.is_ascii_uppercase()) {
        s.to_ascii_lowercase()
    } else {
        s
    }
}

pub fn unsupported(msg: &str) -> Error {
    let ruby = Ruby::get().expect("must be on Ruby thread");
    let class = ruby
        .eval::<Value>("CSS::Native::Unsupported")
        .ok()
        .and_then(|v| ExceptionClass::from_value(v))
        .unwrap_or_else(|| ruby.exception_runtime_error());

    Error::new(class, msg.to_string())
}

pub fn init(ruby: &Ruby) -> Result<(), Error> {
    let css      = ruby.define_module("CSS")?;
    let native   = css.define_module("Native")?;
    let std_err  = ruby.exception_standard_error();

    native.define_error("Unsupported", std_err)?;

    let class = native.define_class("Selector", ruby.class_object())?;
    class.define_singleton_method("compile", magnus::function!(Selector::compile, 1))?;

    Ok(())
}
