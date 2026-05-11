use crate::matcher;
use crate::selectors::Selector;
use crate::state::State;
use magnus::{
    prelude::*, value::ReprValue, Error, RArray, RHash, Ruby, TryConvert, Value,
};
use std::collections::HashMap;
use std::ffi::c_void;

// magnus 0.8 doesn't yet expose rb_thread_call_without_gvl, so we call
// it through rb-sys. The trampoline reads pointer-to-call-args, runs the
// batch of matches, and returns the boolean encoded into the raw void
// pointer.
struct MatchAnyArgs<'a> {
    snap:      &'a Snapshot,
    slot:      u32,
    selectors: &'a [&'a Selector],
    state:     Option<&'a State>,
}

unsafe extern "C" fn match_any_trampoline(data: *mut c_void) -> *mut c_void {
    let args = &*(data as *const MatchAnyArgs);
    let result = args.selectors.iter().any(|s| matcher::matches(args.snap, args.slot, s, args.state));
    result as usize as *mut c_void
}

struct MatchIndicesArgs<'a> {
    snap:      &'a Snapshot,
    slot:      u32,
    selectors: &'a [&'a Selector],
    out:       *mut Vec<u32>,
    state:     Option<&'a State>,
}

unsafe extern "C" fn match_indices_trampoline(data: *mut c_void) -> *mut c_void {
    let args = &*(data as *const MatchIndicesArgs);
    let out  = &mut *args.out;

    for (i, sel) in args.selectors.iter().enumerate() {
        if matcher::matches(args.snap, args.slot, sel, args.state) {
            out.push(i as u32);
        }
    }
    std::ptr::null_mut()
}

fn unwrap_state(value: Value) -> Result<Option<&'static State>, Error> {
    if value.is_nil() {
        return Ok(None);
    }

    // SAFETY: the State is held alive by Ruby for the duration of the
    // surrounding matches?* call.
    let state: &State = TryConvert::try_convert(value)?;
    Ok(Some(unsafe { std::mem::transmute::<&State, &'static State>(state) }))
}

fn unwrap_selectors(array: RArray) -> Result<Vec<&'static Selector>, Error> {
    // SAFETY: We hold the GVL during this conversion. The &Selector
    // references borrow from the Ruby-wrapped Selector objects, which
    // remain live for at least the duration of the surrounding call
    // because the Array holds strong references to them.
    let mut out = Vec::with_capacity(array.len());
    for v in array {
        let sel: &Selector = unsafe { std::mem::transmute(magnus::TryConvert::try_convert(v).map(|s: &Selector| s)?) };
        out.push(sel);
    }
    Ok(out)
}

// Compact, GVL-free DOM representation. All Strings are owned, all
// references are indices into `elements`, so matching can run entirely
// without holding the GVL once the snapshot is built.
#[derive(Debug)]
pub struct ElementData {
    pub tag:          String,                  // ascii-lowercased
    pub id:           Option<String>,
    pub classes:      Vec<String>,             // pre-split, no whitespace
    pub attrs:        HashMap<String, String>,
    pub parent:       Option<u32>,
    pub prev_sibling: Option<u32>,
    pub next_sibling: Option<u32>,
    pub first_child:  Option<u32>, // first element child, for ancestor traversal in :disabled
    // `:empty` per CSS3 — no element children and no non-whitespace text.
    // Comments/processing-instructions/doctypes don't disqualify.
    pub is_empty:     bool,
    // 1-based positions among parent's element children, used by nth-*
    // and (first|last|only)-of-type. Root elements get 1/1.
    pub index:               u32, // among all siblings
    pub last_index:          u32, // among all siblings, counted from the end
    pub index_of_type:       u32, // among same-tag siblings
    pub last_index_of_type:  u32, // among same-tag siblings, counted from the end
}

#[magnus::wrap(class = "CSS::Native::Snapshot", free_immediately, size)]
pub struct Snapshot {
    elements:   Vec<ElementData>,
    id_to_slot: HashMap<i64, u32>,
}

impl Snapshot {
    pub fn from_document(doc: Value) -> Result<Snapshot, Error> {
        let node_set: Value = doc.funcall("css", ("*",))?;
        let nodes:    RArray = node_set.funcall("to_a", ())?;
        let len    = nodes.len();

        // First pass: assign slot indices so parent/sibling lookups can resolve.
        let mut id_to_slot   = HashMap::with_capacity(len);
        let mut node_values: Vec<Value> = Vec::with_capacity(len);

        for (i, n) in nodes.into_iter().enumerate() {
            let oid: i64 = n.funcall("object_id", ())?;
            id_to_slot.insert(oid, i as u32);
            node_values.push(n);
        }

        // Second pass: extract element data.
        let mut elements = Vec::with_capacity(len);
        for n in &node_values {
            elements.push(build_element(*n, &id_to_slot)?);
        }

        // Third pass: compute sibling indices for :nth-* / *-of-type.
        compute_sibling_indices(&mut elements);

        Ok(Snapshot { elements, id_to_slot })
    }

    pub fn size(&self) -> usize {
        self.elements.len()
    }

    pub fn slot_for(&self, object_id: i64) -> Option<u32> {
        self.id_to_slot.get(&object_id).copied()
    }

    pub fn element(&self, slot: u32) -> &ElementData {
        &self.elements[slot as usize]
    }

    pub fn matches(&self, element: Value, selector: &Selector, state: Value) -> Result<bool, Error> {
        let slot       = self.resolve_slot(element)?;
        let state_ref  = unwrap_state(state)?;
        // GVL release adds ~1μs of release/reacquire overhead, which
        // exceeds the work per single-selector match. We keep this path
        // GVL-held; callers wanting thread parallelism should use the
        // batch API below.
        Ok(matcher::matches(self, slot, selector, state_ref))
    }

    pub fn matches_any(&self, element: Value, selectors: RArray, state: Value) -> Result<bool, Error> {
        let slot      = self.resolve_slot(element)?;
        let sels      = unwrap_selectors(selectors)?;
        let state_ref = unwrap_state(state)?;

        let args = MatchAnyArgs { snap: self, slot, selectors: &sels, state: state_ref };
        let data = &args as *const MatchAnyArgs as *mut c_void;

        let raw = unsafe {
            rb_sys::rb_thread_call_without_gvl(
                Some(match_any_trampoline),
                data,
                None,
                std::ptr::null_mut(),
            )
        };

        Ok(raw as usize != 0)
    }

    pub fn match_indices(&self, element: Value, selectors: RArray, state: Value) -> Result<RArray, Error> {
        let slot      = self.resolve_slot(element)?;
        let sels      = unwrap_selectors(selectors)?;
        let state_ref = unwrap_state(state)?;

        let mut out_buf: Vec<u32> = Vec::with_capacity(sels.len());
        let buf_ptr = &mut out_buf as *mut Vec<u32>;
        let args = MatchIndicesArgs { snap: self, slot, selectors: &sels, out: buf_ptr, state: state_ref };
        let data = &args as *const MatchIndicesArgs as *mut c_void;

        unsafe {
            rb_sys::rb_thread_call_without_gvl(
                Some(match_indices_trampoline),
                data,
                None,
                std::ptr::null_mut(),
            );
        }

        let ruby   = Ruby::get().unwrap();
        let result = ruby.ary_new_capa(out_buf.len());
        for i in out_buf {
            result.push(i as i64)?;
        }
        Ok(result)
    }

    pub fn compile_state(&self, hash: RHash) -> Result<State, Error> {
        State::compile(self, hash)
    }

    fn resolve_slot(&self, element: Value) -> Result<u32, Error> {
        let oid: i64 = element.funcall("object_id", ())?;

        self.slot_for(oid).ok_or_else(|| {
            Error::new(
                Ruby::get().unwrap().exception_arg_error(),
                "element not present in snapshot — rebuild after DOM mutation",
            )
        })
    }
}

fn build_element(node: Value, id_to_slot: &HashMap<i64, u32>) -> Result<ElementData, Error> {
    let tag          = read_tag(node)?;
    let id           = read_str_attr(node, "id")?;
    let classes      = read_classes(node)?;
    let attrs        = collect_attrs(node)?;
    let parent       = resolve_ref(node, "parent", id_to_slot, true)?;
    let prev_sibling = resolve_ref(node, "previous_element", id_to_slot, false)?;
    let next_sibling = resolve_ref(node, "next_element",     id_to_slot, false)?;
    let is_empty     = compute_is_empty(node)?;

    Ok(ElementData {
        tag, id, classes, attrs,
        parent, prev_sibling, next_sibling,
        first_child: None,
        is_empty,
        index: 1, last_index: 1, index_of_type: 1, last_index_of_type: 1,
    })
}

// Group elements by parent, then assign 1-based indices in document order
// (overall and per-tag), plus their counted-from-end counterparts.
fn compute_sibling_indices(elements: &mut [ElementData]) {
    let mut groups: HashMap<Option<u32>, Vec<u32>> = HashMap::new();
    for (i, el) in elements.iter().enumerate() {
        groups.entry(el.parent).or_default().push(i as u32);
    }

    for (parent, siblings) in &groups {
        let total = siblings.len() as u32;

        // Populate first_child on the parent element (if any).
        if let (Some(parent_slot), Some(&first)) = (parent, siblings.first()) {
            elements[*parent_slot as usize].first_child = Some(first);
        }

        // Per-tag totals first, then per-tag running positions.
        let mut totals_by_tag: HashMap<String, u32> = HashMap::new();
        for &slot in siblings {
            *totals_by_tag.entry(elements[slot as usize].tag.clone()).or_insert(0) += 1;
        }

        let mut positions_by_tag: HashMap<String, u32> = HashMap::new();
        for (i, &slot) in siblings.iter().enumerate() {
            let tag           = elements[slot as usize].tag.clone();
            let pos_in_type   = positions_by_tag.entry(tag.clone()).or_insert(0);
            *pos_in_type     += 1;
            let pos_in_type   = *pos_in_type;
            let total_in_type = totals_by_tag[&tag];

            let el = &mut elements[slot as usize];
            el.index              = (i as u32) + 1;
            el.last_index         = total - i as u32;
            el.index_of_type      = pos_in_type;
            el.last_index_of_type = total_in_type - pos_in_type + 1;
        }
    }
}

fn compute_is_empty(node: Value) -> Result<bool, Error> {
    let children: RArray = node.funcall::<_, _, Value>("children", ())?.funcall("to_a", ())?;

    for child in children {
        if child.funcall::<_, _, bool>("element?", ()).unwrap_or(false) {
            return Ok(false);
        }

        if child.funcall::<_, _, bool>("text?", ()).unwrap_or(false) {
            let content: String = child.funcall("content", ())?;
            if content.chars().any(|c| !c.is_whitespace()) {
                return Ok(false);
            }
        }
    }

    Ok(true)
}

fn read_tag(node: Value) -> Result<String, Error> {
    let name: String = node.funcall("name", ())?;

    if name.chars().any(|c| c.is_ascii_uppercase()) {
        Ok(name.to_ascii_lowercase())
    } else {
        Ok(name)
    }
}

fn read_str_attr(node: Value, attr: &str) -> Result<Option<String>, Error> {
    let v: Value = node.funcall("[]", (attr,))?;
    if v.is_nil() {
        Ok(None)
    } else {
        Ok(Some(TryConvert::try_convert(v)?))
    }
}

fn read_classes(node: Value) -> Result<Vec<String>, Error> {
    match read_str_attr(node, "class")? {
        None    => Ok(Vec::new()),
        Some(s) => Ok(s.split_whitespace().map(String::from).collect()),
    }
}

fn collect_attrs(node: Value) -> Result<HashMap<String, String>, Error> {
    let attrs: RHash = node.funcall("attributes", ())?;
    let mut map = HashMap::with_capacity(attrs.len());

    attrs.foreach(|k: String, v: Value| {
        let value: String = v.funcall("value", ())?;
        map.insert(k, value);
        Ok(magnus::r_hash::ForEach::Continue)
    })?;

    Ok(map)
}

// `method_name` returns nil when the relation doesn't exist (root, no
// sibling, etc.) or returns a Nokogiri node that may be a non-element
// (Document, Text). We only record the slot when it's an element we
// already indexed.
fn resolve_ref(
    node:       Value,
    method:     &str,
    id_to_slot: &HashMap<i64, u32>,
    check_kind: bool,
) -> Result<Option<u32>, Error> {
    let ref_val: Value = node.funcall(method, ())?;

    if ref_val.is_nil() {
        return Ok(None);
    }

    if check_kind {
        let is_elem: bool = ref_val.funcall("element?", ()).unwrap_or(false);
        if !is_elem {
            return Ok(None);
        }
    }

    let oid: i64 = ref_val.funcall("object_id", ())?;
    Ok(id_to_slot.get(&oid).copied())
}

pub fn init(ruby: &Ruby) -> Result<(), Error> {
    let css    = ruby.define_module("CSS")?;
    let native = css.define_module("Native")?;
    let class  = native.define_class("Snapshot", ruby.class_object())?;

    class.define_singleton_method("from_document", magnus::function!(Snapshot::from_document, 1))?;
    class.define_method("size",                    magnus::method!(Snapshot::size, 0))?;
    class.define_method("matches?",                magnus::method!(Snapshot::matches,        3))?;
    class.define_method("matches_any?",            magnus::method!(Snapshot::matches_any,    3))?;
    class.define_method("match_indices",           magnus::method!(Snapshot::match_indices,  3))?;
    class.define_method("compile_state",           magnus::method!(Snapshot::compile_state,  1))?;

    Ok(())
}
