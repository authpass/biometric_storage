import 'dart:io';

import 'package:biometric_storage/biometric_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:logging_appenders/logging_appenders.dart';

final MemoryAppender logMessages = MemoryAppender();

final _logger = Logger('main');

void main() {
  Logger.root.level = Level.ALL;
  PrintAppender().attachToLogger(Logger.root);
  logMessages.attachToLogger(Logger.root);
  _logger.fine('Application launched.');
  _setTargetPlatformForDesktop();
  runApp(MyApp());
}

/// If the current platform is desktop, override the default platform to
/// a supported platform (iOS for macOS, Android for Linux and Windows).
/// Otherwise, do nothing.
void _setTargetPlatformForDesktop() {
  TargetPlatform targetPlatform;
  if (Platform.isLinux || Platform.isWindows) {
    targetPlatform = TargetPlatform.android;
  }
  _logger.info('targetPlatform: $targetPlatform');
  if (targetPlatform != null) {
    debugDefaultTargetPlatformOverride = targetPlatform;
  }
}

class StringBufferWrapper with ChangeNotifier {
  final StringBuffer _buffer = StringBuffer();

  void writeln(String line) {
    _buffer.writeln(line);
    notifyListeners();
  }

  @override
  String toString() => _buffer.toString();
}

class ShortFormatter extends LogRecordFormatter {
  @override
  StringBuffer formatToStringBuffer(LogRecord rec, StringBuffer sb) {
    sb.write(
        '${rec.time.hour}:${rec.time.minute}:${rec.time.second} ${rec.level.name} '
        '${rec.message}');

    if (rec.error != null) {
      sb.write(rec.error);
    }
    // ignore: avoid_as
    final stackTrace = rec.stackTrace ??
        (rec.error is Error ? (rec.error as Error).stackTrace : null);
    if (stackTrace != null) {
      sb.write(stackTrace);
    }
    return sb;
  }
}

class MemoryAppender extends BaseLogAppender {
  MemoryAppender() : super(ShortFormatter());

  final StringBufferWrapper log = StringBufferWrapper();

  @override
  void handle(LogRecord record) {
    log.writeln(formatter.format(record));
  }
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final String baseName = 'default';
  BiometricStorageFile _authStorage;
  BiometricStorageFile _storage;
  BiometricStorageFile _customPrompt;
  BiometricStorageFile _noConfirmation;

  final TextEditingController _writeController =
      TextEditingController(text: 'Lorem Ipsum');

  @override
  void initState() {
    super.initState();
    logMessages.log.addListener(_logChanged);
    _checkAuthenticate();
  }

  @override
  void dispose() {
    logMessages.log.removeListener(_logChanged);
    super.dispose();
  }

  Future<CanAuthenticateResponse> _checkAuthenticate() async {
    final response = await BiometricStorage().canAuthenticate();
    _logger.info('checked if authentication was possible: $response');
    return response;
  }

  void _logChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Column(
          children: [
            const Text('Methods:'),
            RaisedButton(
              child: const Text('init'),
              onPressed: () async {
                _logger.finer('Initializing $baseName');
                final authenticate = await _checkAuthenticate();
                bool supportsAuthenticated = false;
                if (authenticate == CanAuthenticateResponse.success) {
                  supportsAuthenticated = true;
                } else if (authenticate !=
                    CanAuthenticateResponse.unsupported) {
                  supportsAuthenticated = false;
                } else {
                  _logger.severe(
                      'Unable to use authenticate. Unable to get storage.');
                  return;
                }
                if (supportsAuthenticated) {
                  _authStorage = await BiometricStorage().getStorage(
                      '${baseName}_authenticated',
                      options: StorageFileInitOptions(
                          authenticationValidityDurationSeconds: 30));
                }
                _storage = await BiometricStorage()
                    .getStorage('${baseName}_unauthenticated',
                        options: StorageFileInitOptions(
                          authenticationRequired: false,
                        ));
                if (supportsAuthenticated) {
                  _customPrompt = await BiometricStorage().getStorage(
                      '${baseName}_customPrompt',
                      options: StorageFileInitOptions(
                          authenticationValidityDurationSeconds: 30),
                      androidPromptInfo: const AndroidPromptInfo(
                        title: 'Custom title',
                        subtitle: 'Custom subtitle',
                        description: 'Custom description',
                        negativeButton: 'Nope!',
                      ));
                  _noConfirmation = await BiometricStorage().getStorage(
                      '${baseName}_customPrompt',
                      options: StorageFileInitOptions(
                          authenticationValidityDurationSeconds: 30),
                      androidPromptInfo: const AndroidPromptInfo(
                        confirmationRequired: false,
                      ));
                }
                setState(() {});
                _logger.info('initiailzed $baseName');
              },
            ),
            ...(_authStorage == null
                ? []
                : [
                    const Text('Biometric Authentication',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    StorageActions(
                        storageFile: _authStorage,
                        writeController: _writeController),
                    const Divider(),
                  ]),
            ...?(_storage == null
                ? null
                : [
                    const Text('Unauthenticated',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    StorageActions(
                        storageFile: _storage,
                        writeController: _writeController),
                    const Divider(),
                  ]),
            ...?(_customPrompt == null
                ? null
                : [
                    const Text('Custom Authentication Prompt (Android)',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    StorageActions(
                        storageFile: _customPrompt,
                        writeController: _writeController),
                    const Divider(),
                  ]),
            ...?(_noConfirmation == null
                ? null
                : [
                    const Text('No Confirmation Prompt (Android)',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    StorageActions(
                        storageFile: _noConfirmation,
                        writeController: _writeController),
                  ]),
            const Divider(),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Example text to write',
              ),
              controller: _writeController,
            ),
            Expanded(
              child: Container(
                color: Colors.white,
                constraints: const BoxConstraints.expand(),
                child: SingleChildScrollView(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      logMessages.log.toString(),
                    ),
                  ),
                  reverse: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StorageActions extends StatelessWidget {
  const StorageActions(
      {Key key, @required this.storageFile, @required this.writeController})
      : super(key: key);

  final BiometricStorageFile storageFile;
  final TextEditingController writeController;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: <Widget>[
        RaisedButton(
          child: const Text('read'),
          onPressed: () async {
            _logger.fine('reading from ${storageFile.name}');
            final result = await storageFile.read();
            _logger.fine('read: {$result}');
          },
        ),
        RaisedButton(
          child: const Text('write'),
          onPressed: () async {
            _logger.fine('Going to write...');
            await storageFile
                .write(' [${DateTime.now()}] ${writeController.text}');
            _logger.info('Written content.');
          },
        ),
        RaisedButton(
          child: const Text('delete'),
          onPressed: () async {
            _logger.fine('deleting...');
            await storageFile.delete();
            _logger.info('Deleted.');
          },
        ),
      ],
    );
  }
}
