// SettingsUI — раздел «YTMod» в настройках YouTube (переключатели + «Язык»)
// и отдельный экран YTModSettingsVC, который открывается из пункта «Язык».

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Settings.h"
#import "L10n.h"
#import "YTHeaders.h"

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

// --------- YTMod section in YouTube's own Settings screen ---------
// Settings are numbered categories: register ours in the category order, then
// fill it when the section item manager asks for it.

static const NSInteger kYTModCategory = 1085;

%hook YTSettingsGroupData
- (NSArray<NSNumber *> *)orderedCategories {
    NSArray *categories = %orig;
    // Some tweak managers replace grouping with a +tweaks group; leave those alone.
    if (self.type != 1 || class_getClassMethod(object_getClass(self), @selector(tweaks)))
        return categories;
    if ([categories containsObject:@(kYTModCategory)]) return categories;
    NSMutableArray *m = [categories mutableCopy];
    [m insertObject:@(kYTModCategory) atIndex:0];
    return m;
}
%end

%hook YTAppSettingsPresentationData
+ (NSArray<NSNumber *> *)settingsCategoryOrder {
    NSArray<NSNumber *> *order = %orig;
    if ([order containsObject:@(kYTModCategory)]) return order;
    NSUInteger i = [order indexOfObject:@(1)];
    NSMutableArray *m = [order mutableCopy];
    [m insertObject:@(kYTModCategory) atIndex:(i == NSNotFound ? 0 : i + 1)];
    return m;
}
%end

%hook YTSettingsSectionItemManager
- (void)updateSectionForCategory:(NSUInteger)category withEntry:(id)entry {
    if (category != kYTModCategory) { %orig; return; }

    YTSettingsViewController *delegate = [self valueForKey:@"_dataDelegate"];
    Class itemCls = %c(YTSettingsSectionItem);
    NSMutableArray *items = [NSMutableArray array];

    for (NSString *section in SettingsOrderedSections()) {
        for (NSString *key in SettingsKeysForSection(section)) {
            [items addObject:[itemCls switchItemWithTitle:SettingsTitleForKey(key)
                titleDescription:nil
                accessibilityIdentifier:nil
                switchOn:SettingsEnabled(key)
                switchBlock:^BOOL(id cell, BOOL enabled) {
                    SettingsSetEnabled(key, enabled);
                    return YES;
                }
                settingItemId:0]];
        }
    }

    [items addObject:[itemCls itemWithTitle:L10n(@"Language")
        titleDescription:nil
        accessibilityIdentifier:nil
        detailTextBlock:nil
        selectBlock:^BOOL(id cell, NSUInteger arg1) {
            [delegate presentViewController:YTModSettingsNav() animated:YES completion:nil];
            return YES;
        }]];

    SEL withIcon = @selector(setSectionItems:forCategory:title:icon:titleDescription:headerHidden:);
    if ([delegate respondsToSelector:withIcon])
        [delegate setSectionItems:items forCategory:kYTModCategory title:@"YTMod"
                             icon:[%c(YTIIcon) new] titleDescription:nil headerHidden:NO];
    else
        [delegate setSectionItems:items forCategory:kYTModCategory title:@"YTMod"
                 titleDescription:nil headerHidden:NO];
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
