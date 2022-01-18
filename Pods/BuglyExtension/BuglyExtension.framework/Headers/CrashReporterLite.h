//
//  CrashReporterLite.h
//  Bugly
//
//  Created by Ben Xu on 15/5/19.
//  Copyright (c) 2015年 tencent.com. All rights reserved.
//
//  BuglyExtension SDK Version 1.0

#import <Foundation/Foundation.h>

@interface CrashReporterLite : NSObject
/**
 *    @brief  初始化 BuglyExtension 崩溃上报,开启 App Group
 *            
 *            初始化方法：
 *             iOS Extension : 在 ViewController 的 initWithCoder: 方法中调用
 *             WatchKit Extension : 在 WKInterfaceController 的 init 方法中调用
 *
 *    @param identifier : App Group Identifier ( WatchKit Extension 可选 )
 */
+ (BOOL)startWithApplicationGroupIdentifier:(NSString *)identifier;

/**
 *    @brief  初始化 BuglyExtension 崩溃上报,不开启 App Group
 *
 *            初始化方法：
 *             iOS Extension : 不支持
 *             WatchKit Extension : 在 WKInterfaceController 的 init 方法中调用
 */
+ (BOOL)start;

/**
 *    @brief  设置是否开启打印 sdk 的 log 信息，默认关闭。在初始化方法之前调用
 *
 *    @param enable 设置为YES，则打印sdk的log信息，在Release产品中请务必设置为NO
 */
+ (void)enableLog:(BOOL)enable;

@end
