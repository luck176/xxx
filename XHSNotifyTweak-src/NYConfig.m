//
//  NYConfig.m
//  XHSNotifyTweak
//

#import "NYConfig.h"
#include <stdarg.h>

static NSString *const kNYConfigFileName = @"config.json";

#pragma mark - 默认配置

static NSDictionary *NYDefaultConfig(void) {
    return @{
        @"enabled": @YES,
        // 提醒方式：banner(顶部横幅，推荐) / alert(系统弹窗) / notify(仅本地通知) / none
        @"style": @"banner",
        @"sound": @{
            @"enabled": @YES,
            @"mode": @"system",          // system(系统音) / file(自定义音频) / none
            @"file": @"",                // 自定义音频文件名，放在配置目录或 sounds/ 下
            @"systemSoundID": @1007,     // iOS 系统提示音 ID，见 README
            @"volume": @1.0,
            @"vibrate": @YES,
            @"ignoreMute": @NO,          // YES = 静音键也不静音
            @"speak": @NO,               // YES = 语音播报
            @"speakPrefix": @"新私信，",
            @"speakMaxLength": @40,
        },
        @"banner": @{
            @"duration": @4.0,
            @"titleTemplate": @"{name}",
            @"bodyTemplate": @"{content}",
            @"subtitleTemplate": @"私信通 · {time}",
            @"maxBodyLength": @120,
            @"showSettingsButton": @YES,
        },
        @"alert": @{
            @"titleTemplate": @"新私信",
            @"bodyTemplate": @"{name}：{content}",
        },
        @"notify": @{
            @"titleTemplate": @"新私信 · {name}",
            @"bodyTemplate": @"{content}",
        },
        @"filter": @{
            @"minInterval": @1.0,        // 两条提醒最小间隔（秒）
            @"ignoreSelf": @YES,
            @"selfUserID": @"",          // 留空自动读取登录账号
            @"blacklist": @[],           // 命中关键词不提醒
            @"whitelist": @[],           // 非空时只提醒命中关键词的消息
            @"ignoreEmptyContent": @YES,
            @"maxAgeSeconds": @180,      // 超过这个时间的历史消息不提醒
            @"skipConvTypes": @[],       // 例如填 [2] 可忽略群聊
        },
        @"debug": @{
            @"enabled": @NO,
            @"logPath": @"",
        },
    };
}

#pragma mark - 工具

static NSDictionary *NYDeepMerge(NSDictionary *def, NSDictionary *user) {
    NSMutableDictionary *out = [def mutableCopy];
    for (id key in user) {
        id uv = user[key];
        id dv = def[key];
        if ([uv isKindOfClass:NSDictionary.class] && [dv isKindOfClass:NSDictionary.class]) {
            out[key] = NYDeepMerge(dv, uv);
        } else {
            out[key] = uv;
        }
    }
    return out;
}

static NSArray *NYCandidateDirs(void) {
    NSMutableArray *a = [NSMutableArray array];
    [a addObject:@"/var/mobile/Library/XHSNotifyTweak"];
    [a addObject:@"/var/mobile/Documents/XHSNotifyTweak"];
    NSString *home = NSHomeDirectory();
    [a addObject:[home stringByAppendingPathComponent:@"Documents/XHSNotifyTweak"]];
    [a addObject:[home stringByAppendingPathComponent:@"Library/XHSNotifyTweak"]];
    return a;
}

static BOOL NYIsWritableDir(NSString *dir) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:dir]) {
        if (![fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL]) {
            return NO;
        }
    }
    NSString *probe = [dir stringByAppendingPathComponent:@".ny_write_test"];
    BOOL ok = [@"1" writeToFile:probe atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [fm removeItemAtPath:probe error:NULL];
    return ok;
}

#pragma mark - 实现

@implementation NYConfig {
    NSMutableDictionary *_raw;       // 用户配置（可变，用于回写）
    NSDictionary *_merged;           // 合并默认值后的只读视图
}

+ (instancetype)shared {
    static NYConfig *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [[NYConfig alloc] init]; });
    return inst;
}

- (instancetype)init {
    if (self = [super init]) {
        [self reload];
    }
    return self;
}

- (void)reload {
    @synchronized (self) {
        NSString *path = nil;
        NSFileManager *fm = [NSFileManager defaultManager];
        for (NSString *dir in NYCandidateDirs()) {
            NSString *p = [dir stringByAppendingPathComponent:kNYConfigFileName];
            if ([fm fileExistsAtPath:p]) { path = p; break; }
        }
        if (!path) {
            for (NSString *dir in NYCandidateDirs()) {
                if (NYIsWritableDir(dir)) {
                    path = [dir stringByAppendingPathComponent:kNYConfigFileName];
                    break;
                }
            }
        }
        if (!path) {
            path = [@"/var/mobile/Library/XHSNotifyTweak" stringByAppendingPathComponent:kNYConfigFileName];
        }

        _configPath = [path copy];
        _configDir = [[path stringByDeletingLastPathComponent] copy];

        NSData *data = [NSData dataWithContentsOfFile:path];
        NSDictionary *loaded = nil;
        if (data.length) {
            id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
            if ([obj isKindOfClass:NSDictionary.class]) loaded = obj;
        }
        _raw = [loaded mutableCopy] ?: [NSMutableDictionary dictionary];
        _merged = NYDeepMerge(NYDefaultConfig(), _raw);

        // 首次运行：写出带默认值的配置文件，方便用户直接编辑
        if (data.length == 0) {
            [self save];
        }
    }
}

- (NSDictionary *)config {
    @synchronized (self) { return _merged ?: NYDefaultConfig(); }
}

- (BOOL)save {
    @synchronized (self) {
        NSMutableDictionary *out = [_raw mutableCopy] ?: [NSMutableDictionary dictionary];
        NSData *data = [NSJSONSerialization dataWithJSONObject:out
                                                      options:NSJSONWritingPrettyPrinted
                                                        error:NULL];
        if (!data) return NO;
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:_configDir]) {
            [fm createDirectoryAtPath:_configDir withIntermediateDirectories:YES attributes:nil error:NULL];
        }
        BOOL ok = [data writeToFile:_configPath atomically:YES];
        _merged = NYDeepMerge(NYDefaultConfig(), out);
        return ok;
    }
}

#pragma mark - 取值

- (id)objectForPath:(NSString *)path {
    if (!path.length) return nil;
    id cur = self.config;
    for (NSString *part in [path componentsSeparatedByString:@"."]) {
        if (![cur isKindOfClass:NSDictionary.class]) return nil;
        cur = ((NSDictionary *)cur)[part];
        if (!cur) return nil;
    }
    return cur;
}

- (NSString *)stringForPath:(NSString *)path {
    id v = [self objectForPath:path];
    if ([v isKindOfClass:NSString.class]) return v;
    if ([v isKindOfClass:NSNumber.class]) return [(NSNumber *)v stringValue];
    return nil;
}

- (BOOL)boolForPath:(NSString *)path default:(BOOL)def {
    id v = [self objectForPath:path];
    return [v isKindOfClass:NSNumber.class] ? [(NSNumber *)v boolValue] : def;
}

- (double)doubleForPath:(NSString *)path default:(double)def {
    id v = [self objectForPath:path];
    return [v isKindOfClass:NSNumber.class] ? [(NSNumber *)v doubleValue] : def;
}

- (NSInteger)intForPath:(NSString *)path default:(NSInteger)def {
    id v = [self objectForPath:path];
    return [v isKindOfClass:NSNumber.class] ? [(NSNumber *)v integerValue] : def;
}

- (BOOL)setObject:(id)obj forPath:(NSString *)path {
    if (!path.length || !obj) return NO;
    @synchronized (self) {
        NSArray *parts = [path componentsSeparatedByString:@"."];
        NSMutableDictionary *cur = _raw;
        for (NSUInteger i = 0; i + 1 < parts.count; i++) {
            id next = cur[parts[i]];
            if (![next isKindOfClass:NSMutableDictionary.class]) {
                next = [NSMutableDictionary dictionary];
            } else {
                next = [next mutableCopy];
            }
            cur[parts[i]] = next;
            cur = next;
        }
        cur[parts.lastObject] = obj;
        return [self save];
    }
}

#pragma mark - 音效解析

- (NSString *)resolveSoundFile:(NSString *)name {
    if (!name.length) return nil;
    if ([name isAbsolutePath]) {
        return [[NSFileManager defaultManager] fileExistsAtPath:name] ? name : nil;
    }
    NSString *home = NSHomeDirectory();
    NSMutableArray *dirs = [NSMutableArray array];
    if (self.configDir) {
        [dirs addObject:self.configDir];
        [dirs addObject:[self.configDir stringByAppendingPathComponent:@"sounds"]];
    }
    [dirs addObject:[home stringByAppendingPathComponent:@"Documents/XHSNotifyTweak"]];
    [dirs addObject:[home stringByAppendingPathComponent:@"Documents/XHSNotifyTweak/sounds"]];
    [dirs addObject:@"/var/mobile/Library/XHSNotifyTweak"];
    [dirs addObject:@"/var/mobile/Library/XHSNotifyTweak/sounds"];
    [dirs addObject:[[NSBundle mainBundle] bundlePath]];

    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *dir in dirs) {
        NSString *p = [dir stringByAppendingPathComponent:name];
        if ([fm fileExistsAtPath:p]) return p;
    }
    return nil;
}

#pragma mark - 日志

- (void)log:(NSString *)fmt, ... {
    if (![self boolForPath:@"debug.enabled" default:NO]) return;
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

    NSString *line = [NSString stringWithFormat:@"[%@] %@\n",
                      [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                     dateStyle:NSDateFormatterNoStyle
                                                     timeStyle:NSDateFormatterMediumStyle],
                      msg];
    NSLog(@"[XHSNotifyTweak] %@", msg);

    @synchronized (self) {
        NSString *lp = [self stringForPath:@"debug.logPath"];
        if (!lp.length) lp = [_configDir stringByAppendingPathComponent:@"debug.log"];
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:[lp stringByDeletingLastPathComponent]]) return;
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:lp];
        if (!fh) {
            [line writeToFile:lp atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        } else {
            @try {
                [fh seekToEndOfFile];
                [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
                [fh closeFile];
            } @catch (NSException *e) { }
        }
    }
}

@end
