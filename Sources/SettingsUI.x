// SettingsUI — встраивается в YouTube Settings отдельной строкой «YTMod».
// Последняя секция — выбор языка UI тюика (не зависит от языка YouTube).
//
// Если YT переименует YTSettingsSectionController — работает fallback через
// длинный тап по аватарке.

#import <UIKit/UIKit.h>
#import "Settings.h"
#import "L10n.h"

// --------- VC ---------

@interface YTModSettingsVC : UITableViewController
@end

@implementation YTModSettingsVC {
    NSArray<NSString *> *_langs;   // доступные языки
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"YTMod";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 56;
    if (@available(iOS 13, *)) {
        self.view.backgroundColor = UIColor.systemBackgroundColor;
    }
    _langs = L10nAvailableLanguages();
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:L10n(@"Done")
                                         style:UIBarButtonItemStyleDone
                                        target:self action:@selector(dismissSelf)];

    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(reload)
               name:kYTModSettingsChangedNotification object:nil];
}

- (void)dismissSelf { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)reload {
    self.title = @"YTMod";
    self.navigationItem.rightBarButtonItem.title = L10n(@"Done");
    [self.tableView reloadData];
}

// секции = опции + одна «Language»
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t {
    return SettingsOrderedSections().count + 1;
}

- (BOOL)isLangSection:(NSInteger)s {
    return s == SettingsOrderedSections().count;
}

- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s {
    if ([self isLangSection:s]) return L10n(@"Language");
    return SettingsLocalizedSection(SettingsOrderedSections()[s]);
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    if ([self isLangSection:s]) return _langs.count + 1; // +1 System
    return SettingsKeysForSection(SettingsOrderedSections()[s]).count;
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *ID = @"c";
    UITableViewCell *cell = [t dequeueReusableCellWithIdentifier:ID]
        ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                  reuseIdentifier:ID];
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.detailTextLabel.text = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    if ([self isLangSection:ip.section]) {
        NSString *forced = [[NSUserDefaults standardUserDefaults] stringForKey:@"ytmod.language"];
        if (ip.row == 0) {
            cell.textLabel.text = L10n(@"System language");
            if (!forced.length) cell.accessoryType = UITableViewCellAccessoryCheckmark;
        } else {
            NSString *lang = _langs[ip.row - 1];
            cell.textLabel.text = L10nDisplayNameForLanguage(lang);
            cell.detailTextLabel.text = lang;
            if ([forced isEqualToString:lang]) cell.accessoryType = UITableViewCellAccessoryCheckmark;
        }
        return cell;
    }

    NSString *key = SettingsKeysForSection(SettingsOrderedSections()[ip.section])[ip.row];
    cell.textLabel.text = SettingsTitleForKey(key);
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    UISwitch *sw = [[UISwitch alloc] init];
    sw.on = SettingsEnabled(key);
    sw.accessibilityLabel = key;
    [sw addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    return cell;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    if (![self isLangSection:ip.section]) return;
    NSString *lang = ip.row == 0 ? nil : _langs[ip.row - 1];
    L10nOverrideLanguage(lang);
    [self reload];
}

- (void)toggle:(UISwitch *)sw {
    SettingsSetEnabled(sw.accessibilityLabel, sw.isOn);
}

@end

// --------- entry point helper ---------

static UIViewController *YTModSettingsNav(void) {
    YTModSettingsVC *vc = [YTModSettingsVC new];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    return nav;
}

// --------- hook YT settings table to add our row ---------

@class YTSettingsSectionItem;

%hook YTSettingsSectionController

- (void)setSectionItems:(NSArray *)items {
    NSString *title = [[self valueForKey:@"title"] description] ?: @"";
    NSString *lc = title.lowercaseString;
    if (!([lc containsString:@"general"] ||
          [lc containsString:@"общ"]     ||  // ru
          [lc containsString:@"загал"]   ||  // uk
          [lc containsString:@"жалпы"]   ||  // kk
          [lc containsString:@"general"] ||  // es/de/fr/pt
          [lc containsString:@"allgemein"]||
          [lc containsString:@"général"] ||
          [lc containsString:@"一般"]     ||  // ja/zh
          [lc containsString:@"通用"])) {
        %orig; return;
    }

    Class itemCls = NSClassFromString(@"YTSettingsSectionItem");
    SEL sel = NSSelectorFromString(@"itemWithTitle:accessibilityIdentifier:detailTextBlock:selectBlock:");
    if (!itemCls || ![itemCls respondsToSelector:sel]) { %orig; return; }

    id (^selectBlock)(id, id) = ^id(id cell, id nav) {
        UIViewController *top = [UIApplication.sharedApplication.keyWindow rootViewController];
        while (top.presentedViewController) top = top.presentedViewController;
        [top presentViewController:YTModSettingsNav() animated:YES completion:nil];
        return nil;
    };

    IMP imp = [itemCls methodForSelector:sel];
    id (*fn)(id, SEL, NSString *, NSString *, id, id) = (void *)imp;
    id entry = fn(itemCls, sel, @"YTMod", @"ytmod_entry", nil, selectBlock);

    NSMutableArray *patched = [items mutableCopy] ?: [NSMutableArray array];
    [patched addObject:entry];
    %orig(patched);
}

%end

// --------- fallback: long press по аватарке ---------

%hook YTAccountPanelViewController
- (void)viewDidLoad {
    %orig;
    UILongPressGestureRecognizer *g = [[UILongPressGestureRecognizer alloc]
        initWithTarget:self action:@selector(ytmodLongPress:)];
    g.minimumPressDuration = 0.8;
    [self.view addGestureRecognizer:g];
}
%new
- (void)ytmodLongPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    [self presentViewController:YTModSettingsNav() animated:YES completion:nil];
}
%end
