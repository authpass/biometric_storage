import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

import 'biometric_storage_platform.dart';
import 'types.dart';

abstract class MethodChannelBiometricStoragePlatform
    extends BiometricStoragePlatform {
  MethodChannelBiometricStoragePlatform();

  static const MethodChannel channel = MethodChannel('biometric_storage');
  static final Logger logger = Logger('biometric_storage');

  Map<String, dynamic> buildPromptInfoArguments(PromptInfo promptInfo);

  @override
  Future<bool?> init(
    String name, {
    StorageFileInitOptions? options,
    bool forceInit = false,
  }) =>
      transformErrors(
        channel.invokeMethod<bool>(
          'init',
          <String, dynamic>{
            'name': name,
            'options': options?.toJson() ?? StorageFileInitOptions().toJson(),
            'forceInit': forceInit,
          },
        ),
      );

  @override
  Future<String?> read(
    String name,
    PromptInfo promptInfo, {
    bool forceBiometricAuthentication = false,
  }) =>
      transformErrors(
        channel.invokeMethod<String>(
          'read',
          <String, dynamic>{
            'name': name,
            'forceBiometricAuthentication': forceBiometricAuthentication,
            ...buildPromptInfoArguments(promptInfo),
          },
        ),
      );

  @override
  Future<bool?> delete(
    String name,
    PromptInfo promptInfo,
  ) =>
      transformErrors(
        channel.invokeMethod<bool>(
          'delete',
          <String, dynamic>{
            'name': name,
            ...buildPromptInfoArguments(promptInfo),
          },
        ),
      );

  @override
  Future<void> write(
    String name,
    String content,
    PromptInfo promptInfo, {
    bool forceBiometricAuthentication = false,
  }) =>
      transformErrors(
        channel.invokeMethod<void>(
          'write',
          <String, dynamic>{
            'name': name,
            'content': content,
            'forceBiometricAuthentication': forceBiometricAuthentication,
            ...buildPromptInfoArguments(promptInfo),
          },
        ),
      );

  @override
  Future<void> dispose(
    String name,
    PromptInfo promptInfo,
  ) =>
      transformErrors(
        channel.invokeMethod<void>(
          'dispose',
          <String, dynamic>{
            'name': name,
            ...buildPromptInfoArguments(promptInfo),
          },
        ),
      );

  Future<T> transformErrors<T>(Future<T> future) =>
      future.catchError((Object error, StackTrace stackTrace) {
        if (error is PlatformException) {
          logger.finest(
            'Error during plugin operation (details: ${error.details})',
            error,
            stackTrace,
          );
          if (error.code.startsWith('AuthError:')) {
            return Future<T>.error(
              AuthException(
                authErrorCodeMapping[error.code] ?? AuthExceptionCode.unknown,
                error.message ?? 'Unknown error',
              ),
              stackTrace,
            );
          }
          if (error.details is Map) {
            final message = error.details['message'] as String;
            if (message.contains('org.freedesktop.DBus.Error.AccessDenied') ||
                message.contains('AppArmor')) {
              logger.fine('Got app armor error.');
              return Future<T>.error(
                AuthException(
                  AuthExceptionCode.linuxAppArmorDenied,
                  error.message ?? 'Unknown error',
                ),
                stackTrace,
              );
            }
          }
        }
        return Future<T>.error(error, stackTrace);
      });
}
