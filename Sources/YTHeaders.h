#import <UIKit/UIKit.h>

// Hooks that message `self` need a real @interface: under ARC, messaging a
// forward-declared class is a compile error.

@interface YTReelHeaderView : UIView
@end

// Settings screen (YouTube 17+): categories are numbers; a section item manager
// fills each category through its delegate, the settings view controller.
@interface YTSettingsGroupData : NSObject
@property (nonatomic, assign) NSInteger type;
@end

@interface YTSettingsSectionItem : NSObject
+ (instancetype)switchItemWithTitle:(NSString *)title
                   titleDescription:(NSString *)titleDescription
            accessibilityIdentifier:(NSString *)accessibilityIdentifier
                           switchOn:(BOOL)switchOn
                        switchBlock:(BOOL (^)(id cell, BOOL enabled))switchBlock
                      settingItemId:(int)settingItemId;
+ (instancetype)itemWithTitle:(NSString *)title
             titleDescription:(NSString *)titleDescription
      accessibilityIdentifier:(NSString *)accessibilityIdentifier
              detailTextBlock:(id)detailTextBlock
                  selectBlock:(BOOL (^)(id cell, NSUInteger arg1))selectBlock;
@end

@interface YTSettingsViewController : UIViewController
- (void)setSectionItems:(NSMutableArray *)items forCategory:(NSInteger)category title:(NSString *)title
       titleDescription:(NSString *)titleDescription headerHidden:(BOOL)headerHidden;
- (void)setSectionItems:(NSMutableArray *)items forCategory:(NSInteger)category title:(NSString *)title
                   icon:(id)icon titleDescription:(NSString *)titleDescription headerHidden:(BOOL)headerHidden;
@end

@interface YTSettingsSectionItemManager : NSObject
@end

@interface YTAccountPanelViewController : UIViewController
@end

@interface YTMainAppVideoPlayerOverlayViewController : UIViewController
@end

@interface YTMainAppVideoPlayerOverlayView : UIView
@end

@interface YTPivotBarView : UIView
@end

@interface YTPlayerViewController : UIViewController
- (NSString *)currentVideoID;
- (CGFloat)currentVideoMediaTime;
- (NSString *)contentVideoID;
- (CGFloat)contentVideoMediaTime;
- (CGFloat)currentVideoTotalMediaTime;
- (void)seekToTime:(CGFloat)time;
@end

@interface YTInlinePlayerBarView : UIView
@end
