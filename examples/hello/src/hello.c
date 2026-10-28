#include "pg_prelude.h"

PG_MODULE_MAGIC;

PG_FUNCTION_INFO_V1(hello);
Datum hello(PG_FUNCTION_ARGS){
  text *input = PG_GETARG_TEXT_PP(0);

  StringInfoData buf;
  initStringInfo(&buf);

  // ASAN should flag this
  if (getenv("HELLO_OOB_WRITE")) {
    char *buf2 = (char *)malloc(4);
    buf2[5] = 'A'; // Writing past the 4-byte heap buffer
    free(buf2);
  }
 
  // LSAN should flag this
  if (getenv("HELLO_MEM_LEAK")) {
    char *s = malloc(100);
    strcpy(s, "Hello world!");
    printf("string is: %s\n", s);
  }
 
  // UBSAN should flag this
  if (getenv("HELLO_DIV_BY_ZERO")) {
    int a = 10;
    int b = 0;
    int c = a / b; // Division by zero
    printf("%d\n", c);
  }

  appendStringInfoString(&buf, "hello ");
  appendBinaryStringInfo(&buf, VARDATA_ANY(input), VARSIZE_ANY_EXHDR(input));

  PG_RETURN_TEXT_P(cstring_to_text_with_len(buf.data, buf.len));
}
