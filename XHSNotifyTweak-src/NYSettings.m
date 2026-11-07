//
//  NYSettings.m
//  XHSNotifyTweak —  设置面板（横幅右上角“设置”进入）
//

#import "NYSettings.h"
#import "NYConfig.h"
#import "NYNotifier.h"

@interface NYRow : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *detail;
@property (nonatomic, assign) BOOL isSwitch;
@property (nonatomic, assign) BOOL switchValue;
@property (nonatomic, copy) NSString *configPath;
@property (nonatomic, assign) BOOL hasDisclosure;
@property (nonatomic, copy) void (^action)(void);
@end

@implementation NYRow
@end

@interface NYSettingsViewController ()
@property (nonatomic, strong) NSArray *sections;   // @[ @{title, rows} ]
@end

@implementation NYSettingsViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"私信提醒设置";
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(done)];
    [self rebuild];
}

- (void)done {
    [[NYConfig shared] save];
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - 构建行

- (NYRow *)switchRow:(NSString *)title path:(NSString *)path {
    NYRow *r = [[NYRow alloc] init];
    r.title = title;
    r.isSwitch = YES;
    r.configPath = path;
    r.switchValue = [[NYConfig shared] boolForPath:path default:YES];
    return r;
}

- (NYRow *)valueRow:(NSString *)title path:(NSString *)path fallback:(NSString *)fb {
    NYRow *r = [[NYRow alloc] init];
    r.title = title;
    r.configPath = path;
    NSString *v = [[NYConfig shared] stringForPath:path];
    r.detail = v.length ? v : (fb ?: @"");
    r.hasDisclosure = YES;
    return r;
}

- (void)rebuild {
    NYConfig *cfg = [NYConfig shared];
    __weak typeof(self) weakSelf = self;

    NYRow *style = [[NYRow alloc] init];
    style.title = @"提醒方式";
    style.hasDisclosure = YES;
    NSString *s = [cfg stringForPath:@"style"] ?: @"banner";
    NSDictionary *styleNames = @{ @"banner": @"顶部横幅", @"alert": @"系统弹窗",
                                  @"notify": @"仅本地通知", @"none": @"不弹窗" };
    style.detail = styleNames[s] ?: s;
    style.action = ^{
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"提醒方式"
                                                                    message:nil
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
        NSArray *items = @[ @"banner", @"alert", @"notify", @"none" ];
        NSArray *names = @[ @"顶部横幅（推荐）", @"系统弹窗", @"仅本地通知", @"不弹窗（只响铃）" ];
        for (NSUInteger i = 0; i < items.count; i++) {
            NSString *key = items[i];
            [ac addAction:[UIAlertAction actionWithTitle:names[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                [[NYConfig shared] setObject:key forPath:@"style"];
                [weakSelf rebuild];
            }]];
        }
        [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        ac.popoverPresentationController.sourceView = weakSelf.view;
        ac.popoverPresentationController.sourceRect = weakSelf.view.bounds;
        [weakSelf presentViewController:ac animated:YES completion:nil];
    };

    NYRow *soundMode = [[NYRow alloc] init];
    soundMode.title = @"音效来源";
    soundMode.hasDisclosure = YES;
    NSString *m = [cfg stringForPath:@"sound.mode"] ?: @"system";
    NSDictionary *modeNames = @{ @"system": @"系统提示音", @"file": @"自定义音频", @"none": @"关闭" };
    soundMode.detail = modeNames[m] ?: m;
    soundMode.action = ^{
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"音效来源"
                                                                    message:nil
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
        [ac addAction:[UIAlertAction actionWithTitle:@"系统提示音" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [[NYConfig shared] setObject:@"system" forPath:@"sound.mode"];
            [weakSelf rebuild];
        }]];
        [ac addAction:[UIAlertAction actionWithTitle:@"自定义音频文件" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [[NYConfig shared] setObject:@"file" forPath:@"sound.mode"];
            [weakSelf rebuild];
        }]];
        [ac addAction:[UIAlertAction actionWithTitle:@"关闭音效" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
            [[NYConfig shared] setObject:@"none" forPath:@"sound.mode"];
            [weakSelf rebuild];
        }]];
        [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        ac.popoverPresentationController.sourceView = weakSelf.view;
        ac.popoverPresentationController.sourceRect = weakSelf.view.bounds;
        [weakSelf presentViewController:ac animated:YES completion:nil];
    };

    NYRow *soundFile = [self valueRow:@"音效文件" path:@"sound.file" fallback:@"（未选择）"];
    soundFile.action = ^{ [weakSelf chooseSoundFile]; };

    NYRow *sysID = [self valueRow:@"系统音 ID" path:@"sound.systemSoundID" fallback:@"1007"];
    sysID.action = ^{ [weakSelf editTextFieldWithPath:@"sound.systemSoundID" title:@"系统音 ID" keyboard:UIKeyboardTypeNumberPad]; };

    NYRow *volume = [self valueRow:@"音量 0~1" path:@"sound.volume" fallback:@"1.0"];
    volume.action = ^{ [weakSelf editTextFieldWithPath:@"sound.volume" title:@"音量（0.0~1.0）" keyboard:UIKeyboardTypeDecimalPad]; };

    NYRow *titleTpl = [self valueRow:@"标题模板" path:@"banner.titleTemplate" fallback:@"{name}"];
    titleTpl.action = ^{ [weakSelf editTextFieldWithPath:@"banner.titleTemplate" title:@"标题模板" keyboard:UIKeyboardTypeDefault]; };

    NYRow *bodyTpl = [self valueRow:@"正文模板" path:@"banner.bodyTemplate" fallback:@"{content}"];
    bodyTpl.action = ^{ [weakSelf editTextFieldWithPath:@"banner.bodyTemplate" title:@"正文模板" keyboard:UIKeyboardTypeDefault]; };

    NYRow *duration = [self valueRow:@"横幅停留(秒)" path:@"banner.duration" fallback:@"4.0"];
    duration.action = ^{ [weakSelf editTextFieldWithPath:@"banner.duration" title:@"横幅停留秒数" keyboard:UIKeyboardTypeDecimalPad]; };

    NYRow *minInterval = [self valueRow:@"最小间隔(秒)" path:@"filter.minInterval" fallback:@"1.0"];
    minInterval.action = ^{ [weakSelf editTextFieldWithPath:@"filter.minInterval" title:@"两条提醒的最小间隔（秒）" keyboard:UIKeyboardTypeDecimalPad]; };

    NYRow *test = [[NYRow alloc] init];
    test.title = @"试听当前音效";
    test.action = ^{ [[NYNotifier shared] playConfiguredSound]; };

    NYRow *demo = [[NYRow alloc] init];
    demo.title = @"发送一条测试提醒";
    demo.action = ^{
        [[NYNotifier shared] notifyWithName:@"测试账号"
                                   content:@"这是一条测试私信，用于确认横幅与音效正常。"
                                       key:[NSString stringWithFormat:@"test-%f", [NSDate date].timeIntervalSince1970]];
    };

    NYRow *debug = [self switchRow:@"调试日志" path:@"debug.enabled"];
    debug.switchValue = [cfg boolForPath:@"debug.enabled" default:NO];

    NYRow *about = [[NYRow alloc] init];
    about.title = @"配置文件";
    about.detail = [[NYConfig shared] configPath];

    self.sections = @[
        @{ @"title": @"总开关", @"rows": @[ [self switchRow:@"启用私信提醒" path:@"enabled"], style ] },
        @{ @"title": @"声音与震动", @"rows": @[ [self switchRow:@"播放音效" path:@"sound.enabled"],
                                              soundMode, soundFile, sysID, volume,
                                              [self switchRow:@"震动" path:@"sound.vibrate"],
                                              [self switchRow:@"静音键也响" path:@"sound.ignoreMute"],
                                              [self switchRow:@"语音播报内容" path:@"sound.speak"] ] },
        @{ @"title": @"文案与显示", @"rows": @[ titleTpl, bodyTpl, duration, minInterval ] },
        @{ @"title": @"测试", @"rows": @[ test, demo ] },
        @{ @"title": @"其他", @"rows": @[ debug, about ] },
    ];
    [self.tableView reloadData];
}

#pragma mark - 表格

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sections.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.sections[section][@"title"];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 2) return @"占位符：{name} 发送人，{content} 内容，{time} 时间";
    if (section == 4) return @"把 .caf/.wav/.mp3/.m4a 放进取值目录后，点“音效文件”选择即可。";
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.sections[section][@"rows"] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NYRow *row = self.sections[indexPath.section][@"rows"][indexPath.row];
    static NSString *cellID = @"NYCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellID];
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
    }
    cell.textLabel.text = row.title;
    cell.detailTextLabel.text = row.detail;
    cell.accessoryType = row.isSwitch ? UITableViewCellAccessoryNone
                                      : (row.hasDisclosure ? UITableViewCellAccessoryDisclosureIndicator
                                                           : UITableViewCellAccessoryNone);
    cell.accessoryView = nil;
    cell.selectionStyle = row.isSwitch ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleDefault;
    if (row.isSwitch) {
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = row.switchValue;
        sw.tag = indexPath.section * 1000 + indexPath.row;
        [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    }
    return cell;
}

- (void)switchChanged:(UISwitch *)sw {
    NSInteger section = sw.tag / 1000;
    NSInteger row = sw.tag % 1000;
    NYRow *r = self.sections[section][@"rows"][row];
    if (r.configPath.length) {
        [[NYConfig shared] setObject:@(sw.isOn) forPath:r.configPath];
        r.switchValue = sw.isOn;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NYRow *row = self.sections[indexPath.section][@"rows"][indexPath.row];
    if (row.action) row.action();
}

#pragma mark - 编辑

- (void)editTextFieldWithPath:(NSString *)path title:(NSString *)title keyboard:(UIKeyboardType)kb {
    NYConfig *cfg = [NYConfig shared];
    NSString *cur = [cfg stringForPath:path] ?: @"";
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:title
                                                                message:nil
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = cur;
        tf.keyboardType = kb;
    }];
    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *text = ac.textFields.firstObject.text ?: @"";
        id value = text;
        if (kb == UIKeyboardTypeNumberPad || kb == UIKeyboardTypeDecimalPad) {
            value = @([text doubleValue]);
        }
        [[NYConfig shared] setObject:value forPath:path];
        [weakSelf rebuild];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

#pragma mark - 音效文件选择

- (NSArray<NSString *> *)soundFiles {
    NSMutableArray *out = [NSMutableArray array];
    NYConfig *cfg = [NYConfig shared];
    NSMutableArray *dirs = [NSMutableArray array];
    if (cfg.configDir) {
        [dirs addObject:cfg.configDir];
        [dirs addObject:[cfg.configDir stringByAppendingPathComponent:@"sounds"]];
    }
    NSString *home = NSHomeDirectory();
    [dirs addObject:[home stringByAppendingPathComponent:@"Documents/XHSNotifyTweak"]];
    [dirs addObject:[home stringByAppendingPathComponent:@"Documents/XHSNotifyTweak/sounds"]];
    [dirs addObject:@"/var/mobile/Library/XHSNotifyTweak"];
    [dirs addObject:@"/var/mobile/Library/XHSNotifyTweak/sounds"];

    NSArray *exts = @[ @"caf", @"wav", @"mp3", @"m4a", @"aif", @"aiff" ];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *dir in dirs) {
        for (NSString *f in [fm contentsOfDirectoryAtPath:dir error:NULL]) {
            if ([exts containsObject:[f.pathExtension lowercaseString]] &&
                ![out containsObject:f]) {
                [out addObject:f];
            }
        }
    }
    return out;
}

- (void)chooseSoundFile {
    NSArray *files = [self soundFiles];
    __weak typeof(self) weakSelf = self;
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"选择音效文件"
                                                                message:[NSString stringWithFormat:@"目录：%@", [NYConfig shared].configDir]
                                                         preferredStyle:UIAlertControllerStyleActionSheet];
    if (!files.count) {
        [ac addAction:[UIAlertAction actionWithTitle:@"（目录里还没有音频文件）" style:UIAlertActionStyleDefault handler:nil]];
    }
    for (NSString *f in files) {
        [ac addAction:[UIAlertAction actionWithTitle:f style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [[NYConfig shared] setObject:@"file" forPath:@"sound.mode"];
            [[NYConfig shared] setObject:f forPath:@"sound.file"];
            [weakSelf rebuild];
        }]];
    }
    [ac addAction:[UIAlertAction actionWithTitle:@"手动输入文件名/路径" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf editTextFieldWithPath:@"sound.file" title:@"音效文件名或绝对路径" keyboard:UIKeyboardTypeDefault];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    ac.popoverPresentationController.sourceView = weakSelf.view;
    ac.popoverPresentationController.sourceRect = weakSelf.view.bounds;
    [self presentViewController:ac animated:YES completion:nil];
}

@end
