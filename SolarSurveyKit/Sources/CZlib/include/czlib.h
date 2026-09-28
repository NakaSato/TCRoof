#ifndef CZLIB_H
#define CZLIB_H
#include <stddef.h>
#include <stdint.h>

/// Raw DEFLATE (no zlib header), as stored in ZIP entries. Returns 0 on success.
int cz_inflate_raw(const uint8_t *src, size_t src_len, uint8_t *dst, size_t dst_len, size_t *out_len);
int cz_deflate_raw(const uint8_t *src, size_t src_len, uint8_t *dst, size_t dst_len, size_t *out_len, int level);
size_t cz_deflate_bound(size_t src_len);
uint32_t cz_crc32(uint32_t crc, const uint8_t *buf, size_t len);

#endif
