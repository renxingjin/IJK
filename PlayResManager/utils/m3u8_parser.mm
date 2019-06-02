//
//  m3u8_parser.c
//  IJKMediaDemo
//
//  Created by Gen2 on 2018/12/6.
//  Copyright © 2018年 bilibili. All rights reserved.
//

#include "m3u8_parser.h"



namespace m3u8 {
    
#define MAX_URL_SIZE 4096
#define SPACE_CHARS " \t\r\n"
    
    typedef void (*ff_parse_key_val_cb)(void *context, const char *key,
    int key_len, char **dest, int *dest_len);
    static inline const int av_isspace(int c)
    {
        return c == ' ' || c == '\f' || c == '\n' || c == '\r' || c == '\t' ||
        c == '\v';
    }
    
    static inline const int av_toupper(int c)
    {
        if (c >= 'a' && c <= 'z')
            c ^= 0x20;
        return c;
    }
    
    size_t read_line(const char *s_in, size_t in_size, char *s_out, size_t out_size) {
        size_t offset = 0;
        while (offset < in_size && offset < out_size) {
            char ch = s_in[offset];
            if (ch == '\n' || ch == '\0') {
                s_out[offset] = 0;
                return offset + 1;
            }else {
                s_out[offset] = s_in[offset];
                ++offset;
            }
        }
        return offset;
    }
    
    
    int av_strstart(const char *str, const char *pfx, const char **ptr)
    {
        while (*pfx && *pfx == *str) {
            pfx++;
            str++;
        }
        if (!*pfx && ptr)
            *ptr = str;
        return !*pfx;
    }
    
    void ff_parse_key_value(const char *str, ff_parse_key_val_cb callback_get_buf,
                            void *context)
    {
        const char *ptr = str;
        
        /* Parse key=value pairs. */
        for (;;) {
            const char *key;
            char *dest = NULL, *dest_end;
            int key_len, dest_len = 0;
            
            /* Skip whitespace and potential commas. */
            while (*ptr && (av_isspace(*ptr) || *ptr == ','))
                ptr++;
            if (!*ptr)
                break;
            
            key = ptr;
            
            if (!(ptr = strchr(key, '=')))
                break;
            ptr++;
            key_len = ptr - key;
            
            callback_get_buf(context, key, key_len, &dest, &dest_len);
            dest_end = dest + dest_len - 1;
            
            if (*ptr == '\"') {
                ptr++;
                while (*ptr && *ptr != '\"') {
                    if (*ptr == '\\') {
                        if (!ptr[1])
                            break;
                        if (dest && dest < dest_end)
                            *dest++ = ptr[1];
                        ptr += 2;
                    } else {
                        if (dest && dest < dest_end)
                            *dest++ = *ptr;
                        ptr++;
                    }
                }
                if (*ptr == '\"')
                    ptr++;
            } else {
                for (; *ptr && !(av_isspace(*ptr) || *ptr == ','); ptr++)
                    if (dest && dest < dest_end)
                        *dest++ = *ptr;
            }
            if (dest)
                *dest = 0;
        }
    }
    
    enum KeyType {
        KEY_NONE,
        KEY_AES_128,
        KEY_SAMPLE_AES
    };
    
    struct key_info {
        char uri[MAX_URL_SIZE];
        char method[11];
        char iv[35];
    };
    
    static void handle_key_args(struct key_info *info, const char *key,
                                int key_len, char **dest, int *dest_len)
    {
        if (!strncmp(key, "METHOD=", key_len)) {
            *dest     =        info->method;
            *dest_len = sizeof(info->method);
        } else if (!strncmp(key, "URI=", key_len)) {
            *dest     =        info->uri;
            *dest_len = sizeof(info->uri);
        } else if (!strncmp(key, "IV=", key_len)) {
            *dest     =        info->iv;
            *dest_len = sizeof(info->iv);
        }
    }
    
    
    size_t av_strlcpy(char *dst, const char *src, size_t size)
    {
        size_t len = 0;
        while (++len < size && *src)
            *dst++ = *src++;
        if (len <= size)
            *dst = 0;
        return len + strlen(src) - 1;
    }
    
    size_t av_strlcat(char *dst, const char *src, size_t size)
    {
        size_t len = strlen(dst);
        if (size <= len + 1)
            return len + strlen(src);
        return len + av_strlcpy(dst + len, src, size - len);
    }
    
    int ff_hex_to_data(uint8_t *data, const char *p)
    {
        int c, len, v;
        
        len = 0;
        v   = 1;
        for (;;) {
            p += strspn(p, SPACE_CHARS);
            if (*p == '\0')
                break;
            c = av_toupper((unsigned char) *p++);
            if (c >= '0' && c <= '9')
                c = c - '0';
            else if (c >= 'A' && c <= 'F')
                c = c - 'A' + 10;
            else
                break;
            v = (v << 4) | c;
            if (v & 0x100) {
                if (data)
                    data[len] = v;
                len++;
                v = 1;
            }
        }
        return len;
    }
    
    void ff_make_absolute_url(char *buf, int size, const char *base,
                              const char *rel)
    {
        char *sep, *path_query;
        /* Absolute path, relative to the current server */
        if (base && strstr(base, "://") && rel[0] == '/') {
            if (base != buf)
                av_strlcpy(buf, base, size);
            sep = strstr(buf, "://");
            if (sep) {
                /* Take scheme from base url */
                if (rel[1] == '/') {
                    sep[1] = '\0';
                } else {
                    /* Take scheme and host from base url */
                    sep += 3;
                    sep = strchr(sep, '/');
                    if (sep)
                        *sep = '\0';
                }
            }
            av_strlcat(buf, rel, size);
            return;
        }
        /* If rel actually is an absolute url, just copy it */
        if (!base || strstr(rel, "://") || rel[0] == '/') {
            av_strlcpy(buf, rel, size);
            return;
        }
        if (base != buf)
            av_strlcpy(buf, base, size);
        
        /* Strip off any query string from base */
        path_query = strchr(buf, '?');
        if (path_query)
            *path_query = '\0';
        
        /* Is relative path just a new query part? */
        if (rel[0] == '?') {
            av_strlcat(buf, rel, size);
            return;
        }
        
        /* Remove the file name from the base url */
        sep = strrchr(buf, '/');
        if (sep)
            sep[1] = '\0';
        else
            buf[0] = '\0';
        while (av_strstart(rel, "../", NULL) && sep) {
            /* Remove the path delimiter at the end */
            sep[0] = '\0';
            sep = strrchr(buf, '/');
            /* If the next directory name to pop off is "..", break here */
            if (!strcmp(sep ? &sep[1] : buf, "..")) {
                /* Readd the slash we just removed */
                av_strlcat(buf, "/", size);
                break;
            }
            /* Cut off the directory name */
            if (sep)
                sep[1] = '\0';
            else
                buf[0] = '\0';
            rel += 3;
        }
        av_strlcat(buf, rel, size);
    }
    
#define AV_TIME_BASE            1000000
    
    NSArray<IJKHLSSegment *>* parse_hls(const char *str, size_t size, const char *url) {
        int ret = 0, is_segment = 0, is_variant = 0;
        const char *ptr;
        int64_t duration = 0;
        KeyType key_type = KEY_NONE;
        char key[MAX_URL_SIZE] = "";
        uint8_t iv[16] = "";
        int has_iv = 0;
        int64_t seg_size = -1;
        size_t cursor = 0;
        int64_t seg_offset = 0;
        char line[MAX_URL_SIZE];
        char tmp_str[MAX_URL_SIZE];
        int jack_key_index = -1;
        NSString* jack_key = nil;
        NSMutableArray<IJKHLSSegment*> *segments = [NSMutableArray array];
        
        while (cursor < size) {
            
            cursor += read_line(str + cursor, size - cursor, line, sizeof(line));
            
            if (av_strstart(line, "#EXT-X-STREAM-INF:", &ptr)) {
                is_variant = 1;
                //            memset(&variant_info, 0, sizeof(variant_info));
                //            ff_parse_key_value(ptr, (ff_parse_key_val_cb) handle_variant_args,
                //                               &variant_info);
            } else if (av_strstart(line, "#EXT-X-KEY:", &ptr)) {
                struct key_info info = {{0}};
                ff_parse_key_value(ptr, (ff_parse_key_val_cb) handle_key_args,
                                   &info);
                key_type = KEY_NONE;
                has_iv = 0;
                if (!strcmp(info.method, "AES-128"))
                    key_type = KEY_AES_128;
                if (!strcmp(info.method, "SAMPLE-AES"))
                    key_type = KEY_SAMPLE_AES;
                if (!strncmp(info.iv, "0x", 2) || !strncmp(info.iv, "0X", 2)) {
                    ff_hex_to_data(iv, info.iv + 2);
                    has_iv = 1;
                }
                av_strlcpy(key, info.uri, sizeof(key));
            } else if (av_strstart(line, "#EXT-X-MEDIA:", &ptr)) {
                //                struct rendition_info info = {{0}};
                //                ff_parse_key_value(ptr, (ff_parse_key_val_cb) handle_rendition_args,
                //                                   &info);
                //                new_rendition(c, &info, url);
            } else if (av_strstart(line, "#EXT-X-TARGETDURATION:", &ptr)) {
                //                ret = ensure_playlist(c, &pls, url);
                //                if (ret < 0)
                //                    goto fail;
                //                pls->target_duration = strtoll(ptr, NULL, 10) * AV_TIME_BASE;
            } else if (av_strstart(line, "#EXT-X-MEDIA-SEQUENCE:", &ptr)) {
                //                ret = ensure_playlist(c, &pls, url);
                //                if (ret < 0)
                //                    goto fail;
                //                pls->start_seq_no = atoi(ptr);
            } else if (av_strstart(line, "#EXT-X-PLAYLIST-TYPE:", &ptr)) {
                //                ret = ensure_playlist(c, &pls, url);
                //                if (ret < 0)
                //                    goto fail;
                //                if (!strcmp(ptr, "EVENT"))
                //                    pls->type = PLS_TYPE_EVENT;
                //                else if (!strcmp(ptr, "VOD"))
                //                    pls->type = PLS_TYPE_VOD;
            } else if (av_strstart(line, "#EXT-X-MAP:", &ptr)) {
                //                struct init_section_info info = {{0}};
                //                ret = ensure_playlist(c, &pls, url);
                //                if (ret < 0)
                //                    goto fail;
                //                ff_parse_key_value(ptr, (ff_parse_key_val_cb) handle_init_section_args,
                //                                   &info);
                //                cur_init_section = new_init_section(pls, &info, url);
            } else if (av_strstart(line, "#EXT-X-ENDLIST", &ptr)) {
                //                if (pls)
                //                    pls->finished = 1;
            } else if (av_strstart(line, "#EXTINF:", &ptr)) {
                is_segment = 1;
                duration   = atof(ptr) * AV_TIME_BASE;
            } else if (av_strstart(line, "#EXT-SECRET-KEY-INDEX:", &ptr)) {
                jack_key_index = atoi(ptr);
            } else if (av_strstart(line, "#EXT-SECRET-KEY:", &ptr)) {
                jack_key = [NSString stringWithUTF8String:ptr];
            } else if (av_strstart(line, "#EXT-X-BYTERANGE:", &ptr)) {
                seg_size = strtoll(ptr, NULL, 10);
                ptr = strchr(ptr, '@');
                if (ptr)
                    seg_offset = strtoll(ptr+1, NULL, 10);
            } else if (av_strstart(line, "#", NULL)) {
                continue;
            } else if (line[0]) {
                if (is_variant) {
                    //                    if (!new_variant(c, &variant_info, line, url)) {
                    //                        ret = AVERROR(ENOMEM);
                    //                        goto fail;
                    //                    }
                    is_variant = 0;
                }
                if (is_segment) {
                    IJKHLSSegment *seg = [[IJKHLSSegment alloc] init];
                    seg.duration = duration;
                    seg.type = (IJKHLSSegmentType)key_type;
                    if (jack_key_index >= 0) {
                        seg.secretKeyIndex = jack_key_index;
                        seg.secretKey = jack_key;
                    }
                    if (has_iv) {
                        [seg set_iv:iv];
                    } else {
                        
#   define AV_WB32(p, val) do {                 \
uint32_t d = (val);                     \
((uint8_t*)(p))[3] = (d);               \
((uint8_t*)(p))[2] = (d)>>8;            \
((uint8_t*)(p))[1] = (d)>>16;           \
((uint8_t*)(p))[0] = (d)>>24;           \
} while(0)
                        
                        uint8_t *iv = [seg iv];
                        memset(iv, 0, 16);
                        AV_WB32(iv + 12, segments.count);
                    }
                    
                    if (key_type != KEY_NONE) {
                        ff_make_absolute_url(tmp_str, sizeof(tmp_str), url, key);
                        seg.key = [NSString stringWithUTF8String:tmp_str];
                    } else {
                        seg.key = NULL;
                    }
                    
                    ff_make_absolute_url(tmp_str, sizeof(tmp_str), url, line);
                    seg.url = [NSString stringWithUTF8String:tmp_str];
                    
                    [segments addObject:seg];
                    is_segment = 0;
                    
                    seg.size = seg_size;
                    if (seg_size >= 0) {
                        seg.urlOffset = seg_offset;
                        seg_offset += seg_size;
                        seg_size = -1;
                    } else {
                        seg.urlOffset = 0;
                        seg_offset = 0;
                    }
                    
                }
            }
        }
        return segments;
    }
}
