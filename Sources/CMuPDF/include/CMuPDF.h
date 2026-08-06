#ifndef PAPERLIGHT_C_MUPDF_H
#define PAPERLIGHT_C_MUPDF_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct PLDocument PLDocument;

enum {
    PL_ERROR_NONE = 0,
    PL_ERROR_GENERIC = 1,
    PL_ERROR_PASSWORD_REQUIRED = 2,
    PL_ERROR_INCORRECT_PASSWORD = 3
};

typedef struct {
    float x;
    float y;
    float width;
    float height;
} PLRect;

typedef struct {
    float width;
    float height;
} PLPageSize;

typedef struct {
    PLRect rect;
    int target_page;
    float target_x;
    float target_y;
    char *uri;
} PLLink;

typedef struct {
    int width;
    int height;
    int stride;
    unsigned char *samples;
} PLBitmap;

typedef struct {
    uint32_t scalar;
    PLRect rect;
    int line_index;
} PLTextGlyph;

typedef struct {
    PLRect rect;
    int mark;
} PLSearchQuad;

typedef struct {
    char *title;
    int parent_index;
    int target_page;
    float target_x;
    float target_y;
    int is_open;
} PLOutlineEntry;

PLDocument *pl_document_open(
    const char *path,
    const char *password,
    size_t store_limit,
    int *error_code,
    char *error,
    size_t error_capacity
);

void pl_document_close(PLDocument *document);
int pl_document_page_count(const PLDocument *document);

int pl_document_page(
    PLDocument *document,
    int page_index,
    PLPageSize *page_size,
    PLLink **links,
    size_t *link_count,
    char *error,
    size_t error_capacity
);

void pl_links_free(PLLink *links, size_t count);

int pl_document_outline(
    PLDocument *document,
    PLOutlineEntry **entries,
    size_t *entry_count,
    char *error,
    size_t error_capacity
);

void pl_outline_entries_free(PLOutlineEntry *entries, size_t count);

int pl_document_render(
    PLDocument *document,
    int page_index,
    float scale,
    PLBitmap *bitmap,
    char *error,
    size_t error_capacity
);

void pl_bitmap_free(PLBitmap *bitmap);

int pl_document_text(
    PLDocument *document,
    int page_index,
    PLTextGlyph **glyphs,
    size_t *glyph_count,
    char *error,
    size_t error_capacity
);

void pl_text_glyphs_free(PLTextGlyph *glyphs);

int pl_document_search_page(
    PLDocument *document,
    int page_index,
    const char *query,
    PLSearchQuad **quads,
    size_t *quad_count,
    char *error,
    size_t error_capacity
);

void pl_search_quads_free(PLSearchQuad *quads);

int pl_document_add_highlights(
    PLDocument *document,
    int page_index,
    const PLRect *rects,
    size_t rect_count,
    const char *contents,
    char *error,
    size_t error_capacity
);

int pl_document_add_note(
    PLDocument *document,
    int page_index,
    float x,
    float y,
    const char *contents,
    char *error,
    size_t error_capacity
);

int pl_document_undo(
    PLDocument *document,
    char *error,
    size_t error_capacity
);

int pl_document_save(
    PLDocument *document,
    const char *path,
    char *error,
    size_t error_capacity
);

void pl_document_empty_store(PLDocument *document);

#ifdef __cplusplus
}
#endif

#endif
