#include "json.h"
#include <assert.h>
#include <stdio.h>

enum jp_json_type {
  JsonBool = 0,
  JsonInt = 1,
  JsonFloat = 2,
  JsonNull = 3,
  JsonArray = 4,
  JsonString = 5,
  JsonObject = 6,
};
int main() {
  void *j = jp_parser_create(NULL, NULL, NULL, NULL);
  void *res = jp_parser_parse(j, "[1.0, \"hello world\", true]");
  assert(JsonArray == jp_json_get_type(res));
  printf("arr length: %lu\n", jp_json_arr_len(res));

  void *r0 = jp_json_arr_get(res, 0);
  assert(JsonFloat == jp_json_get_type(r0));
  printf("[0]: %f\n", *(double *)jp_json_get_data(r0));

  void *r1 = jp_json_arr_get(res, 1);
  assert(JsonString == jp_json_get_type(r1));
  printf("[1]: %s\n", (char *)jp_json_get_data(r1));

  void *r2 = jp_json_arr_get(res, 2);
  assert(JsonBool == jp_json_get_type(r2));
  printf("[2]: %s\n", *(int *)jp_json_get_data(r2) ? "true" : "false");

  jp_json_destroy(j, res);
  jp_parser_destroy(j);
  return 0;
}