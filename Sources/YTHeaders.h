#import <UIKit/UIKit.h>

// Hooks that message `self` need a real @interface: under ARC, messaging a
// forward-declared class is a compile error.

@interface YTReelHeaderView : UIView
@end

@interface YTSettingsSectionController : NSObject
@end

@interface YTAccountPanelViewController : UIViewController
@end

@interface YTMainAppVideoPlayerOverlayViewController : UIViewController
@end

@interface YTMainAppVideoPlayerOverlayView : UIView
@end

@interface YTPivotBarView : UIView
@end
