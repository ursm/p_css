use crate::matcher;
use crate::selectors::Selector;
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
}

unsafe extern "C" fn match_any_trampoline(data: *mut c_void) -> *mut c_void {
    let args = &*(data as *const MatchAnyArgs);
    let result = args.selectors.iter().any(|s| matcher::matches(args.snap, args.slot, s));
    result as usize as *mut c_void
}

struct MatchIndicesArgs<'a> {
    snap:      &'a Snapshot,
    slot:      u32,
    selectors: &'a [&'a Selector],
    out:       *mut Vec<u32>,
}

unsafe extern "C" fn match_indices_trampoline(data: *mut c_void) -> *mut c_void {
    let args = &*(data as *const MatchIndicesArgs);
    let out  = &mut *args.out;

    for (i, sel) in args.selectors.iter().enumerate() {
        if matcher::matches(args.snap, args.slot, sel) {
            out.push(i as u32);
        }
    }
    std::ptr::null_mut()
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

    pub fn matches(&self, element: Value, selector: &Selector) -> Result<bool, Error> {
        let slot = self.resolve_slot(element)?;
        // GVL release adds ~1μs of release/reacquire overhead, which
        // exceeds the work per single-selector match. We keep this path
        // GVL-held; callers wanting thread parallelism should use the
        // batch API below.
        Ok(matcher::matches(self, slot, selector))
    }

    pub fn matches_any(&self, element: Value, selectors: RArray) -> Result<bool, Error> {
        let slot = self.resolve_slot(element)?;
        let sels = unwrap_selectors(selectors)?;

        let args = MatchAnyArgs { snap: self, slot, selectors: &sels };
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

    pub fn match_indices(&self, element: Value, selectors: RArray) -> Result<RArray, Error> {
        let slot = self.resolve_slot(element)?;
        let sels = unwrap_selectors(selectors)?;

        let mut out_buf: Vec<u32> = Vec::with_capacity(sels.len());
        let buf_ptr = &mut out_buf as *mut Vec<u32>;
        let args = MatchIndicesArgs { snap: self, slot, selectors: &sels, out: buf_ptr };
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
    let tag         = read_tag(node)?;
    let id          = read_str_attr(node, "id")?;
    let classes     = read_classes(node)?;
    let attrs       = collect_attrs(node)?;
    let parent      = resolve_ref(node, "parent", id_to_slot, true)?;
    let prev_sibling = resolve_ref(node, "previous_element", id_to_slot, false)?;
    let next_sibling = resolve_ref(node, "next_element",     id_to_slot, false)?;

    Ok(ElementData { tag, id, classes, attrs, parent, prev_sibling, next_sibling })
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
    class.define_method("matches?",                magnus::method!(Snapshot::matches, 2))?;
    class.define_method("matches_any?",            magnus::method!(Snapshot::matches_any, 2))?;
    class.define_method("match_indices",            magnus::method!(Snapshot::match_indices, 2))?;

    Ok(())
}
