// BrightnessBridge.h
#import <CoreGraphics/CoreGraphics.h>

extern int DisplayServicesGetBrightness(CGDirectDisplayID display, float *brightness) __attribute__((weak_import));
extern int DisplayServicesSetBrightness(CGDirectDisplayID display, float brightness) __attribute__((weak_import));
