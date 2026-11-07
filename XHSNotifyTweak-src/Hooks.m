//
//  Hooks.m
//  XHSNotifyTweak
//
//  挂载点（小红书私信通 1.29 / MessagePro 逆向分析结果）：
//    1. -[XYSocketManager messageFormIm:]          长连接收到 IM 数据后解析出的响应模型（主挂载点）
//    2. -[XYSKResponseModel setGenericEvent:]      响应模型里的通用消息事件
//    3. -[XYSKGenericEvent setMessages:]           事件里的消息数组
//  说明：XYSK 为 App 自带的“socket kit”，XYSKGenericMessage 具备
//        uuid / cid / content / contentType / convType / extension 等字段。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>

#import "NYConfig.h"
#import "NYNotifier.h"

#pragma mark - 运行时调用

static id NYCallId(id obj, NSString *selName) {
    if (!obj) return nil;
    SEL sel = NSSelectorFromString(selName);
    if (![obj respondsToSelector:sel]) return nil;
    typedef id (*Fn)(id, SEL);
    return ((Fn)objc_msgSend)(obj, sel);
}

static int NYCallInt(id obj, NSString *selName) {
    if (!obj) return -1;
    SEL sel = NSSelectorFromString(selName);
    if (![obj respondsToSelector:sel]) return -1;
    typedef int (*Fn)(id, SEL);
    return ((Fn)objc_msgSend)(obj, sel);
}

static unsigned long long NYCallULL(id obj, NSString *selName) {
    if (!obj) return 0;
    SEL sel = NSSelectorFromString(selName);
    if (![obj respondsToSelector:sel]) return 0;
    typedef unsigned long long (*Fn)(id, SEL);
    return ((Fn)objc_msgSend)(obj, sel);
}

#pragma mark - 通用取值

static NSString *NYFirstString(NSDictionary *d, NSArray<NSString *> *keys) {
    if (![d isKindOfClass:NSDictionary.class]) return nil;
    for (NSString *k in keys) {
        id v = d[k];
        if ([v isKindOfClass:NSString.class] && [(NSString *)v length]) return v;
        if ([v isKindOfClass:NSNumber.class]) return [(NSNumber *)v stringValue];
    }
    return nil;
}

static NSString *NYMsgString(id msg, NSDictionary *d, NSString *sel, NSArray<NSString *> *keys) {
    if (d) return NYFirstString(d, keys);
    id v = NYCallId(msg, sel);
    if ([v isKindOfClass:NSString.class] && [(NSString *)v length]) return v;
    if ([v isKindOfClass:NSNumber.class]) return [(NSNumber *)v stringValue];
    return nil;
}

static NSDictionary *NYMsgDict(id msg, NSDictionary *d, NSString *sel, NSArray<NSString *> *keys) {
    if (d) {
        for (NSString *k in keys) {
            id v = d[k];
            if ([v isKindOfClass:NSDictionary.class]) return v;
            if ([v isKindOfClass:NSString.class]) {
                // 有些版本 extension 是 JSON 字符串
                id parsed = [NSJSONSerialization JSONObjectWithData:[(NSString *)v dataUsingEncoding:NSUTF8StringEncoding]
                                                             options:0 error:NULL];
                if ([parsed isKindOfClass:NSDictionary.class]) return parsed;
            }
        }
        return nil;
    }
    id v = NYCallId(msg, sel);
    return [v isKindOfClass:NSDictionary.class] ? v : nil;
}

static int NYMsgInt(id msg, NSDictionary *d, NSString *sel, NSArray<NSString *> *keys) {
    if (d) {
        id v = d[keys.firstObject];
        return [v isKindOfClass:NSNumber.class] ? [(NSNumber *)v intValue] : -1;
    }
    return NYCallInt(msg, sel);
}

static unsigned long long NYMsgULL(id msg, NSDictionary *d, NSString *sel, NSArray<NSString *> *keys) {
    if (d) {
        id v = d[keys.firstObject];
        return [v isKindOfClass:NSNumber.class] ? [(NSNumber *)v unsignedLongLongValue] : 0;
    }
    return NYCallULL(msg, sel);
}

#pragma mark - 自检提示（让"有没有生效"一眼可见）

static UIWindow *NYKeyWindow(void) {
    UIWindow *win = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if (![s isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *w in ((UIWindowScene *)s).windows) {
                if (w.isKeyWindow) { win = w; break; }
            }
            if (win) break;
        }
    }
    if (!win) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        win = [UIApplication sharedApplication].keyWindow;
#pragma clang diagnostic pop
    }
    if (!win) {
        NSArray *ws = [UIApplication sharedApplication].windows;
        if (ws.count) win = ws.firstObject;
    }
    return win;
}

static void NYShowToast(NSString *msg) {
    if (!msg.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *win = NYKeyWindow();
        if (!win) return;
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
        l.text = msg;
        l.font = [UIFont boldSystemFontOfSize:13];
        l.textColor = [UIColor whiteColor];
        l.textAlignment = NSTextAlignmentCenter;
        l.numberOfLines = 0;
        l.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.85];
        l.layer.cornerRadius = 10.0;
        l.layer.masksToBounds = YES;
        [l sizeToFit];
        CGRect f = l.frame;
        f.size.width += 26;
        f.size.height += 14;
        f.origin.x = (win.bounds.size.width - f.size.width) / 2.0;
        f.origin.y = 90;
        l.frame = f;
        l.alpha = 0.0;
        [win addSubview:l];
        [UIView animateWithDuration:0.2 animations:^{
            l.alpha = 1.0;
        } completion:^(BOOL finished) {
            [UIView animateWithDuration:0.35 delay:2.6 options:0 animations:^{
                l.alpha = 0.0;
            } completion:^(BOOL f2) {
                [l removeFromSuperview];
            }];
        }];
    });
}

#pragma mark - 发送人信息

static NSString *NYNameFromExt(NSDictionary *ext) {
    if (![ext isKindOfClass:NSDictionary.class]) return nil;
    NSString *n = NYFirstString(ext, @[ @"sender_name", @"senderName", @"nickname", @"nick_name",
                                        @"from_name", @"user_name", @"name" ]);
    if (n.length) return n;
    for (NSString *k in @[ @"sender", @"from_user", @"user", @"fromUser" ]) {
        id sub = ext[k];
        if ([sub isKindOfClass:NSDictionary.class]) {
            NSString *sn = NYFirstString(sub, @[ @"nickname", @"nick_name", @"name", @"sender_name" ]);
            if (sn.length) return sn;
        }
    }
    return nil;
}

static NSString *NYSenderIDFromExt(NSDictionary *ext) {
    if (![ext isKindOfClass:NSDictionary.class]) return nil;
    NSString *v = NYFirstString(ext, @[ @"sender_id", @"senderId", @"from_uid", @"from_user_id",
                                        @"uid", @"user_id", @"from" ]);
    if (v.length) return v;
    for (NSString *k in @[ @"sender", @"from_user", @"user" ]) {
        id sub = ext[k];
        if ([sub isKindOfClass:NSDictionary.class]) {
            NSString *sv = NYFirstString(sub, @[ @"user_id", @"userId", @"uid", @"id" ]);
            if (sv.length) return sv;
        }
    }
    return nil;
}

static NSString *NYSelfUserID(void) {
    NSString *cfgID = [[NYConfig shared] stringForPath:@"filter.selfUserID"];
    if (cfgID.length) return cfgID;

    Class cls = NSClassFromString(@"XYSocketManager");
    if (!cls) return nil;
    SEL sel = NSSelectorFromString(@"sharedManager");
    if (![cls respondsToSelector:sel]) return nil;
    typedef id (*Fn)(id, SEL);
    id mgr = ((Fn)objc_msgSend)(cls, sel);
    id conf = NYCallId(mgr, @"config");
    id uid = NYCallId(conf, @"userID");
    return [uid isKindOfClass:NSString.class] ? uid : nil;
}

#pragma mark - 内容

static NSString *NYTextFromContent(NSString *raw, int ctype) {
    if (!raw.length || [raw isEqualToString:@"(null)"]) {
        switch (ctype) {
            case 2: return @"[图片]";
            case 3: return @"[视频]";
            case 4: return @"[语音]";
            case 5: return @"[表情]";
            case 6: return @"[笔记]";
            case 7: return @"[商品]";
            default: return @"[新消息]";
        }
    }
    NSString *trim = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trim hasPrefix:@"{"] || [trim hasPrefix:@"["]) {
        id obj = [NSJSONSerialization JSONObjectWithData:[trim dataUsingEncoding:NSUTF8StringEncoding]
                                                 options:0 error:NULL];
        if ([obj isKindOfClass:NSDictionary.class]) {
            NSString *t = NYFirstString(obj, @[ @"text", @"content", @"desc", @"title", @"note", @"summary" ]);
            if (t.length) return t;
        }
    }
    return trim;
}

#pragma mark - 消息处理

static BOOL NYContainsAny(NSString *text, NSArray *keywords) {
    if (![keywords isKindOfClass:NSArray.class] || keywords.count == 0) return NO;
    for (id k in keywords) {
        if (![k isKindOfClass:NSString.class] || ![(NSString *)k length]) continue;
        if ([text rangeOfString:(NSString *)k].location != NSNotFound) return YES;
    }
    return NO;
}

static void NYHandleMessage(id msg) {
    if (!msg) return;
    NYConfig *cfg = [NYConfig shared];
    NSDictionary *d = [msg isKindOfClass:NSDictionary.class] ? (NSDictionary *)msg : nil;

    NSString *uuid = NYMsgString(msg, d, @"uuid", @[ @"uuid", @"message_id", @"msg_id", @"msgId" ]);
    NSString *cid  = NYMsgString(msg, d, @"cid",  @[ @"cid", @"conversation_id", @"chat_id", @"convId" ]);
    NSString *raw  = NYMsgString(msg, d, @"content", @[ @"content", @"text" ]);
    int ctype = NYMsgInt(msg, d, @"contentType", @[ @"contentType", @"content_type" ]);
    int conv  = NYMsgInt(msg, d, @"convType", @[ @"convType", @"conv_type" ]);
    NSDictionary *ext = NYMsgDict(msg, d, @"extension", @[ @"extension", @"ext" ]);

    // 拉取历史记录时不要把旧消息也提醒一遍
    double maxAge = [cfg doubleForPath:@"filter.maxAgeSeconds" default:180];
    if (maxAge > 0) {
        unsigned long long createAt = NYMsgULL(msg, d, @"createAt", @[ @"createAt", @"create_at", @"timestamp" ]);
        double ts = createAt > 1000000000000ULL ? (double)createAt / 1000.0 : (double)createAt;
        if (ts > 1400000000.0) {           // 只处理看起来像时间戳的值
            double now = [NSDate date].timeIntervalSince1970;
            if (now - ts > maxAge) {
                [cfg log:@"历史消息跳过（%.0f 秒前）", now - ts];
                return;
            }
        }
    }

    // 群聊/其他会话类型过滤
    NSArray *skipConv = [cfg objectForPath:@"filter.skipConvTypes"];
    if ([skipConv isKindOfClass:NSArray.class] && conv >= 0) {
        for (id v in skipConv) {
            if ([v respondsToSelector:@selector(intValue)] && [v intValue] == conv) {
                [cfg log:@"按 convType=%d 过滤", conv];
                return;
            }
        }
    }

    // 自己发的消息过滤
    if ([cfg boolForPath:@"filter.ignoreSelf" default:YES]) {
        NSString *selfID = NYSelfUserID();
        NSString *senderID = NYSenderIDFromExt(ext);
        if (selfID.length && senderID.length && [selfID isEqualToString:senderID]) {
            [cfg log:@"自家发送，忽略（sender=%@）", senderID];
            return;
        }
    }

    NSString *content = NYTextFromContent(raw, ctype);
    NSString *name = NYNameFromExt(ext);
    if (!name.length) name = cid;

    // 关键词白/黑名单（对 内容+发送人 做匹配）
    NSString *haystack = [NSString stringWithFormat:@"%@ %@", name ?: @"", content ?: @""];
    NSArray *black = [cfg objectForPath:@"filter.blacklist"];
    if (NYContainsAny(haystack, black)) {
        [cfg log:@"命中黑名单，忽略"];
        return;
    }
    NSArray *white = [cfg objectForPath:@"filter.whitelist"];
    if ([white isKindOfClass:NSArray.class] && white.count > 0 && !NYContainsAny(haystack, white)) {
        [cfg log:@"未命中白名单，忽略"];
        return;
    }

    NSString *key = uuid.length ? uuid
                                : [NSString stringWithFormat:@"%@|%@|%@", cid ?: @"", name ?: @"", content ?: @""];

    if ([cfg boolForPath:@"debug.enabled" default:NO] && ext) {
        [cfg log:@"消息字段 ctype=%d conv=%d extKeys=%@", ctype, conv, [ext.allKeys componentsJoinedByString:@","]];
    }

    [[NYNotifier shared] notifyWithName:name content:content key:key];
}

// 通用递归：不管消息被包在事件里、模型里还是数组里，都往下捞一遍
static BOOL NYHasSel(id obj, NSString *sel) {
    return obj && [obj respondsToSelector:NSSelectorFromString(sel)];
}

static void NYHandleAny(id obj, int depth) {
    if (!obj || depth > 3) return;
    if ([obj isKindOfClass:NSArray.class]) {
        for (id x in (NSArray *)obj) NYHandleAny(x, depth + 1);
        return;
    }
    if ([obj isKindOfClass:NSSet.class]) {
        for (id x in [(NSSet *)obj allObjects]) NYHandleAny(x, depth + 1);
        return;
    }
    if ([obj isKindOfClass:NSDictionary.class]) {
        NYHandleMessage(obj);
        return;
    }
    if ([obj isKindOfClass:NSData.class]) return;   // 原始二进制，不解析

    for (NSString *sel in @[ @"messages", @"commonMessages", @"genericEvent",
                             @"IMEvent", @"pushOneMsg", @"chatOneMsg", @"message" ]) {
        if (!NYHasSel(obj, sel)) continue;
        id v = NYCallId(obj, sel);
        if (!v || v == obj) continue;
        if ([v isKindOfClass:NSArray.class] || [v isKindOfClass:NSSet.class] ||
            [v respondsToSelector:@selector(countByEnumeratingWithState:objects:count:)]) {
            NYHandleAny(v, depth + 1);
        } else if ([v isKindOfClass:NSDictionary.class]) {
            NYHandleAny(v, depth + 1);
        } else if (NYHasSel(v, @"content") || NYHasSel(v, @"uuid")) {
            NYHandleAny(v, depth + 1);
        }
    }

    if (NYHasSel(obj, @"content") && (NYHasSel(obj, @"uuid") || NYHasSel(obj, @"cid"))) {
        NYHandleMessage(obj);
    }
}

static void NYHandleMessageArray(id arr) {
    NYHandleAny(arr, 0);
}

static void NYHandleGenericEvent(id ev) {
    NYHandleAny(ev, 0);
}

static void NYHandleResponseModel(id model) {
    NYHandleAny(model, 0);
}

#pragma mark - 安装 hook

typedef id (*NYObjImp)(id, SEL, id);
typedef void (*NYVoidImp)(id, SEL, id);

static BOOL NYSwizzle(Class cls, NSString *selName, IMP newImp, IMP *out) {
    if (!cls || !selName.length) return NO;
    SEL sel = NSSelectorFromString(selName);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return NO;
    if (out) *out = method_getImplementation(m);
    method_setImplementation(m, newImp);
    return YES;
}

static NYObjImp gOrigMessageFormIm = NULL;
static NYVoidImp gOrigSetGenericEvent = NULL;
static NYVoidImp gOrigSetMessages = NULL;
static NYVoidImp gOrigDidReadIMData = NULL;
static NYVoidImp gOrigSetIMEvent = NULL;
static NYVoidImp gOrigSetPushOneMsg = NULL;
static NYVoidImp gOrigSetChatOneMsg = NULL;
static NYVoidImp gOrigSetCommonMessages = NULL;
static NYVoidImp gOrigDidReadPushData = NULL;
static NYVoidImp gOrigDidReadSignalData = NULL;

static int gHookInstalled = 0;   // 成功挂上多少个方法
static int gHookHits = 0;        // 运行时被调用的次数
static BOOL gHitToastShown = NO;

static void NYNoteHit(NSString *hook, id payload) {
    gHookHits++;
    if (!gHitToastShown) {
        gHitToastShown = YES;
        NYShowToast([NSString stringWithFormat:@"已捕捉到数据：%@", hook]);
    }
    [[NYConfig shared] log:@"命中 %@ 累计=%d type=%@", hook, gHookHits, NSStringFromClass([payload class])];
    @try {
        NYHandleAny(payload, 0);
    } @catch (NSException *e) {
        [[NYConfig shared] log:@"%@ 处理异常: %@", hook, e];
    }
}

static id ny_messageFormIm(id self, SEL _cmd, id data) {
    id ret = gOrigMessageFormIm ? gOrigMessageFormIm(self, _cmd, data) : nil;
    NYNoteHit(@"messageFormIm", ret);
    return ret;
}

static void ny_setGenericEvent(id self, SEL _cmd, id arg) {
    if (gOrigSetGenericEvent) gOrigSetGenericEvent(self, _cmd, arg);
    NYNoteHit(@"setGenericEvent", arg);
}

static void ny_setIMEvent(id self, SEL _cmd, id arg) {
    if (gOrigSetIMEvent) gOrigSetIMEvent(self, _cmd, arg);
    NYNoteHit(@"setIMEvent", arg);
}

static void ny_setPushOneMsg(id self, SEL _cmd, id arg) {
    if (gOrigSetPushOneMsg) gOrigSetPushOneMsg(self, _cmd, arg);
    NYNoteHit(@"setPushOneMsg", arg);
}

static void ny_setChatOneMsg(id self, SEL _cmd, id arg) {
    if (gOrigSetChatOneMsg) gOrigSetChatOneMsg(self, _cmd, arg);
    NYNoteHit(@"setChatOneMsg", arg);
}

static void ny_setMessages(id self, SEL _cmd, id arg) {
    if (gOrigSetMessages) gOrigSetMessages(self, _cmd, arg);
    NYNoteHit(@"setMessages", arg);
}

static void ny_setCommonMessages(id self, SEL _cmd, id arg) {
    if (gOrigSetCommonMessages) gOrigSetCommonMessages(self, _cmd, arg);
    NYNoteHit(@"setCommonMessages", arg);
}

static void ny_didReadIMData(id self, SEL _cmd, id data) {
    if (gOrigDidReadIMData) gOrigDidReadIMData(self, _cmd, data);
    NYNoteHit(@"didReadIMData", data);
}

static void ny_didReadPushData(id self, SEL _cmd, id data) {
    if (gOrigDidReadPushData) gOrigDidReadPushData(self, _cmd, data);
    NYNoteHit(@"didReadPushData", data);
}

static void ny_didReadSignalData(id self, SEL _cmd, id data) {
    if (gOrigDidReadSignalData) gOrigDidReadSignalData(self, _cmd, data);
    NYNoteHit(@"didReadSignalData", data);
}

static BOOL gInstalled = NO;

#define NYHOOK(clsName, selName, fn, origVar) \
    if (!(origVar) && NYSwizzle(NSClassFromString(clsName), selName, (IMP)(fn), (IMP *)&(origVar))) \
        gHookInstalled++;

static void NYInstallHooks(void) {
    if (gInstalled) return;

    NYHOOK(@"XYSocketManager",  @"messageFormIm:",        ny_messageFormIm,     gOrigMessageFormIm)
    NYHOOK(@"XYSocketManager",  @"didReadIMData:",        ny_didReadIMData,     gOrigDidReadIMData)
    NYHOOK(@"XYSocketManager",  @"didReadPushData:",      ny_didReadPushData,   gOrigDidReadPushData)
    NYHOOK(@"XYSocketManager",  @"didReadSignalData:",    ny_didReadSignalData, gOrigDidReadSignalData)
    NYHOOK(@"XYSKResponseModel", @"setGenericEvent:",     ny_setGenericEvent,   gOrigSetGenericEvent)
    NYHOOK(@"XYSKResponseModel", @"setIMEvent:",          ny_setIMEvent,        gOrigSetIMEvent)
    NYHOOK(@"XYSKResponseModel", @"setPushOneMsg:",       ny_setPushOneMsg,     gOrigSetPushOneMsg)
    NYHOOK(@"XYSKResponseModel", @"setChatOneMsg:",       ny_setChatOneMsg,     gOrigSetChatOneMsg)
    NYHOOK(@"XYSKGenericEvent",  @"setMessages:",         ny_setMessages,       gOrigSetMessages)
    NYHOOK(@"XYSKGenericEvent",  @"setCommonMessages:",   ny_setCommonMessages, gOrigSetCommonMessages)

    [[NYConfig shared] log:@"hook 安装成功 %d 个：mfi=%d ge=%d ime=%d push=%d chat=%d msgs=%d common=%d raw=%d",
     gHookInstalled, !!gOrigMessageFormIm, !!gOrigSetGenericEvent, !!gOrigSetIMEvent,
     !!gOrigSetPushOneMsg, !!gOrigSetChatOneMsg, !!gOrigSetMessages, !!gOrigSetCommonMessages,
     !!gOrigDidReadIMData];

    // 少挂一两个没关系（有的版本没有对应 setter），关键链路挂上就停手
    if (gOrigMessageFormIm || gOrigSetGenericEvent || gOrigSetMessages ||
        gOrigSetPushOneMsg || gOrigSetChatOneMsg || gOrigSetIMEvent) {
        gInstalled = YES;
    }
}

#pragma mark - 设置入口（三指双击屏幕）

@interface NYGestureProxy : NSObject
@end

@implementation NYGestureProxy
+ (instancetype)shared {
    static NYGestureProxy *p;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ p = [[NYGestureProxy alloc] init]; });
    return p;
}
- (void)handleTap:(UITapGestureRecognizer *)g {
    [[NYNotifier shared] showSettings];
}
@end

static char kNYGestureKey;

static void NYInstallSettingsGesture(void) {
    if (![[NYConfig shared] boolForPath:@"enabled" default:YES]) return;

    UIWindow *win = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if (![s isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *w in ((UIWindowScene *)s).windows) {
                if (w.isKeyWindow) { win = w; break; }
            }
        }
    }
    if (!win) win = [UIApplication sharedApplication].keyWindow;
    if (!win) return;
    if (objc_getAssociatedObject(win, &kNYGestureKey)) return;

    objc_setAssociatedObject(win, &kNYGestureKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
                                    initWithTarget:[NYGestureProxy shared]
                                            action:@selector(handleTap:)];
    tap.numberOfTouchesRequired = 3;
    tap.numberOfTapsRequired = 2;
    [win addGestureRecognizer:tap];
}

#pragma mark - 入口

__attribute__((constructor)) static void NYTweakEntry(void) {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (![bundleID isEqualToString:@"com.xingin.messagepro"]) {
        NSLog(@"[XHSNotifyTweak] 当前宿主 %@ 非私信通，仍尝试加载", bundleID);
    }

    [[NYConfig shared] reload];

    // 类可能晚于 dylib 加载完成，做几次重试
    for (NSInteger i = 1; i <= 6; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * i * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            NYInstallHooks();
            NYInstallSettingsGesture();
        });
    }

    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        [[NYConfig shared] reload];       // 回到前台重新读一次配置，手改 JSON 也能即时生效
        NYInstallSettingsGesture();
    }];

    // 启动自检：能弹出来就说明 dylib 真的被加载了，数字就是成功挂上的方法数
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NYShowToast([NSString stringWithFormat:@"XHSNotify 已加载 · 钩子 %d 个 · 命中 %d 次",
                     gHookInstalled, gHookHits]);
    });
}
