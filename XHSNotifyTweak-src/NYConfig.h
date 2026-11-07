//
//  NYConfig.h
//  XHSNotifyTweak — 小红书私信通 私信提醒插件
//

#import <Foundation/Foundation.h>

@interface NYConfig : NSObject

+ (instancetype)shared;

/// 当前生效的配置文件路径（加载或首次创建后固定）
@property (nonatomic, copy, readonly) NSString *configPath;
/// 配置文件所在目录（自定义音效放这里）
@property (nonatomic, copy, readonly) NSString *configDir;
/// 完整配置字典（已与默认值深度合并）
@property (nonatomic, copy, readonly) NSDictionary *config;

- (void)reload;
- (BOOL)save;

- (id)objectForPath:(NSString *)path;                              // "sound.file"
- (NSString *)stringForPath:(NSString *)path;
- (BOOL)boolForPath:(NSString *)path default:(BOOL)def;
- (double)doubleForPath:(NSString *)path default:(double)def;
- (NSInteger)intForPath:(NSString *)path default:(NSInteger)def;
- (BOOL)setObject:(id)obj forPath:(NSString *)path;                // 写回 JSON 文件

/// 解析音效文件绝对路径（找不到返回 nil）
- (NSString *)resolveSoundFile:(NSString *)name;

/// 调试日志
- (void)log:(NSString *)fmt, ...;

@end
