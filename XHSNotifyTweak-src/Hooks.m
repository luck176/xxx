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

static void NYHandleMessageArray(id arr) {
    if (!arr) return;
    if ([arr isKindOfClass:NSArray.class]) {
        for (id m in (NSArray *)arr) NYHandleMessage(m);
    } else if ([arr isKindOfClass:NSSet.class]) {
        for (id m in [(NSSet *)arr allObjects]) NYHandleMessage(m);
    } else if ([arr isKindOfClass:NSDictionary.class]) {
        NYHandleMessage(arr);
    }
}

static void NYHandleGenericEvent(id ev) {
    if (!ev) return;
    id msgs = NYCallId(ev, @"messages");
    if (msgs) NYHandleMessageArray(msgs);
    id common = NYCallId(ev, @"commonMessages");
    if (common) NYHandleMessageArray(common);
}

static void NYHandleResponseModel(id model) {
    if (!model) return;
    id gen = NYCallId(model, @"genericEvent");
    if (gen) NYHandleGenericEvent(gen);
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

static id ny_messageFormIm(id self, SEL _cmd, id data) {
    id ret = gOrigMessageFormIm ? gOrigMessageFormIm(self, _cmd, data) : nil;
    @try {
        NYHandleResponseModel(ret);
    } @catch (NSException *e) {
        [[NYConfig shared] log:@"messageFormIm 处理异常: %@", e];
    }
    return ret;
}

static void ny_setGenericEvent(id self, SEL _cmd, id arg) {
    if (gOrigSetGenericEvent) gOrigSetGenericEvent(self, _cmd, arg);
    @try {
        NYHandleGenericEvent(arg);
    } @catch (NSException *e) {
        [[NYConfig shared] log:@"setGenericEvent 处理异常: %@", e];
    }
}

static void ny_setMessages(id self, SEL _cmd, id arg) {
    if (gOrigSetMessages) gOrigSetMessages(self, _cmd, arg);
    @try {
        NYHandleMessageArray(arg);
    } @catch (NSException *e) {
        [[NYConfig shared] log:@"setMessages 处理异常: %@", e];
    }
}

static void ny_didReadIMData(id self, SEL _cmd, id data) {
    if (gOrigDidReadIMData) gOrigDidReadIMData(self, _cmd, data);
    NYConfig *cfg = [NYConfig shared];
    if ([cfg boolForPath:@"debug.enabled" default:NO]) {
        NSUInteger len = 0;
        if ([data respondsToSelector:@selector(length)]) {
            len = [(NSData *)data length];
        }
        [cfg log:@"didReadIMData %lu bytes", (unsigned long)len];
    }
}

static BOOL gInstalled = NO;
static BOOL gSwzMessageFormIm = NO;
static BOOL gSwzSetGenericEvent = NO;
static BOOL gSwzSetMessages = NO;
static BOOL gSwzDidReadIMData = NO;

static void NYInstallHooks(void) {
    if (gInstalled) return;

    Class socketMgr = NSClassFromString(@"XYSocketManager");
    Class respModel = NSClassFromString(@"XYSKResponseModel");
    Class genEvent  = NSClassFromString(@"XYSKGenericEvent");

    // 每个方法只替换一次，避免重复 swizzle 造成自我递归
    if (!gSwzMessageFormIm &&
        NYSwizzle(socketMgr, @"messageFormIm:", (IMP)ny_messageFormIm, (IMP *)&gOrigMessageFormIm)) {
        gSwzMessageFormIm = YES;
    }
    if (!gSwzSetGenericEvent &&
        NYSwizzle(respModel, @"setGenericEvent:", (IMP)ny_setGenericEvent, (IMP *)&gOrigSetGenericEvent)) {
        gSwzSetGenericEvent = YES;
    }
    if (!gSwzSetMessages &&
        NYSwizzle(genEvent, @"setMessages:", (IMP)ny_setMessages, (IMP *)&gOrigSetMessages)) {
        gSwzSetMessages = YES;
    }
    if (!gSwzDidReadIMData &&
        NYSwizzle(socketMgr, @"didReadIMData:", (IMP)ny_didReadIMData, (IMP *)&gOrigDidReadIMData)) {
        gSwzDidReadIMData = YES;
    }

    [[NYConfig shared] log:@"hook 安装 messageFormIm=%d setGenericEvent=%d setMessages=%d didReadIMData=%d",
     gSwzMessageFormIm, gSwzSetGenericEvent, gSwzSetMessages, gSwzDidReadIMData];

    if (gSwzMessageFormIm || gSwzSetGenericEvent || gSwzSetMessages) gInstalled = YES;  // 主链路成功即停
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
}
