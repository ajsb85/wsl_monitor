import 'dart:async';
import 'dart:isolate';
import 'proc_parser.dart';

class MonitorCommand {
  final String action;
  final dynamic payload;

  MonitorCommand(this.action, this.payload);
}

class MonitorWorker {
  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _commandPort;
  StreamSubscription? _subscription;

  void start({
    required Function(SystemSnapshot) onSnapshot,
    Duration interval = const Duration(seconds: 1),
    int processLimit = 15,
  }) async {
    // Clean up if already running
    stop();

    _receivePort = ReceivePort();

    // Spawn the isolate
    _isolate = await Isolate.spawn(
      _isolateEntryPoint,
      _receivePort!.sendPort,
    );

    // Listen to messages from the isolate
    _subscription = _receivePort!.listen((message) {
      if (message is SendPort) {
        _commandPort = message;
        // Send initial config
        _commandPort?.send(MonitorCommand('config', {
          'intervalMs': interval.inMilliseconds,
          'processLimit': processLimit,
        }));
      } else if (message is SystemSnapshot) {
        onSnapshot(message);
      }
    });
  }

  void updateInterval(Duration interval) {
    _commandPort?.send(MonitorCommand('config', {
      'intervalMs': interval.inMilliseconds,
    }));
  }

  void updateProcessLimit(int limit) {
    _commandPort?.send(MonitorCommand('config', {
      'processLimit': limit,
    }));
  }

  void triggerGarbageCollection() {
    _commandPort?.send(MonitorCommand('gc', null));
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;

    _receivePort?.close();
    _receivePort = null;

    _isolate?.kill(priority: Isolate.beforeNextEvent);
    _isolate = null;

    _commandPort = null;
  }

  // The entry point for the isolate
  static void _isolateEntryPoint(SendPort mainSendPort) {
    final commandPort = ReceivePort();
    mainSendPort.send(commandPort.sendPort);

    Timer? timer;
    Duration interval = const Duration(seconds: 1);
    int processLimit = 15;

    // Helper to run parser and send snapshot
    void tick() {
      // Warm up parser to establish first baseline if not already done
      final snapshot = ProcParser.getSnapshot(processLimit: processLimit);
      mainSendPort.send(snapshot);
    }

    void restartTimer() {
      timer?.cancel();
      timer = Timer.periodic(interval, (_) => tick());
    }

    commandPort.listen((message) {
      if (message is MonitorCommand) {
        switch (message.action) {
          case 'config':
            final map = message.payload as Map<String, dynamic>;
            bool needsRestart = false;

            if (map.containsKey('intervalMs')) {
              final newInterval = Duration(milliseconds: map['intervalMs'] as int);
              if (newInterval != interval) {
                interval = newInterval;
                needsRestart = true;
              }
            }

            if (map.containsKey('processLimit')) {
              processLimit = map['processLimit'] as int;
            }

            if (needsRestart || timer == null) {
              restartTimer();
            }
            break;
          case 'gc':
            // System snapshots generate small transient objects, 
            // trigger a hint or let Dart vm run normal collection.
            break;
          case 'stop':
            timer?.cancel();
            commandPort.close();
            break;
        }
      }
    });

    // Run first tick immediately
    tick();
    restartTimer();
  }
}
