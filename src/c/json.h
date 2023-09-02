#include <stdbool.h>
#include <stdint.h>

typedef void *(*alloc_t)(void *, unsigned, uint8_t, unsigned);
typedef bool (*resize_t)(void *, void *, uint8_t, unsigned, unsigned);
typedef void (*free_t)(void *, void *, uint8_t, unsigned);
void *jp_parser_create(void *ctx, alloc_t alloc, resize_t resize, free_t free);
void jp_parser_destroy(void *j);
void *jp_parser_parse(void *j, char *str);
int jp_json_get_type(void *res);
void *jp_json_get_data(void *res);
void *jp_json_arr_get(void *j, unsigned i);
unsigned long jp_json_arr_len(void *res);
void jp_json_debug(void *res);
void jp_json_destroy(void *j, void *res);