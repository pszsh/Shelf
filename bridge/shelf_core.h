#ifndef SHELF_CORE_H
#define SHELF_CORE_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

typedef struct ShelfStore ShelfStore;

typedef struct {
    char *id;
    double timestamp;
    uint8_t content_type;
    char *text_content;
    char *image_path;
    char *source_app;
    bool is_pinned;
    int32_t displaced_prev;
    int32_t displaced_next;
    char *source_path;
} ShelfClip;

typedef struct {
    ShelfClip *clips;
    size_t count;
} ShelfClipList;

ShelfStore *shelf_store_new(const char *support_dir, int max_items);
void shelf_store_free(ShelfStore *store);

ShelfClipList shelf_store_get_all(ShelfStore *store);
void shelf_clip_list_free(ShelfClipList list);

char *shelf_store_add(ShelfStore *store, const ShelfClip *clip,
                      const uint8_t *image_data, size_t image_len);
void shelf_store_delete(ShelfStore *store, const char *id);
bool shelf_store_toggle_pin(ShelfStore *store, const char *id);
void shelf_store_clear_all(ShelfStore *store);

void shelf_string_free(char *s);

bool shelf_generate_icns(const char *svg_path, const char *output_path,
                         bool nearest_neighbor);

#endif
