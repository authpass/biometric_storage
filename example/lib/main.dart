import 'package:biometric_storage/biometric_storage.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:logging_appenders/logging_appenders.dart';

final MemoryAppender logMessages = MemoryAppender();

final _logger = Logger('main');

void main() {
  Logger.root.level = Level.ALL;
  logMessages.attachToLogger(Logger.root);
  _logger.fine('Application launched.');
  runApp(MyApp());
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

class MemoryAppender extends BaseLogAppender {
  MemoryAppender() : super(null);

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
  final String name = 'default3';
  BiometricStorageFile _storage;

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
                _logger.finer('Initializing $name');
                if ((await _checkAuthenticate()) !=
                    CanAuthenticateResponse.success) {
                  _logger.severe(
                      'Unable to use authenticate. Unable to getting storage.');
                  return;
                }
                _storage = await BiometricStorage().getStorage(name,
                    options: AndroidInitOptions(
                        authenticationValidityDurationSeconds: 30));
                setState(() {});
                _logger.info('initiailzed $name');
              },
            ),
            ..._storage == null
                ? []
                : [
                    RaisedButton(
                      child: const Text('read'),
                      onPressed: () async {
                        _logger.fine('reading from ${_storage.name}');
                        final result = await _storage.read();
                        _logger.fine('read: {$result}');
                      },
                    ),
                    const Divider(),
                    TextField(
                      decoration: InputDecoration(
                        labelText: 'Example text to write',
                      ),
                      controller: _writeController,
                    ),
                    RaisedButton(
                      child: const Text('write'),
                      onPressed: () async {
                        _logger.fine('Going to write...');
                        await _storage.write(
                            ' [${DateTime.now()}] ${_writeController.text}');
                        _logger.info('Written content.');
                      },
                    ),
                  ],
            Expanded(
              child: Container(
                color: Colors.white,
                constraints: BoxConstraints.expand(),
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
