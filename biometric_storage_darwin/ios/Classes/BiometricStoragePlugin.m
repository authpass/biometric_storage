#import "BiometricStoragePlugin.h"
#import <biometric_storage_darwin/biometric_storage_darwin-Swift.h>

@implementation BiometricStoragePlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftBiometricStoragePlugin registerWithRegistrar:registrar];
}
@end
