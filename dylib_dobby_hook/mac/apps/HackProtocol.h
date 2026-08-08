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
 * 是否为通用/兜底 Hack (如 StoreKit2BaseHack)。
 * 为 YES 的类会排在所有专用 Hack 之后执行, 避免在具体 App 的
 * Hack 之前被匹配到, 导致走错 Hook 路径。
 */
+ (BOOL)isBaseHack;

- (void)firstLaunch;
- (BOOL)hack;
@end
