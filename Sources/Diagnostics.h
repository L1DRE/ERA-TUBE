#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// Appends a line to Documents/ytmod-log.txt (capped in size).
void YTModLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
NSURL *YTModLogFileURL(void);

#ifdef __cplusplus
}
#endif
