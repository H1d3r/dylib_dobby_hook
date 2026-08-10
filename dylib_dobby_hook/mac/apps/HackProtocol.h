//
//  hook_protocol.h
//  dylib_dobby_hook
//
//  Created by artemis on 2024/1/15.
//
#import <Foundation/Foundation.h>

@protocol HackProtocol

+ (NSString *)getAppName;
+ (NSString *)getSupportAppVersion;
/**
 * 判断当前应用是否需要注入。
 * 默认根据 AppName 前缀匹配，如果需要自定义，请在实现类中自行实现。
 */
+ (BOOL)shouldInject:(NSString *)target;
/**
 * 执行排序值, 值越小越靠前执行, 默认 0。
 * 通用/兜底 Hack (如 StoreKit2BaseHack) 返回较大值(如 250)排在末尾,
 * 避免在具体 App 的 Hack 之前被匹配到, 导致走错 Hook 路径。
 */
+ (NSInteger)sortOrder;

- (void)firstLaunch;
- (BOOL)hack;
@end
