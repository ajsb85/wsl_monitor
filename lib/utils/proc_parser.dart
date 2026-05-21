import 'dart:io';

class CpuStats {
  final int total;
  final int idle;
  final double usagePercentage;
  final List<double> coresUsage;

  CpuStats({
    required this.total,
    required this.idle,
    required this.usagePercentage,
    required this.coresUsage,
  });

  static CpuStats empty() {
    return CpuStats(total: 0, idle: 0, usagePercentage: 0.0, coresUsage: []);
  }
}

class MemoryStats {
  final int totalKb;
  final int freeKb;
  final int availableKb;
  final int buffersKb;
  final int cachedKb;
  final int swapTotalKb;
  final int swapFreeKb;

  MemoryStats({
    required this.totalKb,
    required this.freeKb,
    required this.availableKb,
    required this.buffersKb,
    required this.cachedKb,
    required this.swapTotalKb,
    required this.swapFreeKb,
  });

  double get usedPercentage => totalKb > 0 ? ((totalKb - availableKb) / totalKb) * 100.0 : 0.0;
  double get swapUsedPercentage => swapTotalKb > 0 ? ((swapTotalKb - swapFreeKb) / swapTotalKb) * 100.0 : 0.0;
  double get activeMb => (totalKb - freeKb - buffersKb - cachedKb) / 1024.0;
  double get cachedMb => (buffersKb + cachedKb) / 1024.0;
  double get freeMb => freeKb / 1024.0;
  double get totalMb => totalKb / 1024.0;
  double get availableMb => availableKb / 1024.0;
  double get swapTotalMb => swapTotalKb / 1024.0;
  double get swapUsedMb => (swapTotalKb - swapFreeKb) / 1024.0;

  static MemoryStats empty() {
    return MemoryStats(
      totalKb: 0,
      freeKb: 0,
      availableKb: 0,
      buffersKb: 0,
      cachedKb: 0,
      swapTotalKb: 0,
      swapFreeKb: 0,
    );
  }
}

class NetworkStats {
  final int rxBytes;
  final int txBytes;
  final double downloadSpeedBytesPerSec;
  final double uploadSpeedBytesPerSec;

  NetworkStats({
    required this.rxBytes,
    required this.txBytes,
    required this.downloadSpeedBytesPerSec,
    required this.uploadSpeedBytesPerSec,
  });

  static NetworkStats empty() {
    return NetworkStats(rxBytes: 0, txBytes: 0, downloadSpeedBytesPerSec: 0.0, uploadSpeedBytesPerSec: 0.0);
  }
}

class DiskStats {
  final int readBytes;
  final int writeBytes;
  final double readSpeedBytesPerSec;
  final double writeSpeedBytesPerSec;

  DiskStats({
    required this.readBytes,
    required this.writeBytes,
    required this.readSpeedBytesPerSec,
    required this.writeSpeedBytesPerSec,
  });

  static DiskStats empty() {
    return DiskStats(readBytes: 0, writeBytes: 0, readSpeedBytesPerSec: 0.0, writeSpeedBytesPerSec: 0.0);
  }
}

class ProcessInfo {
  final int pid;
  final String name;
  final double rssMb;
  final double cpuUsage;

  ProcessInfo({
    required this.pid,
    required this.name,
    required this.rssMb,
    required this.cpuUsage,
  });
}

class SystemInfo {
  final String kernelVersion;
  final String cpuModel;
  final double uptimeSeconds;
  final int coreCount;

  SystemInfo({
    required this.kernelVersion,
    required this.cpuModel,
    required this.uptimeSeconds,
    required this.coreCount,
  });

  static SystemInfo empty() {
    return SystemInfo(kernelVersion: 'Unknown', cpuModel: 'Unknown', uptimeSeconds: 0.0, coreCount: 1);
  }
}

class SystemSnapshot {
  final CpuStats cpu;
  final MemoryStats memory;
  final NetworkStats network;
  final DiskStats disk;
  final List<ProcessInfo> topProcesses;
  final SystemInfo sysInfo;
  final DateTime timestamp;

  SystemSnapshot({
    required this.cpu,
    required this.memory,
    required this.network,
    required this.disk,
    required this.topProcesses,
    required this.sysInfo,
    required this.timestamp,
  });
}

class ProcParser {
  // Previous states for calculating deltas
  static int _prevCpuTotal = 0;
  static int _prevCpuIdle = 0;
  static List<int> _prevCoresTotal = [];
  static List<int> _prevCoresIdle = [];

  static int _prevRxBytes = 0;
  static int _prevTxBytes = 0;
  static DateTime? _prevNetTime;

  static int _prevReadSectors = 0;
  static int _prevWriteSectors = 0;
  static DateTime? _prevDiskTime;

  static final Map<int, int> _prevProcessCpuTime = {};
  static DateTime? _prevProcessTime;

  // Cached system info that doesn't change
  static String _cachedCpuModel = '';
  static int _cachedCoreCount = 0;
  static String _cachedKernelVersion = '';

  static SystemInfo getSystemInfo() {
    try {
      if (_cachedKernelVersion.isEmpty) {
        final versionFile = File('/proc/version');
        if (versionFile.existsSync()) {
          final content = versionFile.readAsStringSync();
          final match = RegExp(r'Linux version ([^\s]+)').firstMatch(content);
          _cachedKernelVersion = match != null ? match.group(1) ?? 'Linux' : 'Linux';
        } else {
          _cachedKernelVersion = Platform.operatingSystemVersion;
        }
      }

      if (_cachedCpuModel.isEmpty) {
        final cpuinfo = File('/proc/cpuinfo');
        if (cpuinfo.existsSync()) {
          final lines = cpuinfo.readAsLinesSync();
          int cores = 0;
          for (final line in lines) {
            if (line.startsWith('model name')) {
              if (_cachedCpuModel.isEmpty) {
                _cachedCpuModel = line.split(':')[1].trim();
              }
            } else if (line.startsWith('processor')) {
              cores++;
            }
          }
          _cachedCoreCount = cores > 0 ? cores : Platform.numberOfProcessors;
        } else {
          _cachedCpuModel = 'Generic x86_64 CPU';
          _cachedCoreCount = Platform.numberOfProcessors;
        }
      }

      double uptime = 0.0;
      final uptimeFile = File('/proc/uptime');
      if (uptimeFile.existsSync()) {
        final content = uptimeFile.readAsStringSync().trim();
        uptime = double.tryParse(content.split(' ')[0]) ?? 0.0;
      }

      return SystemInfo(
        kernelVersion: _cachedKernelVersion,
        cpuModel: _cachedCpuModel,
        uptimeSeconds: uptime,
        coreCount: _cachedCoreCount,
      );
    } catch (_) {
      return SystemInfo.empty();
    }
  }

  static CpuStats getCpuStats() {
    try {
      final file = File('/proc/stat');
      if (!file.existsSync()) return CpuStats.empty();

      final lines = file.readAsLinesSync();
      if (lines.isEmpty) return CpuStats.empty();

      int currentTotal = 0;
      int currentIdle = 0;
      List<int> currentCoresTotal = [];
      List<int> currentCoresIdle = [];

      for (final line in lines) {
        if (line.startsWith('cpu ')) {
          final parts = line.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
          // cpu user nice system idle iowait irq softirq steal guest guest_nice
          if (parts.length >= 5) {
            final user = int.tryParse(parts[1]) ?? 0;
            final nice = int.tryParse(parts[2]) ?? 0;
            final sys = int.tryParse(parts[3]) ?? 0;
            final idle = int.tryParse(parts[4]) ?? 0;
            final iowait = parts.length > 5 ? (int.tryParse(parts[5]) ?? 0) : 0;
            final irq = parts.length > 6 ? (int.tryParse(parts[6]) ?? 0) : 0;
            final softirq = parts.length > 7 ? (int.tryParse(parts[7]) ?? 0) : 0;
            final steal = parts.length > 8 ? (int.tryParse(parts[8]) ?? 0) : 0;

            currentIdle = idle + iowait;
            currentTotal = user + nice + sys + idle + iowait + irq + softirq + steal;
          }
        } else if (line.startsWith('cpu') && !line.startsWith('cpu ')) {
          final parts = line.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
          if (parts.length >= 5) {
            final user = int.tryParse(parts[1]) ?? 0;
            final nice = int.tryParse(parts[2]) ?? 0;
            final sys = int.tryParse(parts[3]) ?? 0;
            final idle = int.tryParse(parts[4]) ?? 0;
            final iowait = parts.length > 5 ? (int.tryParse(parts[5]) ?? 0) : 0;
            final irq = parts.length > 6 ? (int.tryParse(parts[6]) ?? 0) : 0;
            final softirq = parts.length > 7 ? (int.tryParse(parts[7]) ?? 0) : 0;
            final steal = parts.length > 8 ? (int.tryParse(parts[8]) ?? 0) : 0;

            currentCoresIdle.add(idle + iowait);
            currentCoresTotal.add(user + nice + sys + idle + iowait + irq + softirq + steal);
          }
        }
      }

      // Calculate overall CPU usage
      double usagePercentage = 0.0;
      if (_prevCpuTotal > 0) {
        final totalDiff = currentTotal - _prevCpuTotal;
        final idleDiff = currentIdle - _prevCpuIdle;
        if (totalDiff > 0) {
          usagePercentage = (1.0 - (idleDiff / totalDiff)) * 100.0;
        }
      }
      _prevCpuTotal = currentTotal;
      _prevCpuIdle = currentIdle;

      // Calculate per-core CPU usage
      List<double> coresUsage = [];
      if (_prevCoresTotal.length == currentCoresTotal.length) {
        for (int i = 0; i < currentCoresTotal.length; i++) {
          final totalDiff = currentCoresTotal[i] - _prevCoresTotal[i];
          final idleDiff = currentCoresIdle[i] - _prevCoresIdle[i];
          double coreUsage = 0.0;
          if (totalDiff > 0) {
            coreUsage = (1.0 - (idleDiff / totalDiff)) * 100.0;
          }
          coresUsage.add(coreUsage.clamp(0.0, 100.0));
        }
      } else {
        coresUsage = List.filled(currentCoresTotal.length, 0.0);
      }
      _prevCoresTotal = currentCoresTotal;
      _prevCoresIdle = currentCoresIdle;

      return CpuStats(
        total: currentTotal,
        idle: currentIdle,
        usagePercentage: usagePercentage.clamp(0.0, 100.0),
        coresUsage: coresUsage,
      );
    } catch (_) {
      return CpuStats.empty();
    }
  }

  static MemoryStats getMemoryStats() {
    try {
      final file = File('/proc/meminfo');
      if (!file.existsSync()) return MemoryStats.empty();

      final lines = file.readAsLinesSync();
      int total = 0, free = 0, available = 0, buffers = 0, cached = 0;
      int swapTotal = 0, swapFree = 0;

      for (final line in lines) {
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length >= 2) {
          final key = parts[0].replaceAll(':', '');
          final val = int.tryParse(parts[1]) ?? 0;
          switch (key) {
            case 'MemTotal':
              total = val;
              break;
            case 'MemFree':
              free = val;
              break;
            case 'MemAvailable':
              available = val;
              break;
            case 'Buffers':
              buffers = val;
              break;
            case 'Cached':
              cached = val;
              break;
            case 'SwapTotal':
              swapTotal = val;
              break;
            case 'SwapFree':
              swapFree = val;
              break;
          }
        }
      }

      // Fallback if MemAvailable is not supported (old kernels)
      if (available == 0) {
        available = free + buffers + cached;
      }

      return MemoryStats(
        totalKb: total,
        freeKb: free,
        availableKb: available,
        buffersKb: buffers,
        cachedKb: cached,
        swapTotalKb: swapTotal,
        swapFreeKb: swapFree,
      );
    } catch (_) {
      return MemoryStats.empty();
    }
  }

  static NetworkStats getNetworkStats() {
    try {
      final file = File('/proc/net/dev');
      if (!file.existsSync()) return NetworkStats.empty();

      final lines = file.readAsLinesSync();
      int totalRx = 0;
      int totalTx = 0;

      for (final line in lines) {
        // Skip header lines
        if (line.contains('|') || line.trim().startsWith('Inter-')) continue;
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length >= 10) {
          final face = parts[0];
          // Skip loopback interface
          if (face.startsWith('lo:')) continue;

          final rx = int.tryParse(parts[1]) ?? 0;
          final tx = int.tryParse(parts[9]) ?? 0;
          totalRx += rx;
          totalTx += tx;
        }
      }

      final now = DateTime.now();
      double dlSpeed = 0.0;
      double ulSpeed = 0.0;

      if (_prevNetTime != null && _prevRxBytes > 0) {
        final timeDiffSec = now.difference(_prevNetTime!).inMilliseconds / 1000.0;
        if (timeDiffSec > 0) {
          dlSpeed = (totalRx - _prevRxBytes) / timeDiffSec;
          ulSpeed = (totalTx - _prevTxBytes) / timeDiffSec;
        }
      }

      _prevRxBytes = totalRx;
      _prevTxBytes = totalTx;
      _prevNetTime = now;

      return NetworkStats(
        rxBytes: totalRx,
        txBytes: totalTx,
        downloadSpeedBytesPerSec: dlSpeed >= 0 ? dlSpeed : 0.0,
        uploadSpeedBytesPerSec: ulSpeed >= 0 ? ulSpeed : 0.0,
      );
    } catch (_) {
      return NetworkStats.empty();
    }
  }

  static DiskStats getDiskStats() {
    try {
      final file = File('/proc/diskstats');
      if (!file.existsSync()) return DiskStats.empty();

      final lines = file.readAsLinesSync();
      int totalReadSectors = 0;
      int totalWriteSectors = 0;

      for (final line in lines) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length >= 10) {
          final deviceName = parts[2];
          // Track physical drives e.g. sda, nvme0n1, etc.
          // Skip loop, ram, and partition names (ending with numbers e.g. sda1, nvme0n1p1)
          if (RegExp(r'^(sd[a-z]|nvme\d+n\d+|vd[a-z])$').hasMatch(deviceName)) {
            final readSectors = int.tryParse(parts[5]) ?? 0;
            final writeSectors = int.tryParse(parts[9]) ?? 0;
            totalReadSectors += readSectors;
            totalWriteSectors += writeSectors;
          }
        }
      }

      final now = DateTime.now();
      double readSpeed = 0.0;
      double writeSpeed = 0.0;

      // Sectors are typically 512 bytes
      final currentReadBytes = totalReadSectors * 512;
      final currentWriteBytes = totalWriteSectors * 512;

      if (_prevDiskTime != null && _prevReadSectors > 0) {
        final timeDiffSec = now.difference(_prevDiskTime!).inMilliseconds / 1000.0;
        if (timeDiffSec > 0) {
          readSpeed = (currentReadBytes - (_prevReadSectors * 512)) / timeDiffSec;
          writeSpeed = (currentWriteBytes - (_prevWriteSectors * 512)) / timeDiffSec;
        }
      }

      _prevReadSectors = totalReadSectors;
      _prevWriteSectors = totalWriteSectors;
      _prevDiskTime = now;

      return DiskStats(
        readBytes: currentReadBytes,
        writeBytes: currentWriteBytes,
        readSpeedBytesPerSec: readSpeed >= 0 ? readSpeed : 0.0,
        writeSpeedBytesPerSec: writeSpeed >= 0 ? writeSpeed : 0.0,
      );
    } catch (_) {
      return DiskStats.empty();
    }
  }

  static List<ProcessInfo> getTopProcesses(int limit) {
    try {
      final procDir = Directory('/proc');
      if (!procDir.existsSync()) return [];

      final now = DateTime.now();
      double timeDiffSec = 1.0;
      if (_prevProcessTime != null) {
        timeDiffSec = now.difference(_prevProcessTime!).inMilliseconds / 1000.0;
      }
      if (timeDiffSec <= 0) timeDiffSec = 1.0;

      final List<ProcessInfo> list = [];
      final entities = procDir.listSync();

      // Get system ticks per second (usually 100)
      // Reading from ticks is safe, we default to 100
      final double ticksPerSec = 100.0;

      for (final entity in entities) {
        final path = entity.path;
        final name = path.substring(path.lastIndexOf('/') + 1);
        final pid = int.tryParse(name);
        if (pid == null) continue; // Not a process directory

        try {
          // Read process stat: pid (name) state ppid pgrp session tty_nr tpgid flags minflt cminflt majflt cmajflt utime stime ...
          final statFile = File('$path/stat');
          if (!statFile.existsSync()) continue;

          final statStr = statFile.readAsStringSync();
          final openParen = statStr.indexOf('(');
          final closeParen = statStr.lastIndexOf(')');
          if (openParen == -1 || closeParen == -1) continue;

          final procName = statStr.substring(openParen + 1, closeParen);
          final rest = statStr.substring(closeParen + 2).trim().split(' ');

          // utime is 12th value after name, stime is 13th
          // Since index 0 in `rest` is state (3rd in stat), utime is at index 11, stime at 12
          if (rest.length < 13) continue;
          final utime = int.tryParse(rest[11]) ?? 0;
          final stime = int.tryParse(rest[12]) ?? 0;
          final totalTime = utime + stime;

          // Read process status for memory (VmRSS)
          final statusFile = File('$path/status');
          int rssKb = 0;
          if (statusFile.existsSync()) {
            final lines = statusFile.readAsLinesSync();
            for (final line in lines) {
              if (line.startsWith('VmRSS:')) {
                rssKb = int.tryParse(line.split(RegExp(r'\s+'))[1]) ?? 0;
                break;
              }
            }
          }

          // Calculate CPU usage
          double cpuUsage = 0.0;
          final prevTime = _prevProcessCpuTime[pid];
          if (prevTime != null) {
            final ticksDiff = totalTime - prevTime;
            cpuUsage = (ticksDiff / ticksPerSec) / timeDiffSec * 100.0;
          }
          _prevProcessCpuTime[pid] = totalTime;

          list.add(ProcessInfo(
            pid: pid,
            name: procName,
            rssMb: rssKb / 1024.0,
            cpuUsage: cpuUsage.clamp(0.0, 100.0),
          ));
        } catch (_) {
          // Process exited during parsing
        }
      }

      // Cleanup dead processes from cache
      final currentPids = list.map((p) => p.pid).toSet();
      _prevProcessCpuTime.removeWhere((pid, _) => !currentPids.contains(pid));

      _prevProcessTime = now;

      // Sort by CPU usage desc, then RSS desc
      list.sort((a, b) {
        int cmp = b.cpuUsage.compareTo(a.cpuUsage);
        if (cmp != 0) return cmp;
        return b.rssMb.compareTo(a.rssMb);
      });

      return list.take(limit).toList();
    } catch (_) {
      return [];
    }
  }

  static SystemSnapshot getSnapshot({int processLimit = 15}) {
    final sysInfo = getSystemInfo();
    final cpu = getCpuStats();
    final memory = getMemoryStats();
    final network = getNetworkStats();
    final disk = getDiskStats();
    final topProcesses = getTopProcesses(processLimit);

    return SystemSnapshot(
      cpu: cpu,
      memory: memory,
      network: network,
      disk: disk,
      topProcesses: topProcesses,
      sysInfo: sysInfo,
      timestamp: DateTime.now(),
    );
  }
}
