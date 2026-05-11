use crate::snapshot::Snapshot;
use magnus::{prelude::*, value::ReprValue, Error, RArray, RHash, TryConvert, Value};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StatefulKind {
    Hover,
    Focus,
    FocusWithin,
    FocusVisible,
    Active,
    Visited,
    Target,
}

// Pseudos whose "source" elements propagate the state up the ancestor
// chain (CSS Selectors §10): if a descendant is hovered/active/contains
// focus, its ancestors also satisfy the pseudo.
const PROPAGATING: &[StatefulKind] = &[
    StatefulKind::Hover,
    StatefulKind::Active,
    StatefulKind::FocusWithin,
];

#[derive(Debug)]
pub enum StateValue {
    None,
    All,
    Slots(Vec<u32>),
}

#[magnus::wrap(class = "CSS::Native::State", free_immediately, size)]
pub struct State {
    hover:         StateValue,
    focus:         StateValue,
    focus_within:  StateValue,
    focus_visible: StateValue,
    active:        StateValue,
    visited:       StateValue,
    target:        StateValue,
}

impl State {
    pub fn empty() -> Self {
        Self {
            hover:         StateValue::None,
            focus:         StateValue::None,
            focus_within:  StateValue::None,
            focus_visible: StateValue::None,
            active:        StateValue::None,
            visited:       StateValue::None,
            target:        StateValue::None,
        }
    }

    pub fn compile(snap: &Snapshot, hash: RHash) -> Result<State, Error> {
        let mut state = State::empty();

        hash.foreach(|k: Value, v: Value| {
            // Keys can be Symbol or String — normalize to lowercased str.
            let name: String = k.funcall("to_s", ())?;

            let kind = match name.as_str() {
                "hover"         => StatefulKind::Hover,
                "focus"         => StatefulKind::Focus,
                "focus-within"  => StatefulKind::FocusWithin,
                "focus-visible" => StatefulKind::FocusVisible,
                "active"        => StatefulKind::Active,
                "visited"       => StatefulKind::Visited,
                "target"        => StatefulKind::Target,
                _ => return Ok(magnus::r_hash::ForEach::Continue),
            };

            state.set(kind, compile_value(snap, v)?);

            Ok(magnus::r_hash::ForEach::Continue)
        })?;

        Ok(state)
    }

    fn set(&mut self, kind: StatefulKind, value: StateValue) {
        match kind {
            StatefulKind::Hover         => self.hover = value,
            StatefulKind::Focus         => self.focus = value,
            StatefulKind::FocusWithin   => self.focus_within = value,
            StatefulKind::FocusVisible  => self.focus_visible = value,
            StatefulKind::Active        => self.active = value,
            StatefulKind::Visited       => self.visited = value,
            StatefulKind::Target        => self.target = value,
        }
    }

    fn get(&self, kind: StatefulKind) -> &StateValue {
        match kind {
            StatefulKind::Hover         => &self.hover,
            StatefulKind::Focus         => &self.focus,
            StatefulKind::FocusWithin   => &self.focus_within,
            StatefulKind::FocusVisible  => &self.focus_visible,
            StatefulKind::Active        => &self.active,
            StatefulKind::Visited       => &self.visited,
            StatefulKind::Target        => &self.target,
        }
    }

    pub fn matches(&self, snap: &Snapshot, slot: u32, kind: StatefulKind) -> bool {
        match self.get(kind) {
            StateValue::None      => false,
            StateValue::All       => true,
            StateValue::Slots(slots) => {
                if PROPAGATING.contains(&kind) {
                    propagating_match(snap, slot, slots)
                } else {
                    slots.contains(&slot)
                }
            }
        }
    }
}

fn propagating_match(snap: &Snapshot, slot: u32, sources: &[u32]) -> bool {
    // For each source, walk up its ancestor chain. The element matches if
    // it IS the source or any of its ancestors.
    sources.iter().any(|&source| {
        let mut cur = Some(source);
        while let Some(s) = cur {
            if s == slot {
                return true;
            }
            cur = snap.element(s).parent;
        }
        false
    })
}

fn compile_value(snap: &Snapshot, value: Value) -> Result<StateValue, Error> {
    let ruby = magnus::Ruby::get().unwrap();

    // Strict singleton check — `bool::try_convert` does a truthy/falsy
    // reduction (every non-nil/non-false value → true), which would map
    // an Array of elements to All. Inspect the class instead.
    if value.is_nil() || value.is_kind_of(ruby.class_false_class()) {
        return Ok(StateValue::None);
    }
    if value.is_kind_of(ruby.class_true_class()) {
        return Ok(StateValue::All);
    }

    let array: RArray = if value.is_kind_of(ruby.class_array()) {
        RArray::from_value(value).unwrap()
    } else {
        // Set / other Enumerable
        value.funcall("to_a", ())?
    };

    let mut slots = Vec::with_capacity(array.len());

    for el in array {
        let oid: i64 = el.funcall("object_id", ())?;
        if let Some(s) = snap.slot_for(oid) {
            slots.push(s);
        }
    }

    Ok(StateValue::Slots(slots))
}

pub fn init(ruby: &magnus::Ruby) -> Result<(), Error> {
    let css    = ruby.define_module("CSS")?;
    let native = css.define_module("Native")?;

    native.define_class("State", ruby.class_object())?;

    Ok(())
}
