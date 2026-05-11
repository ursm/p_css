use crate::selectors::{AttrMatcher, CaseFlag, Combinator, Complex, Compound, Selector, Simple};
use crate::snapshot::{ElementData, Snapshot};

// Entry point. Returns true if any of the SelectorList alternatives match.
// Runs entirely against owned data — safe to call without the GVL.
pub fn matches(snap: &Snapshot, slot: u32, selector: &Selector) -> bool {
    selector.list().iter().any(|c| match_complex(snap, slot, c))
}

fn match_complex(snap: &Snapshot, slot: u32, complex: &Complex) -> bool {
    let last = complex.compounds.len().saturating_sub(1);
    match_at(snap, Some(slot), complex, last)
}

fn match_at(snap: &Snapshot, slot: Option<u32>, complex: &Complex, index: usize) -> bool {
    let Some(slot) = slot else { return false };

    if !match_compound(snap, slot, &complex.compounds[index]) {
        return false;
    }

    if index == 0 {
        return true;
    }

    let prev = index - 1;
    let element = snap.element(slot);

    match complex.combinators[prev] {
        Combinator::Descendant         => walk_until_match(snap, element.parent,       complex, prev, Step::Parent),
        Combinator::Child              => match_at(snap, element.parent,               complex, prev),
        Combinator::NextSibling        => match_at(snap, element.prev_sibling,         complex, prev),
        Combinator::SubsequentSibling  => walk_until_match(snap, element.prev_sibling, complex, prev, Step::PrevSibling),
    }
}

#[derive(Clone, Copy)]
enum Step {
    Parent,
    PrevSibling,
}

fn walk_until_match(
    snap:    &Snapshot,
    start:   Option<u32>,
    complex: &Complex,
    index:   usize,
    step:    Step,
) -> bool {
    let mut current = start;

    while let Some(slot) = current {
        if match_at(snap, Some(slot), complex, index) {
            return true;
        }

        let e = snap.element(slot);
        current = match step {
            Step::Parent      => e.parent,
            Step::PrevSibling => e.prev_sibling,
        };
    }

    false
}

fn match_compound(snap: &Snapshot, slot: u32, compound: &Compound) -> bool {
    let element = snap.element(slot);
    compound.components.iter().all(|s| match_simple(element, s))
}

fn match_simple(element: &ElementData, simple: &Simple) -> bool {
    match simple {
        Simple::Type(name)      => &element.tag == name,
        Simple::Universal       => true,
        Simple::Id(name)        => element.id.as_deref() == Some(name.as_str()),
        Simple::Class(name)     => element.classes.iter().any(|c| c == name),
        Simple::Attribute(attr) => match_attribute(element, attr),
    }
}

fn match_attribute(element: &ElementData, attr: &crate::selectors::AttrSel) -> bool {
    let actual = match attr.name.as_str() {
        "id"    => element.id.as_deref(),
        "class" => element.attrs.get("class").map(String::as_str),
        _       => element.attrs.get(&attr.name).map(String::as_str),
    };

    let Some(actual) = actual else { return false };
    let Some(matcher) = attr.matcher else { return true };

    let needle = attr.value.as_deref().unwrap_or("");
    let case_insensitive = attr.case_flag == Some(CaseFlag::I);

    let cmp_eq = |h: &str, n: &str| {
        if case_insensitive { h.eq_ignore_ascii_case(n) } else { h == n }
    };

    let starts = |h: &str, n: &str| {
        if case_insensitive {
            h.len() >= n.len() && h[..n.len()].eq_ignore_ascii_case(n)
        } else {
            h.starts_with(n)
        }
    };

    let ends = |h: &str, n: &str| {
        if case_insensitive {
            h.len() >= n.len() && h[h.len() - n.len()..].eq_ignore_ascii_case(n)
        } else {
            h.ends_with(n)
        }
    };

    let contains = |h: &str, n: &str| {
        if case_insensitive {
            h.to_ascii_lowercase().contains(&n.to_ascii_lowercase())
        } else {
            h.contains(n)
        }
    };

    match matcher {
        AttrMatcher::Exact     => cmp_eq(actual, needle),
        AttrMatcher::Includes  => !needle.is_empty()
            && actual.split_whitespace().any(|w| cmp_eq(w, needle)),
        AttrMatcher::Dash      => cmp_eq(actual, needle)
            || starts(actual, &format!("{}-", needle)),
        AttrMatcher::Prefix    => !needle.is_empty() && starts(actual, needle),
        AttrMatcher::Suffix    => !needle.is_empty() && ends(actual, needle),
        AttrMatcher::Substring => !needle.is_empty() && contains(actual, needle),
    }
}
