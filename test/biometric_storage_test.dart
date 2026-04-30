import 'package:biometric_storage/src/biometric_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('biometric_storage');

  TestWidgetsFlutterBinding.ensureInitialized();

  late Future<Object?> Function(MethodCall methodCall) methodCallHandler;
  late List<MethodCall> methodCalls;

  setUp(() {
    BiometricStorage.instance = MethodChannelBiometricStorage();
    methodCalls = <MethodCall>[];
    methodCallHandler = (MethodCall methodCall) async {
      if (methodCall.method == 'canAuthenticate') {
        return 'ErrorUnknown';
      }
      throw PlatformException(code: 'NotImplemented');
    };

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      methodCalls.add(methodCall);
      return methodCallHandler(methodCall);
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('canAuthenticate', () {
    test('maps native responses', () async {
      const expectedMappings = <String, CanAuthenticateResponse>{
        'Success': CanAuthenticateResponse.success,
        'ErrorHwUnavailable': CanAuthenticateResponse.errorHwUnavailable,
        'ErrorNoBiometricEnrolled':
            CanAuthenticateResponse.errorNoBiometricEnrolled,
        'ErrorNoHardware': CanAuthenticateResponse.errorNoHardware,
        'ErrorPasscodeNotSet': CanAuthenticateResponse.errorPasscodeNotSet,
        'ErrorUnknown': CanAuthenticateResponse.unsupported,
        'ErrorStatusUnknown': CanAuthenticateResponse.statusUnknown,
      };

      for (final entry in expectedMappings.entries) {
        methodCallHandler = (MethodCall methodCall) async => entry.key;

        final result = await BiometricStorage().canAuthenticate();

        expect(result, entry.value, reason: 'native response ${entry.key}');
      }
    });

    test('passes init options over the channel', () async {
      final options = StorageFileInitOptions(
        authenticationRequired: false,
        androidBiometricOnly: false,
        darwinBiometricOnly: false,
      );
      methodCallHandler = (MethodCall methodCall) async => 'Success';

      await BiometricStorage().canAuthenticate(options: options);

      expect(methodCalls, hasLength(1));
      expect(methodCalls.single.method, 'canAuthenticate');
      expect(methodCalls.single.arguments, <String, dynamic>{
        'options': options.toJson(),
      });
    });

    test('throws for invalid native responses', () async {
      methodCallHandler = (MethodCall methodCall) async => 'DefinitelyNotValid';

      await expectLater(
        BiometricStorage().canAuthenticate(),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('StorageFileInitOptions', () {
    test('serializes configured durations and flags', () {
      final options = StorageFileInitOptions(
        androidAuthenticationValidityDuration: const Duration(seconds: 11),
        darwinTouchIDAuthenticationAllowableReuseDuration:
            const Duration(seconds: 22),
        darwinTouchIDAuthenticationForceReuseContextDuration:
            const Duration(seconds: 33),
        authenticationRequired: false,
        androidBiometricOnly: false,
        darwinBiometricOnly: false,
      );

      expect(options.toJson(), <String, dynamic>{
        'androidAuthenticationValidityDurationSeconds': 11,
        'darwinTouchIDAuthenticationAllowableReuseDurationSeconds': 22,
        'darwinTouchIDAuthenticationForceReuseContextDurationSeconds': 33,
        'authenticationRequired': false,
        'androidBiometricOnly': false,
        'darwinBiometricOnly': false,
      });
    });

    test('supports deprecated authentication validity seconds fallback', () {
      final options = StorageFileInitOptions(
        authenticationValidityDurationSeconds: 7,
      );

      expect(options.toJson(), <String, dynamic>{
        'androidAuthenticationValidityDurationSeconds': 7,
        'darwinTouchIDAuthenticationAllowableReuseDurationSeconds': 7,
        'darwinTouchIDAuthenticationForceReuseContextDurationSeconds': null,
        'authenticationRequired': true,
        'androidBiometricOnly': true,
        'darwinBiometricOnly': true,
      });
    });
  });

  group('storage operations', () {
    test('initializes storage and forwards read write delete calls', () async {
      const promptInfo = PromptInfo(
        macOsPromptInfo: IosPromptInfo(
          saveTitle: 'Save title',
          accessTitle: 'Access title',
        ),
      );
      final options = StorageFileInitOptions(
        authenticationRequired: false,
        androidBiometricOnly: false,
        darwinBiometricOnly: false,
      );

      methodCallHandler = (MethodCall methodCall) async {
        switch (methodCall.method) {
          case 'init':
            return true;
          case 'read':
            return 'stored value';
          case 'write':
          case 'delete':
            return true;
        }
        throw PlatformException(code: 'NotImplemented');
      };

      final storage = await BiometricStorage().getStorage(
        'secret-name',
        options: options,
        forceInit: true,
        promptInfo: promptInfo,
      );

      expect(storage.name, 'secret-name');
      expect(await storage.read(), 'stored value');
      await storage.write('next value');
      await storage.delete();

      expect(
        methodCalls.map((methodCall) => methodCall.method),
        <String>['init', 'read', 'write', 'delete'],
      );
      expect(methodCalls[0].arguments, <String, dynamic>{
        'name': 'secret-name',
        'options': options.toJson(),
        'forceInit': true,
      });
      expect(methodCalls[1].arguments, <String, dynamic>{
        'name': 'secret-name',
        'forceBiometricAuthentication': false,
        'iosPromptInfo': <String, dynamic>{
          'saveTitle': 'Save title',
          'accessTitle': 'Access title',
        },
      });
      expect(methodCalls[2].arguments, <String, dynamic>{
        'name': 'secret-name',
        'content': 'next value',
        'forceBiometricAuthentication': false,
        'iosPromptInfo': <String, dynamic>{
          'saveTitle': 'Save title',
          'accessTitle': 'Access title',
        },
      });
      expect(methodCalls[3].arguments, <String, dynamic>{
        'name': 'secret-name',
        'iosPromptInfo': <String, dynamic>{
          'saveTitle': 'Save title',
          'accessTitle': 'Access title',
        },
      });
    });

    test('allows overriding prompt info per operation', () async {
      const defaultPromptInfo = PromptInfo(
        macOsPromptInfo: IosPromptInfo(
          saveTitle: 'Default save',
          accessTitle: 'Default access',
        ),
      );
      const overridePromptInfo = PromptInfo(
        macOsPromptInfo: IosPromptInfo(
          saveTitle: 'Override save',
          accessTitle: 'Override access',
        ),
      );

      methodCallHandler = (MethodCall methodCall) async {
        switch (methodCall.method) {
          case 'init':
            return true;
          case 'read':
            return 'value';
          case 'write':
          case 'delete':
            return true;
        }
        throw PlatformException(code: 'NotImplemented');
      };

      final storage = await BiometricStorage().getStorage(
        'overridden-secret',
        promptInfo: defaultPromptInfo,
      );

      await storage.read(promptInfo: overridePromptInfo);
      await storage.write('content', promptInfo: overridePromptInfo);
      await storage.delete(promptInfo: overridePromptInfo);

      for (final methodCall in methodCalls.skip(1)) {
        expect(methodCall.arguments['iosPromptInfo'], <String, dynamic>{
          'saveTitle': 'Override save',
          'accessTitle': 'Override access',
        });
      }
    });

    test('deleteAndDispose forwards delete then dispose', () async {
      methodCallHandler = (MethodCall methodCall) async {
        switch (methodCall.method) {
          case 'init':
          case 'delete':
          case 'dispose':
            return true;
        }
        throw PlatformException(code: 'NotImplemented');
      };

      final storage = await BiometricStorage().getStorage('dispose-secret');

      await storage.deleteAndDispose();

      expect(
        methodCalls.map((methodCall) => methodCall.method),
        <String>['init', 'delete', 'dispose'],
      );
      expect(methodCalls[1].arguments, <String, dynamic>{
        'name': 'dispose-secret',
        'iosPromptInfo': <String, dynamic>{
          'saveTitle': 'Unlock to save data',
          'accessTitle': 'Unlock to access data',
        },
      });
      expect(methodCalls[2].arguments, <String, dynamic>{
        'name': 'dispose-secret',
        'iosPromptInfo': <String, dynamic>{
          'saveTitle': 'Unlock to save data',
          'accessTitle': 'Unlock to access data',
        },
      });
    });
  });

  group('platform error translation', () {
    test('maps auth-related platform exceptions', () async {
      const expectedMappings = <String, AuthExceptionCode>{
        'AuthError:UserCanceled': AuthExceptionCode.userCanceled,
        'AuthError:Canceled': AuthExceptionCode.canceled,
        'AuthError:Timeout': AuthExceptionCode.timeout,
        'AuthError:SomethingElse': AuthExceptionCode.unknown,
      };

      for (final entry in expectedMappings.entries) {
        methodCallHandler = (MethodCall methodCall) async {
          if (methodCall.method == 'init') {
            return true;
          }
          throw PlatformException(code: entry.key, message: 'boom');
        };

        final storage = await BiometricStorage().getStorage('auth-errors');

        await expectLater(
          storage.read(),
          throwsA(
            isA<AuthException>()
                .having((e) => e.code, 'code', entry.value)
                .having((e) => e.message, 'message', 'boom'),
          ),
          reason: 'platform error ${entry.key}',
        );
      }
    });

    test('maps AppArmor platform errors to auth exception', () async {
      methodCallHandler = (MethodCall methodCall) async {
        if (methodCall.method == 'init') {
          return true;
        }
        throw PlatformException(
          code: 'OtherError',
          message: 'denied',
          details: <String, dynamic>{
            'message': 'org.freedesktop.DBus.Error.AccessDenied',
          },
        );
      };

      final storage = await BiometricStorage().getStorage('linux-errors');

      await expectLater(
        storage.read(),
        throwsA(
          isA<AuthException>().having(
            (e) => e.code,
            'code',
            AuthExceptionCode.linuxAppArmorDenied,
          ),
        ),
      );
    });
  });
}
