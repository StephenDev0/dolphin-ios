// Copyright 2022 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import "JitManager+Debugger.h"

#import <math.h>
#import <sys/utsname.h>
#import <unistd.h>

#define CS_OPS_STATUS 0
#define CS_DEBUGGED 0x10000000

extern int csops(pid_t pid, unsigned int ops, void* useraddr, size_t usersize);

@implementation JitManager (Debugger)

- (bool)checkIfProcessIsDebugged {
  int flags;
  if (csops(getpid(), CS_OPS_STATUS, &flags, sizeof(flags) != 0)) {
    return false;
  }

  return flags & CS_DEBUGGED;
}

// The following TXM detection is adapted from StikDebug.
// https://github.com/StephenDev0/StikDebug/blob/d077e232a9ff548d69a21e0e55466e8c7e9edb11/StikJIT/Views/HomeView.swift#L895-L908

- (nullable NSString*)filePathAtPath:(NSString*)path withLength:(NSUInteger)length {
    NSError *error = nil;
    NSArray<NSString *> *items = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:&error];
    if (!items) { return nil; }

    for (NSString *entry in items) {
        if (entry.length == length) {
            return [path stringByAppendingPathComponent:entry];
        }
    }
    return nil;
}

- (bool)checkIfDeviceUsesTXMClassic {
  if (@available(iOS 14.0, *)) {
    if ([[NSProcessInfo processInfo] isiOSAppOnMac]) {
      return false;
    }
  }

  // Primary: /System/Volumes/Preboot/<36>/boot/<96>/usr/.../Ap,TrustedExecutionMonitor.img4
  NSString* bootUUID = [self filePathAtPath:@"/System/Volumes/Preboot" withLength:36];
  if (bootUUID) {
    NSString* bootDir = [bootUUID stringByAppendingPathComponent:@"boot"];
    NSString* ninetySixCharPath = [self filePathAtPath:bootDir withLength:96];
    if (ninetySixCharPath) {
      NSString* img =
          [ninetySixCharPath stringByAppendingPathComponent:
                                 @"usr/standalone/firmware/FUD/Ap,TrustedExecutionMonitor.img4"];
      return access(img.fileSystemRepresentation, F_OK) == 0;
    }
  }

  // Fallback: /private/preboot/<96>/usr/.../Ap,TrustedExecutionMonitor.img4
  NSString* fallback = [self filePathAtPath:@"/private/preboot" withLength:96];
  if (fallback) {
    NSString* img = [fallback stringByAppendingPathComponent:
                                  @"usr/standalone/firmware/FUD/Ap,TrustedExecutionMonitor.img4"];
    return access(img.fileSystemRepresentation, F_OK) == 0;
  }

  return false;
}

- (nullable NSNumber*)deviceVersionFromIdentifier:(NSString*)identifier pattern:(NSString*)pattern {
  NSError* error = nil;
  NSRegularExpression* regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                         options:0
                                                                           error:&error];
  if (!regex) {
    return nil;
  }

  NSTextCheckingResult* match = [regex firstMatchInString:identifier
                                                  options:0
                                                    range:NSMakeRange(0, identifier.length)];
  if (!match || match.numberOfRanges < 3) {
    return nil;
  }

  NSRange majorRange = [match rangeAtIndex:1];
  NSRange minorRange = [match rangeAtIndex:2];
  if (majorRange.location == NSNotFound || minorRange.location == NSNotFound) {
    return nil;
  }

  NSString* majorString = [identifier substringWithRange:majorRange];
  NSString* minorString = [identifier substringWithRange:minorRange];
  double divisor = pow(10.0, minorString.length);

  return @(majorString.doubleValue + (minorString.doubleValue / divisor));
}

- (nullable NSNumber*)deviceVersionFromIdentifier:(NSString*)identifier {
  NSNumber* iPhoneVersion = [self deviceVersionFromIdentifier:identifier
                                                      pattern:@"iPhone(\\d+),(\\d+)"];
  if (iPhoneVersion) {
    return iPhoneVersion;
  }

  return [self deviceVersionFromIdentifier:identifier pattern:@"iPad(\\d+),(\\d+)"];
}

- (NSString*)hardwareIdentifier {
  struct utsname systemInfo;
  uname(&systemInfo);

  return [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding] ?: @"";
}

- (bool)checkIfDeviceUsesTXM {
  if (@available(iOS 26.0, *)) {
    bool hasTXMClassic = [self checkIfDeviceUsesTXMClassic];
    if (@available(iOS 26.6, *)) {
      if (!hasTXMClassic) {
        const double firstTXMDeviceVersion = 14.2;
        const double firstIPadTXMDeviceVersion = 14.5;
        NSString* identifier = [self hardwareIdentifier];
        NSNumber* deviceVersion = [self deviceVersionFromIdentifier:identifier];

        if (deviceVersion) {
          if ([identifier hasPrefix:@"iPad"]) {
            return deviceVersion.doubleValue >= firstIPadTXMDeviceVersion;
          }

          return deviceVersion.doubleValue >= firstTXMDeviceVersion;
        }

        return false;
      }
    }

    return hasTXMClassic;
  } else {
    return false;
  }
}

@end
