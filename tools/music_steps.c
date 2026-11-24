/* Development tool (not part of the app): prints every 1/70 s step of one of the demo's songs as
   libopenmpt plays it: step, order, row, tempo, speed. Used by tools/demo_timeline.py.

   Build (after ./build.sh has built libopenmpt):
     clang -O2 -o build/music_steps tools/music_steps.c -IThirdParty/libopenmpt/libopenmpt \
           -Lbuild/libopenmpt/src/bin -lopenmpt -lc++
   Run on an UNSCRAMBLED song (SRMetal --music-info --write <folder> makes them):
     build/music_steps <song.s3m> <tempo override, 0 for none> <start order>
   The demo loaded MUSIC0 with its starting tempo changed to 120 (MAIN/STARTMUS.C: module[50]=0x78). */
#include <stdio.h>
#include <stdlib.h>
#include "libopenmpt.h"
int main(int argc, char **argv) {
  FILE *f = fopen(argv[1], "rb"); fseek(f, 0, SEEK_END); long n = ftell(f); rewind(f);
  unsigned char *d = malloc(n); fread(d, 1, n, f); fclose(f);
  int tempo = atoi(argv[2]); if (tempo) d[0x32] = tempo;
  openmpt_module *m = openmpt_module_create_from_memory2(d, n, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
  openmpt_module_select_subsong(m, -1);
  int start = atoi(argv[3]); if (start) openmpt_module_set_position_order_row(m, start, 0);
  static float buf[630 * 2];
  for (long step = 0; step < 70L * 700; step++) {
    printf("%ld %d %d %.3f %d\n", step, openmpt_module_get_current_order(m), openmpt_module_get_current_row(m),
           openmpt_module_get_current_tempo2(m), openmpt_module_get_current_speed(m));
    if (openmpt_module_read_interleaved_float_stereo(m, 44100, 630, buf) == 0) break;
  }
  return 0;
}
