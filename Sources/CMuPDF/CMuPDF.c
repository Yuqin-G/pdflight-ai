#include "CMuPDF.h"

#include <mupdf/fitz.h>
#include <mupdf/pdf.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct PLDocument {
    fz_context *context;
    fz_document *document;
    char *source_path;
    int page_count;
};

static void pl_set_error(char *error, size_t capacity, const char *message)
{
    if (!error || capacity == 0)
        return;
    snprintf(error, capacity, "%s", message ? message : "Unknown MuPDF error");
}

static int pl_valid_page(const PLDocument *document, int page_index)
{
    return document && page_index >= 0 && page_index < document->page_count;
}

PLDocument *
pl_document_open(
    const char *path,
    const char *password,
    size_t store_limit,
    int *error_code,
    char *error,
    size_t error_capacity)
{
    PLDocument *result = NULL;
    fz_context *context = NULL;
    fz_document *document = NULL;

    if (error_code)
        *error_code = PL_ERROR_NONE;
    if (!path) {
        if (error_code)
            *error_code = PL_ERROR_GENERIC;
        pl_set_error(error, error_capacity, "Missing PDF path");
        return NULL;
    }

    context = fz_new_context(NULL, NULL, store_limit);
    if (!context) {
        if (error_code)
            *error_code = PL_ERROR_GENERIC;
        pl_set_error(error, error_capacity, "Could not create MuPDF context");
        return NULL;
    }

    fz_var(document);
    fz_try(context) {
        fz_register_document_handlers(context);
        document = fz_open_document(context, path);
        if (fz_needs_password(context, document)) {
            if (!password) {
                if (error_code)
                    *error_code = PL_ERROR_PASSWORD_REQUIRED;
                fz_throw(context, FZ_ERROR_ARGUMENT, "This PDF requires a password");
            }
            if (!fz_authenticate_password(context, document, password)) {
                if (error_code)
                    *error_code = PL_ERROR_INCORRECT_PASSWORD;
                fz_throw(context, FZ_ERROR_ARGUMENT, "The PDF password is incorrect");
            }
        }

        pdf_document *pdf = pdf_specifics(context, document);
        if (!pdf)
            fz_throw(context, FZ_ERROR_UNSUPPORTED, "Document is not an editable PDF");
        pdf_enable_journal(context, pdf);

        result = calloc(1, sizeof(*result));
        if (!result)
            fz_throw(context, FZ_ERROR_SYSTEM, "Out of memory");
        result->source_path = strdup(path);
        if (!result->source_path)
            fz_throw(context, FZ_ERROR_SYSTEM, "Out of memory");
        result->context = context;
        result->document = document;
        result->page_count = fz_count_pages(context, document);
    }
    fz_catch(context) {
        if (error_code && *error_code == PL_ERROR_NONE)
            *error_code = PL_ERROR_GENERIC;
        pl_set_error(error, error_capacity, fz_caught_message(context));
        fz_drop_document(context, document);
        if (result) {
            free(result->source_path);
            free(result);
        }
        fz_drop_context(context);
        return NULL;
    }

    return result;
}

void
pl_document_close(PLDocument *document)
{
    if (!document)
        return;
    fz_drop_document(document->context, document->document);
    fz_drop_context(document->context);
    free(document->source_path);
    free(document);
}

int
pl_document_page_count(const PLDocument *document)
{
    return document ? document->page_count : 0;
}

void
pl_links_free(PLLink *links, size_t count)
{
    if (!links)
        return;
    for (size_t index = 0; index < count; ++index)
        free(links[index].uri);
    free(links);
}

static size_t
pl_outline_count(const fz_outline *outline)
{
    size_t count = 0;
    while (outline) {
        ++count;
        if (outline->down)
            count += pl_outline_count(outline->down);
        outline = outline->next;
    }
    return count;
}

static void
pl_copy_outline(
    fz_context *context,
    fz_document *document,
    const fz_outline *outline,
    int parent_index,
    PLOutlineEntry *entries,
    size_t *next_index)
{
    while (outline) {
        size_t current_index = (*next_index)++;
        PLOutlineEntry *entry = &entries[current_index];
        entry->title = strdup(outline->title ? outline->title : "");
        if (!entry->title)
            fz_throw(context, FZ_ERROR_SYSTEM, "Out of memory");
        entry->parent_index = parent_index;
        entry->target_page = -1;
        entry->target_x = outline->x;
        entry->target_y = outline->y;
        entry->is_open = outline->is_open;

        fz_location location = outline->page;
        if ((location.chapter < 0 || location.page < 0) &&
            outline->uri && !fz_is_external_link(context, outline->uri)) {
            location = fz_resolve_link(
                context,
                document,
                outline->uri,
                &entry->target_x,
                &entry->target_y);
        }
        if (location.chapter >= 0 && location.page >= 0)
            entry->target_page = fz_page_number_from_location(context, document, location);

        if (outline->down)
            pl_copy_outline(
                context,
                document,
                outline->down,
                (int)current_index,
                entries,
                next_index);
        outline = outline->next;
    }
}

void
pl_outline_entries_free(PLOutlineEntry *entries, size_t count)
{
    if (!entries)
        return;
    for (size_t index = 0; index < count; ++index)
        free(entries[index].title);
    free(entries);
}

int
pl_document_outline(
    PLDocument *document,
    PLOutlineEntry **output_entries,
    size_t *output_entry_count,
    char *error,
    size_t error_capacity)
{
    fz_outline *outline = NULL;
    PLOutlineEntry *copied_entries = NULL;
    size_t count = 0;

    if (!document || !output_entries || !output_entry_count) {
        pl_set_error(error, error_capacity, "Missing outline output storage");
        return 0;
    }
    *output_entries = NULL;
    *output_entry_count = 0;

    fz_context *context = document->context;
    fz_var(outline);
    fz_var(copied_entries);
    fz_try(context) {
        outline = fz_load_outline(context, document->document);
        count = pl_outline_count(outline);
        if (count > 10000)
            fz_throw(context, FZ_ERROR_LIMIT, "Document outline is too large");
        if (count > 0) {
            copied_entries = calloc(count, sizeof(*copied_entries));
            if (!copied_entries)
                fz_throw(context, FZ_ERROR_SYSTEM, "Out of memory");
            size_t next_index = 0;
            pl_copy_outline(
                context,
                document->document,
                outline,
                -1,
                copied_entries,
                &next_index);
        }
    }
    fz_always(context) {
        fz_drop_outline(context, outline);
    }
    fz_catch(context) {
        pl_set_error(error, error_capacity, fz_caught_message(context));
        pl_outline_entries_free(copied_entries, count);
        return 0;
    }

    *output_entries = copied_entries;
    *output_entry_count = count;
    return 1;
}

int
pl_document_page(
    PLDocument *document,
    int page_index,
    PLPageSize *page_size,
    PLLink **output_links,
    size_t *output_link_count,
    char *error,
    size_t error_capacity)
{
    fz_context *context;
    fz_page *page = NULL;
    fz_link *links = NULL;
    PLLink *copied_links = NULL;
    size_t count = 0;

    if (!pl_valid_page(document, page_index)) {
        pl_set_error(error, error_capacity, "Page index is out of range");
        return 0;
    }
    if (!page_size || !output_links || !output_link_count) {
        pl_set_error(error, error_capacity, "Missing page output storage");
        return 0;
    }

    *output_links = NULL;
    *output_link_count = 0;
    context = document->context;
    fz_var(page);
    fz_var(links);
    fz_var(copied_links);

    fz_try(context) {
        page = fz_load_page(context, document->document, page_index);
        fz_rect bounds = fz_bound_page(context, page);
        page_size->width = bounds.x1 - bounds.x0;
        page_size->height = bounds.y1 - bounds.y0;

        links = fz_load_links(context, page);
        for (fz_link *link = links; link; link = link->next)
            ++count;

        if (count > 0) {
            copied_links = calloc(count, sizeof(*copied_links));
            if (!copied_links)
                fz_throw(context, FZ_ERROR_SYSTEM, "Out of memory");
        }

        size_t index = 0;
        for (fz_link *link = links; link; link = link->next, ++index) {
            copied_links[index].rect.x = link->rect.x0;
            copied_links[index].rect.y = link->rect.y0;
            copied_links[index].rect.width = link->rect.x1 - link->rect.x0;
            copied_links[index].rect.height = link->rect.y1 - link->rect.y0;
            copied_links[index].target_page = -1;

            if (fz_is_external_link(context, link->uri)) {
                copied_links[index].uri = strdup(link->uri);
                if (!copied_links[index].uri)
                    fz_throw(context, FZ_ERROR_SYSTEM, "Out of memory");
            } else {
                float x = 0;
                float y = 0;
                fz_location location = fz_resolve_link(context, document->document, link->uri, &x, &y);
                if (location.chapter >= 0 && location.page >= 0) {
                    copied_links[index].target_page =
                        fz_page_number_from_location(context, document->document, location);
                    copied_links[index].target_x = x;
                    copied_links[index].target_y = y;
                }
            }
        }
    }
    fz_always(context) {
        fz_drop_link(context, links);
        fz_drop_page(context, page);
    }
    fz_catch(context) {
        pl_set_error(error, error_capacity, fz_caught_message(context));
        pl_links_free(copied_links, count);
        return 0;
    }

    *output_links = copied_links;
    *output_link_count = count;
    return 1;
}

int
pl_document_render(
    PLDocument *document,
    int page_index,
    float scale,
    PLBitmap *bitmap,
    char *error,
    size_t error_capacity)
{
    fz_context *context;
    fz_page *page = NULL;
    fz_pixmap *pixmap = NULL;
    fz_device *device = NULL;

    if (!pl_valid_page(document, page_index)) {
        pl_set_error(error, error_capacity, "Page index is out of range");
        return 0;
    }
    if (!bitmap || scale <= 0 || scale > 16) {
        pl_set_error(error, error_capacity, "Invalid render scale");
        return 0;
    }
    memset(bitmap, 0, sizeof(*bitmap));

    context = document->context;
    fz_var(page);
    fz_var(pixmap);
    fz_var(device);

    fz_try(context) {
        page = fz_load_page(context, document->document, page_index);
        fz_matrix transform = fz_scale(scale, scale);
        fz_rect bounds = fz_transform_rect(fz_bound_page(context, page), transform);
        fz_irect pixel_bounds = fz_round_rect(bounds);
        long long pixel_count =
            (long long)(pixel_bounds.x1 - pixel_bounds.x0) *
            (long long)(pixel_bounds.y1 - pixel_bounds.y0);
        if (pixel_count <= 0 || pixel_count > 120000000)
            fz_throw(context, FZ_ERROR_LIMIT, "Rendered page is too large");

        pixmap = fz_new_pixmap_with_bbox(
            context, fz_device_rgb(context), pixel_bounds, NULL, 0);
        fz_clear_pixmap_with_value(context, pixmap, 255);
        device = fz_new_draw_device(context, fz_identity, pixmap);
        fz_run_page(context, page, device, transform, NULL);
        fz_close_device(context, device);

        bitmap->width = fz_pixmap_width(context, pixmap);
        bitmap->height = fz_pixmap_height(context, pixmap);
        bitmap->stride = fz_pixmap_stride(context, pixmap);
        size_t byte_count = (size_t)bitmap->stride * (size_t)bitmap->height;
        bitmap->samples = malloc(byte_count);
        if (!bitmap->samples)
            fz_throw(context, FZ_ERROR_SYSTEM, "Out of memory");
        memcpy(bitmap->samples, fz_pixmap_samples(context, pixmap), byte_count);
    }
    fz_always(context) {
        fz_drop_device(context, device);
        fz_drop_pixmap(context, pixmap);
        fz_drop_page(context, page);
    }
    fz_catch(context) {
        pl_set_error(error, error_capacity, fz_caught_message(context));
        pl_bitmap_free(bitmap);
        return 0;
    }

    return 1;
}

void
pl_bitmap_free(PLBitmap *bitmap)
{
    if (!bitmap)
        return;
    free(bitmap->samples);
    memset(bitmap, 0, sizeof(*bitmap));
}

int
pl_document_text(
    PLDocument *document,
    int page_index,
    PLTextGlyph **output_glyphs,
    size_t *output_glyph_count,
    char *error,
    size_t error_capacity)
{
    fz_context *context;
    fz_page *page = NULL;
    fz_stext_page *text = NULL;
    PLTextGlyph *copied_glyphs = NULL;
    size_t count = 0;

    if (!pl_valid_page(document, page_index)) {
        pl_set_error(error, error_capacity, "Page index is out of range");
        return 0;
    }
    if (!output_glyphs || !output_glyph_count) {
        pl_set_error(error, error_capacity, "Missing text output storage");
        return 0;
    }
    *output_glyphs = NULL;
    *output_glyph_count = 0;

    context = document->context;
    fz_var(page);
    fz_var(text);
    fz_var(copied_glyphs);
    fz_try(context) {
        page = fz_load_page(context, document->document, page_index);
        text = fz_new_stext_page_from_page(context, page, NULL);
        for (fz_stext_block *block = text->first_block; block; block = block->next) {
            if (block->type != FZ_STEXT_BLOCK_TEXT)
                continue;
            for (fz_stext_line *line = block->u.t.first_line; line; line = line->next)
                for (fz_stext_char *character = line->first_char; character; character = character->next)
                    ++count;
        }

        if (count > 0) {
            copied_glyphs = calloc(count, sizeof(*copied_glyphs));
            if (!copied_glyphs)
                fz_throw(context, FZ_ERROR_SYSTEM, "Out of memory");
        }

        size_t index = 0;
        int line_index = 0;
        for (fz_stext_block *block = text->first_block; block; block = block->next) {
            if (block->type != FZ_STEXT_BLOCK_TEXT)
                continue;
            for (fz_stext_line *line = block->u.t.first_line; line; line = line->next, ++line_index) {
                for (fz_stext_char *character = line->first_char; character; character = character->next) {
                    fz_rect rect = fz_rect_from_quad(character->quad);
                    copied_glyphs[index].scalar = character->c >= 0 ? (uint32_t)character->c : 0xfffd;
                    copied_glyphs[index].rect.x = rect.x0;
                    copied_glyphs[index].rect.y = rect.y0;
                    copied_glyphs[index].rect.width = rect.x1 - rect.x0;
                    copied_glyphs[index].rect.height = rect.y1 - rect.y0;
                    copied_glyphs[index].line_index = line_index;
                    ++index;
                }
            }
        }
    }
    fz_always(context) {
        fz_drop_stext_page(context, text);
        fz_drop_page(context, page);
    }
    fz_catch(context) {
        pl_set_error(error, error_capacity, fz_caught_message(context));
        free(copied_glyphs);
        return 0;
    }

    *output_glyphs = copied_glyphs;
    *output_glyph_count = count;
    return 1;
}

void
pl_text_glyphs_free(PLTextGlyph *glyphs)
{
    free(glyphs);
}

int
pl_document_search_page(
    PLDocument *document,
    int page_index,
    const char *query,
    PLSearchQuad **output_quads,
    size_t *output_quad_count,
    char *error,
    size_t error_capacity)
{
    enum { PL_SEARCH_LIMIT = 4096 };
    fz_context *context;
    fz_page *page = NULL;
    int *marks = NULL;
    fz_quad *bounds = NULL;
    PLSearchQuad *copied_quads = NULL;
    int count = 0;

    if (!pl_valid_page(document, page_index)) {
        pl_set_error(error, error_capacity, "Page index is out of range");
        return 0;
    }
    if (!query || !output_quads || !output_quad_count) {
        pl_set_error(error, error_capacity, "Missing search input or output storage");
        return 0;
    }
    *output_quads = NULL;
    *output_quad_count = 0;

    context = document->context;
    fz_var(page);
    fz_var(marks);
    fz_var(bounds);
    fz_var(copied_quads);
    fz_try(context) {
        marks = calloc(PL_SEARCH_LIMIT, sizeof(*marks));
        bounds = calloc(PL_SEARCH_LIMIT, sizeof(*bounds));
        if (!marks || !bounds)
            fz_throw(context, FZ_ERROR_SYSTEM, "Out of memory");

        page = fz_load_page(context, document->document, page_index);
        count = fz_search_page(context, page, query, marks, bounds, PL_SEARCH_LIMIT);
        if (count > 0) {
            copied_quads = calloc((size_t)count, sizeof(*copied_quads));
            if (!copied_quads)
                fz_throw(context, FZ_ERROR_SYSTEM, "Out of memory");
        }
        for (int index = 0; index < count; ++index) {
            fz_rect rect = fz_rect_from_quad(bounds[index]);
            copied_quads[index].rect.x = rect.x0;
            copied_quads[index].rect.y = rect.y0;
            copied_quads[index].rect.width = rect.x1 - rect.x0;
            copied_quads[index].rect.height = rect.y1 - rect.y0;
            copied_quads[index].mark = marks[index];
        }
    }
    fz_always(context) {
        free(marks);
        free(bounds);
        fz_drop_page(context, page);
    }
    fz_catch(context) {
        pl_set_error(error, error_capacity, fz_caught_message(context));
        free(copied_quads);
        return 0;
    }

    *output_quads = copied_quads;
    *output_quad_count = (size_t)count;
    return 1;
}

void
pl_search_quads_free(PLSearchQuad *quads)
{
    free(quads);
}

int
pl_document_add_highlights(
    PLDocument *document,
    int page_index,
    const PLRect *rects,
    size_t rect_count,
    const char *contents,
    char *error,
    size_t error_capacity)
{
    fz_context *context;
    fz_page *page = NULL;
    pdf_annot *annotation = NULL;
    int operation_started = 0;

    if (!pl_valid_page(document, page_index)) {
        pl_set_error(error, error_capacity, "Page index is out of range");
        return 0;
    }
    if (!rects || rect_count == 0) {
        pl_set_error(error, error_capacity, "Highlight selection is empty");
        return 0;
    }
    for (size_t index = 0; index < rect_count; ++index) {
        if (rects[index].width <= 0 || rects[index].height <= 0) {
            pl_set_error(error, error_capacity, "Highlight rectangle is empty");
            return 0;
        }
    }

    context = document->context;
    fz_var(page);
    fz_var(annotation);
    fz_var(operation_started);
    fz_try(context) {
        pdf_document *pdf = pdf_specifics(context, document->document);
        if (!pdf)
            fz_throw(context, FZ_ERROR_UNSUPPORTED, "Document is not an editable PDF");

        pdf_begin_operation(context, pdf, "Highlight Selection");
        operation_started = 1;

        page = fz_load_page(context, document->document, page_index);
        pdf_page *pdf_page = pdf_page_from_fz_page(context, page);
        for (size_t index = 0; index < rect_count; ++index) {
            PLRect rect = rects[index];
            annotation = pdf_create_annot(context, pdf_page, PDF_ANNOT_HIGHLIGHT);

            float x0 = rect.x;
            float y0 = rect.y;
            float x1 = rect.x + rect.width;
            float y1 = rect.y + rect.height;
            fz_quad quad = fz_make_quad(x0, y0, x1, y0, x0, y1, x1, y1);
            pdf_set_annot_quad_points(context, annotation, 1, &quad);
            if (contents && contents[0] != '\0')
                pdf_set_annot_contents(context, annotation, contents);
            pdf_update_annot(context, annotation);
            pdf_drop_annot(context, annotation);
            annotation = NULL;
        }
        pdf_end_operation(context, pdf);
        operation_started = 0;
    }
    fz_always(context) {
        pdf_drop_annot(context, annotation);
        fz_drop_page(context, page);
    }
    fz_catch(context) {
        if (operation_started)
            pdf_abandon_operation(context, pdf_specifics(context, document->document));
        pl_set_error(error, error_capacity, fz_caught_message(context));
        return 0;
    }

    return 1;
}

int
pl_document_add_note(
    PLDocument *document,
    int page_index,
    float x,
    float y,
    const char *contents,
    char *error,
    size_t error_capacity)
{
    fz_context *context;
    fz_page *page = NULL;
    pdf_annot *annotation = NULL;
    int operation_started = 0;

    if (!pl_valid_page(document, page_index)) {
        pl_set_error(error, error_capacity, "Page index is out of range");
        return 0;
    }
    if (!contents || contents[0] == '\0') {
        pl_set_error(error, error_capacity, "Note text is empty");
        return 0;
    }

    context = document->context;
    fz_var(page);
    fz_var(annotation);
    fz_var(operation_started);
    fz_try(context) {
        pdf_document *pdf = pdf_specifics(context, document->document);
        if (!pdf)
            fz_throw(context, FZ_ERROR_UNSUPPORTED, "Document is not an editable PDF");

        pdf_begin_operation(context, pdf, "Add Text Note");
        operation_started = 1;

        page = fz_load_page(context, document->document, page_index);
        pdf_page *pdf_page = pdf_page_from_fz_page(context, page);
        annotation = pdf_create_annot(context, pdf_page, PDF_ANNOT_TEXT);
        pdf_set_annot_rect(context, annotation, fz_make_rect(x, y, x + 20, y + 20));
        pdf_set_annot_contents(context, annotation, contents);
        pdf_set_annot_icon_name(context, annotation, "Comment");
        pdf_update_annot(context, annotation);
        pdf_end_operation(context, pdf);
        operation_started = 0;
    }
    fz_always(context) {
        pdf_drop_annot(context, annotation);
        fz_drop_page(context, page);
    }
    fz_catch(context) {
        if (operation_started)
            pdf_abandon_operation(context, pdf_specifics(context, document->document));
        pl_set_error(error, error_capacity, fz_caught_message(context));
        return 0;
    }

    return 1;
}

int
pl_document_undo(
    PLDocument *document,
    char *error,
    size_t error_capacity)
{
    if (!document) {
        pl_set_error(error, error_capacity, "Missing document");
        return 0;
    }

    fz_context *context = document->context;
    fz_try(context) {
        pdf_document *pdf = pdf_specifics(context, document->document);
        if (!pdf)
            fz_throw(context, FZ_ERROR_UNSUPPORTED, "Document is not an editable PDF");
        if (!pdf_can_undo(context, pdf))
            fz_throw(context, FZ_ERROR_ARGUMENT, "There is no annotation to undo");
        pdf_undo(context, pdf);
    }
    fz_catch(context) {
        pl_set_error(error, error_capacity, fz_caught_message(context));
        return 0;
    }

    return 1;
}

int
pl_document_save(
    PLDocument *document,
    const char *path,
    char *error,
    size_t error_capacity)
{
    if (!document || !path) {
        pl_set_error(error, error_capacity, "Missing save path");
        return 0;
    }

    fz_context *context = document->context;
    fz_try(context) {
        pdf_document *pdf = pdf_specifics(context, document->document);
        if (!pdf)
            fz_throw(context, FZ_ERROR_UNSUPPORTED, "Document is not an editable PDF");

        pdf_write_options options = pdf_default_write_options;
        if (strcmp(path, document->source_path) == 0)
            options.do_incremental = 1;
        else {
            options.do_compress = 1;
            options.do_compress_images = 1;
            options.do_compress_fonts = 1;
        }
        pdf_save_document(context, pdf, path, &options);
    }
    fz_catch(context) {
        pl_set_error(error, error_capacity, fz_caught_message(context));
        return 0;
    }

    return 1;
}

void
pl_document_empty_store(PLDocument *document)
{
    if (!document)
        return;
    fz_empty_store(document->context);
}
