#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <stdbool.h>

bool MRDisplayServicesCanControlBrightness(void);
int MRDisplayServicesGetBrightness(CGDirectDisplayID display, float *brightness);
int MRDisplayServicesSetBrightness(CGDirectDisplayID display, float brightness);
