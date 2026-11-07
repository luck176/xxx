//
//  NYNotifier.h
//  XHSNotifyTweak
//

#import <Foundation/Foundation.h>

@interface NYNotifier : NSObject

+ (instancetype)shared;

/// 触发一次私信提醒（内部做去重、限流、按配置决定横幅/弹窗/本地通知/声音/播报）
/// @param name    发送人昵称（可空）
/// @param content 消息内容（可空）
/// @param key     去重键（一般是消息 uuid）
- (void)notifyWithName:(NSString *)name content:(NSString *)content key:(NSString *)key;

/// 用当前配置播放一次音效（供设置页“试听”使用）
- (void)playConfiguredSound;

/// 打开设置面板
- (void)showSettings;

@end
