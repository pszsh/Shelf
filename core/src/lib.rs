pub mod clip;
pub mod icon;
pub mod store;

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;

use clip::{Clip, ContentType};
use store::Store;

#[repr(C)]
pub struct ShelfClip {
    pub id: *mut c_char,
    pub timestamp: f64,
    pub content_type: u8,
    pub text_content: *mut c_char,
    pub image_path: *mut c_char,
    pub source_app: *mut c_char,
    pub is_pinned: bool,
    pub displaced_prev: i32,
    pub displaced_next: i32,
}

#[repr(C)]
pub struct ShelfClipList {
    pub clips: *mut ShelfClip,
    pub count: usize,
}

fn to_c_string(s: &str) -> *mut c_char {
    CString::new(s).unwrap_or_default().into_raw()
}

fn opt_to_c(s: &Option<String>) -> *mut c_char {
    match s {
        Some(s) => to_c_string(s),
        None => ptr::null_mut(),
    }
}

unsafe fn from_c(p: *const c_char) -> Option<String> {
    if p.is_null() {
        return None;
    }
    Some(CStr::from_ptr(p).to_string_lossy().into_owned())
}

#[no_mangle]
pub extern "C" fn shelf_store_new(support_dir: *const c_char, max_items: i32) -> *mut Store {
    let dir = unsafe { CStr::from_ptr(support_dir).to_string_lossy() };
    Box::into_raw(Box::new(Store::new(&dir, max_items as usize)))
}

#[no_mangle]
pub extern "C" fn shelf_store_free(store: *mut Store) {
    if !store.is_null() {
        unsafe {
            drop(Box::from_raw(store));
        }
    }
}

#[no_mangle]
pub extern "C" fn shelf_store_get_all(store: *mut Store) -> ShelfClipList {
    let store = unsafe { &*store };
    let clips = store.get_all();

    let mut ffi_clips: Vec<ShelfClip> = clips
        .iter()
        .map(|c| ShelfClip {
            id: to_c_string(&c.id),
            timestamp: c.timestamp,
            content_type: c.content_type as u8,
            text_content: opt_to_c(&c.text_content),
            image_path: opt_to_c(&c.image_path),
            source_app: opt_to_c(&c.source_app),
            is_pinned: c.is_pinned,
            displaced_prev: c.displaced_prev.map(|v| v as i32).unwrap_or(-1),
            displaced_next: c.displaced_next.map(|v| v as i32).unwrap_or(-1),
        })
        .collect();

    let count = ffi_clips.len();
    let ptr = ffi_clips.as_mut_ptr();
    std::mem::forget(ffi_clips);

    ShelfClipList { clips: ptr, count }
}

#[no_mangle]
pub extern "C" fn shelf_clip_list_free(list: ShelfClipList) {
    if list.clips.is_null() {
        return;
    }
    let clips = unsafe { Vec::from_raw_parts(list.clips, list.count, list.count) };
    for clip in clips {
        unsafe {
            if !clip.id.is_null() {
                drop(CString::from_raw(clip.id));
            }
            if !clip.text_content.is_null() {
                drop(CString::from_raw(clip.text_content));
            }
            if !clip.image_path.is_null() {
                drop(CString::from_raw(clip.image_path));
            }
            if !clip.source_app.is_null() {
                drop(CString::from_raw(clip.source_app));
            }
        }
    }
}

#[no_mangle]
pub extern "C" fn shelf_store_add(
    store: *mut Store,
    clip: *const ShelfClip,
    image_data: *const u8,
    image_len: usize,
) -> *mut c_char {
    let store = unsafe { &*store };
    let ffi = unsafe { &*clip };

    let rust_clip = Clip {
        id: unsafe { from_c(ffi.id) }.unwrap_or_default(),
        timestamp: ffi.timestamp,
        content_type: ContentType::from_u8(ffi.content_type),
        text_content: unsafe { from_c(ffi.text_content) },
        image_path: unsafe { from_c(ffi.image_path) },
        source_app: unsafe { from_c(ffi.source_app) },
        is_pinned: ffi.is_pinned,
        displaced_prev: if ffi.displaced_prev >= 0 { Some(ffi.displaced_prev as i64) } else { None },
        displaced_next: if ffi.displaced_next >= 0 { Some(ffi.displaced_next as i64) } else { None },
    };

    let img = if !image_data.is_null() && image_len > 0 {
        Some(unsafe { std::slice::from_raw_parts(image_data, image_len) })
    } else {
        None
    };

    match store.add(&rust_clip, img) {
        Some(path) => to_c_string(&path),
        None => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn shelf_store_delete(store: *mut Store, id: *const c_char) {
    let store = unsafe { &*store };
    let id = unsafe { CStr::from_ptr(id).to_string_lossy() };
    store.delete(&id);
}

#[no_mangle]
pub extern "C" fn shelf_store_toggle_pin(store: *mut Store, id: *const c_char) -> bool {
    let store = unsafe { &*store };
    let id = unsafe { CStr::from_ptr(id).to_string_lossy() };
    store.toggle_pin(&id)
}

#[no_mangle]
pub extern "C" fn shelf_store_clear_all(store: *mut Store) {
    let store = unsafe { &*store };
    store.clear_all();
}

#[no_mangle]
pub extern "C" fn shelf_string_free(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            drop(CString::from_raw(s));
        }
    }
}

#[no_mangle]
pub extern "C" fn shelf_generate_icns(
    svg_path: *const c_char,
    output_path: *const c_char,
    nearest_neighbor: bool,
) -> bool {
    let svg = unsafe { CStr::from_ptr(svg_path).to_string_lossy() };
    let out = unsafe { CStr::from_ptr(output_path).to_string_lossy() };
    icon::generate_icns(&svg, &out, nearest_neighbor)
}
