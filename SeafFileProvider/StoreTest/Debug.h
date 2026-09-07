// Test shim for the standalone store test: the real Debug.h pulls in UIKit.
#import <Foundation/Foundation.h>
#define API_URL @"/api2"
#define Debug(fmt, args...) NSLog(@"D " fmt, ##args)
#define Warning(fmt, args...) NSLog(@"W " fmt, ##args)
#define Info(fmt, args...) NSLog(@"I " fmt, ##args)
