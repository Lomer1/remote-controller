#import "BrightnessBridge.h"
#import <dlfcn.h>

typedef int (*DisplayServicesGetBrightnessFunc)(CGDirectDisplayID, float *);
typedef int (*DisplayServicesSetBrightnessFunc)(CGDirectDisplayID, float);

static void *displayServicesHandle(void) {
    static void *handle = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY);
    });
    return handle;
}

static DisplayServicesGetBrightnessFunc getBrightnessSymbol(void) {
    void *handle = displayServicesHandle();
    if (!handle) { return NULL; }
    return (DisplayServicesGetBrightnessFunc)dlsym(handle, "DisplayServicesGetBrightness");
}

static DisplayServicesSetBrightnessFunc setBrightnessSymbol(void) {
    void *handle = displayServicesHandle();
    if (!handle) { return NULL; }
    return (DisplayServicesSetBrightnessFunc)dlsym(handle, "DisplayServicesSetBrightness");
}

bool MRDisplayServicesCanControlBrightness(void) {
    return getBrightnessSymbol() != NULL && setBrightnessSymbol() != NULL;
}

int MRDisplayServicesGetBrightness(CGDirectDisplayID display, float *brightness) {
    DisplayServicesGetBrightnessFunc fn = getBrightnessSymbol();
    if (!fn) { return -1; }
    return fn(display, brightness);
}

int MRDisplayServicesSetBrightness(CGDirectDisplayID display, float brightness) {
    DisplayServicesSetBrightnessFunc fn = setBrightnessSymbol();
    if (!fn) { return -1; }
    return fn(display, brightness);
}
