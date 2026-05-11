use crate::selectors::{AnB, AttrMatcher, CaseFlag, Combinator, Complex, Compound, Pseudo, Selector, Simple};
use crate::snapshot::{ElementData, Snapshot};
use crate::state::{State, StatefulKind};

// Entry point. Returns true if any of the SelectorList alternatives match.
// Runs entirely against owned data — safe to call without the GVL.
pub fn matches(snap: &Snapshot, slot: u32, selector: &Selector, state: Option<&State>) -> bool {
    selector.list().iter().any(|c| match_complex(snap, slot, c, state))
}

fn match_complex(snap: &Snapshot, slot: u32, complex: &Complex, state: Option<&State>) -> bool {
    let last = complex.compounds.len().saturating_sub(1);
    match_at(snap, Some(slot), complex, last, state)
}

fn match_at(snap: &Snapshot, slot: Option<u32>, complex: &Complex, index: usize, state: Option<&State>) -> bool {
    let Some(slot) = slot else { return false };

    if !match_compound(snap, slot, &complex.compounds[index], state) {
        return false;
    }

    if index == 0 {
        return true;
    }

    let prev = index - 1;
    let element = snap.element(slot);

    match complex.combinators[prev] {
        Combinator::Descendant         => walk_until_match(snap, element.parent,       complex, prev, Step::Parent,      state),
        Combinator::Child              => match_at(snap, element.parent,               complex, prev,                    state),
        Combinator::NextSibling        => match_at(snap, element.prev_sibling,         complex, prev,                    state),
        Combinator::SubsequentSibling  => walk_until_match(snap, element.prev_sibling, complex, prev, Step::PrevSibling, state),
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
    state:   Option<&State>,
) -> bool {
    let mut current = start;

    while let Some(slot) = current {
        if match_at(snap, Some(slot), complex, index, state) {
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

fn match_compound(snap: &Snapshot, slot: u32, compound: &Compound, state: Option<&State>) -> bool {
    let element = snap.element(slot);
    compound.components.iter().all(|s| match_simple(snap, slot, element, s, state))
}

fn match_simple(snap: &Snapshot, slot: u32, element: &ElementData, simple: &Simple, state: Option<&State>) -> bool {
    match simple {
        Simple::Type(name)      => &element.tag == name,
        Simple::Universal       => true,
        Simple::Id(name)        => element.id.as_deref() == Some(name.as_str()),
        Simple::Class(name)     => element.classes.iter().any(|c| c == name),
        Simple::Attribute(attr) => match_attribute(element, attr),
        Simple::PseudoClass(p)  => match_pseudo(snap, slot, element, p, state),
    }
}

fn match_pseudo(snap: &Snapshot, slot: u32, element: &ElementData, pseudo: &Pseudo, state: Option<&State>) -> bool {
    match pseudo {
        Pseudo::Root        => element.parent.is_none(),
        Pseudo::FirstChild  => element.prev_sibling.is_none(),
        Pseudo::LastChild   => element.next_sibling.is_none(),
        Pseudo::OnlyChild   => element.prev_sibling.is_none() && element.next_sibling.is_none(),
        Pseudo::Empty       => element.is_empty,
        Pseudo::Defined     => true,
        Pseudo::FirstOfType => element.index_of_type == 1,
        Pseudo::LastOfType  => element.last_index_of_type == 1,
        Pseudo::OnlyOfType  => element.index_of_type == 1 && element.last_index_of_type == 1,

        // Pure-Ruby parity: nth-* require a parent. Root elements never
        // satisfy them, even when the index would be 1.
        Pseudo::NthChild(anb)       => element.parent.is_some() && match_anb(anb, element.index),
        Pseudo::NthLastChild(anb)   => element.parent.is_some() && match_anb(anb, element.last_index),
        Pseudo::NthOfType(anb)      => element.parent.is_some() && match_anb(anb, element.index_of_type),
        Pseudo::NthLastOfType(anb)  => element.parent.is_some() && match_anb(anb, element.last_index_of_type),

        Pseudo::Is(list)  =>  list.iter().any(|c| match_complex(snap, slot, c, state)),
        Pseudo::Not(list) => !list.iter().any(|c| match_complex(snap, slot, c, state)),

        Pseudo::Link             => is_link(element),
        Pseudo::Enabled          => is_disableable(element) && !is_disabled(snap, slot),
        Pseudo::Disabled         => is_disableable(element) &&  is_disabled(snap, slot),
        Pseudo::Checked          => is_checked(element),
        Pseudo::Required         => is_input_like(element) && element.attrs.contains_key("required"),
        Pseudo::Optional         => is_input_like(element) && !element.attrs.contains_key("required"),
        Pseudo::ReadOnly         => is_read_only(snap, slot, element),
        Pseudo::ReadWrite        => is_read_write(snap, slot, element),
        Pseudo::PlaceholderShown => is_placeholder_shown(element),

        Pseudo::Hover        => stateful(state, snap, slot, StatefulKind::Hover),
        Pseudo::Focus        => stateful(state, snap, slot, StatefulKind::Focus),
        Pseudo::FocusWithin  => stateful(state, snap, slot, StatefulKind::FocusWithin),
        Pseudo::FocusVisible => stateful(state, snap, slot, StatefulKind::FocusVisible),
        Pseudo::Active       => stateful(state, snap, slot, StatefulKind::Active),
        Pseudo::Visited      => stateful(state, snap, slot, StatefulKind::Visited),
        Pseudo::Target       => stateful(state, snap, slot, StatefulKind::Target),
    }
}

fn stateful(state: Option<&State>, snap: &Snapshot, slot: u32, kind: StatefulKind) -> bool {
    state.is_some_and(|s| s.matches(snap, slot, kind))
}

const LINK_TAGS:        &[&str] = &["a", "area", "link"];
const DISABLEABLE_TAGS: &[&str] = &["button", "input", "select", "textarea", "optgroup", "option", "fieldset"];
const INPUT_TAGS:       &[&str] = &["input", "textarea", "select"];
const RO_INPUT_TYPES:   &[&str] = &["hidden", "range", "color", "checkbox", "radio", "file", "submit", "image", "reset", "button"];

fn is_link(element: &ElementData) -> bool {
    LINK_TAGS.contains(&element.tag.as_str()) && element.attrs.contains_key("href")
}

fn is_disableable(element: &ElementData) -> bool {
    DISABLEABLE_TAGS.contains(&element.tag.as_str())
}

fn is_input_like(element: &ElementData) -> bool {
    INPUT_TAGS.contains(&element.tag.as_str())
}

fn is_checked(element: &ElementData) -> bool {
    match element.tag.as_str() {
        "input" => {
            let ty = element.attrs.get("type").map(String::as_str).unwrap_or("");
            (ty.eq_ignore_ascii_case("checkbox") || ty.eq_ignore_ascii_case("radio"))
                && element.attrs.contains_key("checked")
        }
        "option" => element.attrs.contains_key("selected"),
        _ => false,
    }
}

// `:disabled` walks the ancestor chain. A fieldset[disabled] disables every
// descendant unless that descendant sits inside the fieldset's first <legend>.
fn is_disabled(snap: &Snapshot, slot: u32) -> bool {
    let element = snap.element(slot);
    if element.attrs.contains_key("disabled") {
        return true;
    }

    let mut ancestor = element.parent;
    while let Some(a_slot) = ancestor {
        let a = snap.element(a_slot);
        if a.tag == "fieldset" && a.attrs.contains_key("disabled") {
            if !is_inside_first_legend(snap, slot, a_slot) {
                return true;
            }
        }
        ancestor = a.parent;
    }

    false
}

fn is_inside_first_legend(snap: &Snapshot, element_slot: u32, fieldset_slot: u32) -> bool {
    let Some(first_legend) = first_legend_child(snap, fieldset_slot) else {
        return false;
    };

    let mut cur = Some(element_slot);
    while let Some(s) = cur {
        if s == first_legend  { return true; }
        if s == fieldset_slot { return false; }
        cur = snap.element(s).parent;
    }
    false
}

fn first_legend_child(snap: &Snapshot, parent_slot: u32) -> Option<u32> {
    let mut cur = snap.element(parent_slot).first_child;
    while let Some(s) = cur {
        if snap.element(s).tag == "legend" {
            return Some(s);
        }
        cur = snap.element(s).next_sibling;
    }
    None
}

fn is_read_only(snap: &Snapshot, slot: u32, element: &ElementData) -> bool {
    match element.tag.as_str() {
        "input" => {
            let ty = element.attrs.get("type").map(String::as_str).unwrap_or("");
            if RO_INPUT_TYPES.iter().any(|t| ty.eq_ignore_ascii_case(t)) {
                return true;
            }
            element.attrs.contains_key("readonly") || is_disabled(snap, slot)
        }
        "textarea" => element.attrs.contains_key("readonly") || is_disabled(snap, slot),
        _ => {
            let ce = element.attrs.get("contenteditable")
                .map(|s| s.to_ascii_lowercase())
                .unwrap_or_default();
            ce.is_empty() || (ce != "true" && ce != "plaintext-only")
        }
    }
}

fn is_read_write(snap: &Snapshot, slot: u32, element: &ElementData) -> bool {
    match element.tag.as_str() {
        "input" | "textarea" => !is_read_only(snap, slot, element),
        _ => {
            let ce = element.attrs.get("contenteditable")
                .map(|s| s.to_ascii_lowercase())
                .unwrap_or_default();
            ce == "true" || ce == "plaintext-only"
        }
    }
}

fn is_placeholder_shown(element: &ElementData) -> bool {
    if element.tag != "input" && element.tag != "textarea" {
        return false;
    }
    if !element.attrs.contains_key("placeholder") {
        return false;
    }
    let value = element.attrs.get("value").map(String::as_str).unwrap_or("");
    value.is_empty()
}

// CSS Selectors §6.6.5.1: matches when there exists a non-negative integer
// `k` such that `index == step * k + offset`. When step is zero, that
// collapses to `index == offset`.
fn match_anb(anb: &AnB, index: u32) -> bool {
    let index = index as i64;

    if anb.step == 0 {
        return index == anb.offset;
    }

    let diff = index - anb.offset;
    diff % anb.step == 0 && (diff / anb.step) >= 0
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
