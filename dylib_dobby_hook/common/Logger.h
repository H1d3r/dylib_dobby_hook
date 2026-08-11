//
//  Header.h
//  dylib_dobby_hook
//
//  Created by voidm on 2024/10/16.
//

#ifndef Header_h
#define Header_h

//#ifdef DEBUG
//#warning DEBUG is defined
//#else
//#warning DEBUG is NOT defined
//#endif

#ifdef DEBUG
#define NSLogger(fmt, ...)                      \
    NSLog((@"🔍 Hack Debug: %s [:%d] " fmt), \
        __func__,                               \
        __LINE__, ##__VA_ARGS__)
#else
// if (0) 分支保留参数 "被引用", Release 下消除仅日志用变量的 unused 告警
#define NSLogger(fmt, ...)                                         \
    do {                                                           \
        if (0) {                                                   \
            NSLog((@"🔍 Hack Debug: %s [:%d] " fmt),               \
                  __func__, __LINE__, ##__VA_ARGS__);              \
        }                                                          \
    } while (0)
#endif

#ifdef DEBUG
#define CLogger(fmt, ...)                          \
    printf("🔍 Hack Debug: %s [:%d] " fmt "\n", \
        __PRETTY_FUNCTION__,                       \
        __LINE__, ##__VA_ARGS__)
#else
#define CLogger(fmt, ...)                                  \
    do {                                                   \
        if (0) {                                           \
            printf("🔍 Hack Debug: %s [:%d] " fmt "\n",    \
                __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__); \
        }                                                  \
    } while (0)
#endif

#endif /* Header_h */
