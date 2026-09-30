#include "czlib.h"
#include <zlib.h>
#include <string.h>

int cz_inflate_raw(const uint8_t *src, size_t src_len, uint8_t *dst, size_t dst_len, size_t *out_len) {
    z_stream s; memset(&s, 0, sizeof s);
    if (inflateInit2(&s, -MAX_WBITS) != Z_OK) return -1;
    s.next_in = (Bytef *)src; s.avail_in = (uInt)src_len;
    s.next_out = dst; s.avail_out = (uInt)dst_len;
    int r = inflate(&s, Z_FINISH);
    *out_len = s.total_out;
    inflateEnd(&s);
    return (r == Z_STREAM_END) ? 0 : -2;
}

int cz_deflate_raw(const uint8_t *src, size_t src_len, uint8_t *dst, size_t dst_len, size_t *out_len, int level) {
    z_stream s; memset(&s, 0, sizeof s);
    if (deflateInit2(&s, level, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY) != Z_OK) return -1;
    s.next_in = (Bytef *)src; s.avail_in = (uInt)src_len;
    s.next_out = dst; s.avail_out = (uInt)dst_len;
    int r = deflate(&s, Z_FINISH);
    *out_len = s.total_out;
    deflateEnd(&s);
    return (r == Z_STREAM_END) ? 0 : -2;
}

size_t cz_deflate_bound(size_t src_len) { return compressBound((uLong)src_len) + 64; }

uint32_t cz_crc32(uint32_t crc, const uint8_t *buf, size_t len) { return (uint32_t)crc32((uLong)crc, buf, (uInt)len); }
