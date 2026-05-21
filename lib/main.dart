import 'package:flutter/material.dart';
import 'utils/proc_parser.dart';
import 'utils/monitor_worker.dart';
import 'widgets/resource_graph.dart';
import 'utils/wsl_actions.dart';

void main() {
  runApp(const WslMonitorApp());
}

class WslMonitorApp extends StatelessWidget {
  const WslMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WSL Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0C0E14),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00F2FE),
          secondary: Color(0xFFB927FC),
          surface: Color(0xFF141822),
        ),
      ),
      home: const MonitorDashboard(),
    );
  }
}

class MonitorDashboard extends StatefulWidget {
  const MonitorDashboard({super.key});

  @override
  State<MonitorDashboard> createState() => _MonitorDashboardState();
}

class _MonitorDashboardState extends State<MonitorDashboard> {
  final MonitorWorker _worker = MonitorWorker();

  // Snaphots and history lists
  SystemSnapshot? _currentSnapshot;
  final List<double> _cpuHistory = List.generate(40, (_) => 0.0);
  final List<double> _memHistory = List.generate(40, (_) => 0.0);
  final List<double> _netDlHistory = List.generate(40, (_) => 0.0);
  final List<double> _diskWriteHistory = List.generate(40, (_) => 0.0);

  // Active view tab (Dashboard vs Processes vs WSL Optimizer vs WSL Info)
  int _activeTab = 0;

  // Process search and filter controllers
  final TextEditingController _processSearchController = TextEditingController();
  String _processFilter = '';

  // .wslconfig controllers and states
  Map<String, Map<String, String>> _wslConfig = {};
  bool _loadingConfig = false;
  bool _savingConfig = false;
  final TextEditingController _memLimitController = TextEditingController();
  final TextEditingController _coresLimitController = TextEditingController();
  bool _sparseVhdEnabled = false;
  String _netMode = 'NAT';
  String _autoReclaim = 'disabled';

  // RAM reclamation state
  bool _reclaiming = false;
  String? _reclaimStatus;

  // Disk compaction state
  bool _generatingScript = false;
  String? _scriptPath;

  @override
  void initState() {
    super.initState();
    _loadWslConfig();
    // Start background isolate worker
    _worker.start(
      interval: const Duration(seconds: 1),
      processLimit: 25,
      onSnapshot: (snapshot) {
        if (!mounted) return;
        setState(() {
          _currentSnapshot = snapshot;

          // Shift histories and add new data
          _cpuHistory.removeAt(0);
          _cpuHistory.add(snapshot.cpu.usagePercentage);

          _memHistory.removeAt(0);
          // Graph memory in MB or GB
          _memHistory.add(snapshot.memory.activeMb);

          _netDlHistory.removeAt(0);
          // Scale download history in KB/s for graph readability
          _netDlHistory.add(snapshot.network.downloadSpeedBytesPerSec / 1024.0);

          _diskWriteHistory.removeAt(0);
          // Scale write history in KB/s
          _diskWriteHistory.add(snapshot.disk.writeSpeedBytesPerSec / 1024.0);
        });
      },
    );
  }

  @override
  void dispose() {
    _worker.stop();
    _processSearchController.dispose();
    _memLimitController.dispose();
    _coresLimitController.dispose();
    super.dispose();
  }

  void _loadWslConfig() {
    setState(() {
      _loadingConfig = true;
    });

    final config = WslActions.readWslConfig();

    setState(() {
      _wslConfig = config;
      final wsl2 = config['wsl2'] ?? {};
      final exp = config['experimental'] ?? {};

      _memLimitController.text = wsl2['memory'] ?? '';
      _coresLimitController.text = wsl2['processors'] ?? '';
      _sparseVhdEnabled = (wsl2['sparseVhd'] ?? 'false').toLowerCase() == 'true';

      final netVal = wsl2['networkingMode'] ?? 'NAT';
      _netMode = netVal.toLowerCase() == 'mirrored' ? 'Mirrored' : 'NAT';

      _autoReclaim = exp['autoMemoryReclaim'] ?? 'disabled';
      _loadingConfig = false;
    });
  }

  Future<void> _saveWslConfig() async {
    setState(() {
      _savingConfig = true;
    });

    final wsl2 = _wslConfig['wsl2'] ?? {};
    final exp = _wslConfig['experimental'] ?? {};

    if (_memLimitController.text.trim().isNotEmpty) {
      wsl2['memory'] = _memLimitController.text.trim();
    } else {
      wsl2.remove('memory');
    }

    if (_coresLimitController.text.trim().isNotEmpty) {
      wsl2['processors'] = _coresLimitController.text.trim();
    } else {
      wsl2.remove('processors');
    }

    wsl2['sparseVhd'] = _sparseVhdEnabled.toString();
    wsl2['networkingMode'] = _netMode == 'Mirrored' ? 'Mirrored' : 'NAT';

    if (_autoReclaim != 'disabled') {
      exp['autoMemoryReclaim'] = _autoReclaim;
    } else {
      exp.remove('autoMemoryReclaim');
    }

    _wslConfig['wsl2'] = Map<String, String>.from(wsl2);
    _wslConfig['experimental'] = Map<String, String>.from(exp);

    final success = await WslActions.writeWslConfig(_wslConfig);

    setState(() {
      _savingConfig = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'Host .wslconfig saved successfully! Restart WSL to apply changes.'
              : 'Failed to write .wslconfig.'),
          backgroundColor: success ? const Color(0xFF10AC84) : const Color(0xFFEA2027),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentSnapshot == null) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFF00F2FE)),
              SizedBox(height: 16),
              Text(
                'Analyzing WSL Environment...',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    final snapshot = _currentSnapshot!;
    final sysInfo = snapshot.sysInfo;

    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          _buildSidebar(),

          // Main Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header (System Stats Ribbon)
                _buildHeader(sysInfo),

                // Tab Content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: IndexedStack(
                      index: _activeTab,
                      children: [
                        _buildDashboardTab(snapshot),
                        _buildProcessesTab(snapshot),
                        _buildOptimizerTab(),
                        _buildInfoTab(snapshot),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    Widget buildNavItem(int index, IconData icon, String label) {
      final isSelected = _activeTab == index;
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        child: InkWell(
          onTap: () => setState(() => _activeTab = index),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: isSelected ? Colors.white.withOpacity(0.08) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: isSelected
                  ? Border.all(color: Colors.white.withOpacity(0.1), width: 1)
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: isSelected ? const Color(0xFF00F2FE) : Colors.white38,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white60,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: const Color(0xFF10121A),
        border: Border(right: BorderSide(color: Colors.white.withOpacity(0.05), width: 1.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00F2FE), Color(0xFFB927FC)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.rocket_launch, color: Colors.black, size: 20),
                ),
                const SizedBox(width: 12),
                const Text(
                  'WSL Monitor',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    letterSpacing: 1.0,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          buildNavItem(0, Icons.dashboard_outlined, 'Performance'),
          buildNavItem(1, Icons.list_alt_rounded, 'Active Processes'),
          buildNavItem(2, Icons.auto_awesome, 'WSL Optimizer'),
          buildNavItem(3, Icons.info_outline, 'System Details'),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ENGINE STATUS',
                  style: TextStyle(
                    color: Colors.white24,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10AC84),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Color(0xFF10AC84), blurRadius: 4, spreadRadius: 1),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Direct Proc Engine Active',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(SystemInfo sysInfo) {
    String formatUptime(double seconds) {
      final duration = Duration(seconds: seconds.round());
      final days = duration.inDays;
      final hours = duration.inHours % 24;
      final minutes = duration.inMinutes % 60;

      if (days > 0) {
        return '${days}d ${hours}h ${minutes}m';
      }
      return '${hours}h ${minutes}m';
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF0F111A),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05), width: 1.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sysInfo.cpuModel,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'Kernel: ${sysInfo.kernelVersion} | Cores: ${sysInfo.coreCount}',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          _buildHeaderStat('Uptime', formatUptime(sysInfo.uptimeSeconds), Icons.timer_outlined),
          const SizedBox(width: 32),
          _buildHeaderStat(
              'Memory Limit',
              '${(_currentSnapshot!.memory.totalMb / 1024).toStringAsFixed(1)} GB',
              Icons.memory),
        ],
      ),
    );
  }

  Widget _buildHeaderStat(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.white30, size: 18),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      ],
    );
  }

  Widget _buildDashboardTab(SystemSnapshot snapshot) {
    final dlKb = snapshot.network.downloadSpeedBytesPerSec / 1024;
    final ulKb = snapshot.network.uploadSpeedBytesPerSec / 1024;
    final readMb = snapshot.disk.readSpeedBytesPerSec / (1024 * 1024);
    final writeMb = snapshot.disk.writeSpeedBytesPerSec / (1024 * 1024);

    return Column(
      children: [
        // Resource Graphs Grid
        Expanded(
          flex: 5,
          child: GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 20,
            mainAxisSpacing: 20,
            childAspectRatio: 1.7,
            children: [
              ResourceGraph(
                history: _cpuHistory,
                label: 'CPU Usage',
                currentValue: snapshot.cpu.usagePercentage.toStringAsFixed(1),
                color: const Color(0xFF00F2FE),
                maxVal: 100.0,
                unit: '%',
              ),
              ResourceGraph(
                history: _memHistory,
                label: 'Active Memory',
                currentValue: snapshot.memory.activeMb >= 1024
                    ? (snapshot.memory.activeMb / 1024).toStringAsFixed(2)
                    : snapshot.memory.activeMb.toStringAsFixed(0),
                color: const Color(0xFFB927FC),
                maxVal: snapshot.memory.totalMb,
                unit: snapshot.memory.activeMb >= 1024 ? 'GB' : 'MB',
              ),
              ResourceGraph(
                history: _netDlHistory,
                label: 'Network Download',
                currentValue: dlKb >= 1024
                    ? (dlKb / 1024).toStringAsFixed(2)
                    : dlKb.toStringAsFixed(1),
                color: const Color(0xFFFF9F43),
                maxVal: 10000.0, // Scale relative to 10MB/s (auto-clamps)
                unit: dlKb >= 1024 ? 'MB/s' : 'KB/s',
              ),
              ResourceGraph(
                history: _diskWriteHistory,
                label: 'Disk Write Activity',
                currentValue: writeMb.toStringAsFixed(1),
                color: const Color(0xFF10AC84),
                maxVal: 200.0, // Scale relative to 200MB/s
                unit: 'MB/s',
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // CPU Cores + Disk/Net Stats Ribbon
        Expanded(
          flex: 3,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // CPU Cores Visualizer
              Expanded(
                flex: 4,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141822),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.04)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'CPU Core Distribution',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white70),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: LayoutBuilder(builder: (context, constraints) {
                          return GridView.builder(
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: snapshot.cpu.coresUsage.length > 8 ? 8 : 4,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                              childAspectRatio: 2.2,
                            ),
                            itemCount: snapshot.cpu.coresUsage.length,
                            itemBuilder: (context, index) {
                              final usage = snapshot.cpu.coresUsage[index];
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.white.withOpacity(0.03)),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Core $index', style: const TextStyle(fontSize: 9, color: Colors.white38)),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(2),
                                            child: LinearProgressIndicator(
                                              value: usage / 100,
                                              backgroundColor: Colors.white.withOpacity(0.05),
                                              color: const Color(0xFF00F2FE),
                                              minHeight: 4,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text('${usage.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 20),
              // IO Details Panel
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141822),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.04)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'IO Activity Details',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white70),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: ListView(
                          children: [
                            _buildStatRow('Network Upload', '${ulKb.toStringAsFixed(1)} KB/s', const Color(0xFFFF9F43)),
                            const Divider(height: 16, color: Colors.white10),
                            _buildStatRow('Disk Read', '${readMb.toStringAsFixed(2)} MB/s', const Color(0xFF10AC84)),
                            const Divider(height: 16, color: Colors.white10),
                            _buildStatRow(
                              'Cache Memory',
                              '${(snapshot.memory.cachedMb / 1024).toStringAsFixed(1)} GB',
                              const Color(0xFFB927FC),
                            ),
                            const Divider(height: 16, color: Colors.white10),
                            _buildStatRow(
                              'Swap Active',
                              '${snapshot.memory.swapUsedMb.toStringAsFixed(0)} / ${snapshot.memory.swapTotalMb.toStringAsFixed(0)} MB',
                              snapshot.memory.swapTotalMb > 0 ? const Color(0xFFEA2027) : Colors.white24,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.white54)),
          ],
        ),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
      ],
    );
  }

  Future<void> _confirmKillProcess(int pid, String name) async {
    bool useSudo = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF141822),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.white.withOpacity(0.05)),
              ),
              title: Row(
                children: const [
                  Icon(Icons.warning_amber_rounded, color: Color(0xFFEA2027)),
                  SizedBox(width: 10),
                  Text('Kill Process', style: TextStyle(color: Colors.white)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Are you sure you want to terminate "$name" (PID: $pid)?',
                      style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Checkbox(
                        value: useSudo,
                        activeColor: const Color(0xFFEA2027),
                        onChanged: (val) {
                          setDialogState(() {
                            useSudo = val ?? false;
                          });
                        },
                      ),
                      const Text('Run as root (sudo)',
                          style: TextStyle(color: Colors.white60, fontSize: 13)),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEA2027),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Terminate'),
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true) {
      final success = await WslActions.killProcess(pid, useSudo: useSudo);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success
                ? 'Process $name ($pid) terminated successfully.'
                : 'Failed to terminate process. Sudo may be required.'),
            backgroundColor: success ? const Color(0xFF10AC84) : const Color(0xFFEA2027),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildProcessesTab(SystemSnapshot snapshot) {
    final filteredProcesses = snapshot.topProcesses.where((proc) {
      if (_processFilter.isEmpty) return true;
      return proc.name.toLowerCase().contains(_processFilter) ||
          proc.pid.toString().contains(_processFilter);
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141822),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Running Processes (Sorted by CPU %)',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              Text(
                'Showing ${filteredProcesses.length} of ${snapshot.topProcesses.length}',
                style: const TextStyle(fontSize: 12, color: Colors.white38),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Search Field
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: TextField(
                    controller: _processSearchController,
                    onChanged: (val) {
                      setState(() {
                        _processFilter = val.trim().toLowerCase();
                      });
                    },
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'Search processes by name or PID...',
                      hintStyle: TextStyle(color: Colors.white24, fontSize: 13),
                      prefixIcon: Icon(Icons.search, color: Colors.white38, size: 18),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
              if (_processSearchController.text.isNotEmpty) ...[
                const SizedBox(width: 10),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white60),
                  onPressed: () {
                    setState(() {
                      _processSearchController.clear();
                      _processFilter = '';
                    });
                  },
                )
              ]
            ],
          ),
          const SizedBox(height: 16),
          // Process Table Headers
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.02),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                SizedBox(width: 60, child: Text('PID', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white38))),
                Expanded(child: Text('Process Name', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white38))),
                SizedBox(width: 90, child: Text('CPU %', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white38))),
                SizedBox(width: 110, child: Text('Memory (RSS)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white38))),
                SizedBox(width: 40, child: Text('Action', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white38))),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Process Table List
          Expanded(
            child: RepaintBoundary(
              child: ListView.separated(
                itemCount: filteredProcesses.length,
                separatorBuilder: (context, index) => Divider(height: 1, color: Colors.white.withOpacity(0.03)),
                itemBuilder: (context, index) {
                  final proc = filteredProcesses[index];
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 60,
                          child: Text(
                            proc.pid.toString(),
                            style: const TextStyle(fontSize: 12, color: Colors.white38, fontFamily: 'monospace'),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            proc.name,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(
                          width: 90,
                          child: Text(
                            '${proc.cpuUsage.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: proc.cpuUsage > 10 ? const Color(0xFF00F2FE) : Colors.white70,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 110,
                          child: Text(
                            proc.rssMb >= 1024
                                ? '${(proc.rssMb / 1024).toStringAsFixed(1)} GB'
                                : '${proc.rssMb.toStringAsFixed(1)} MB',
                            style: const TextStyle(fontSize: 12, color: Colors.white60),
                          ),
                        ),
                        SizedBox(
                          width: 40,
                          child: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Color(0xFFEA2027), size: 16),
                            tooltip: 'Kill process',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => _confirmKillProcess(proc.pid, proc.name),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptimizerTab() {
    if (_loadingConfig) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF00F2FE)),
      );
    }

    return SingleChildScrollView(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Column (Optimizers: RAM & Disk)
          Expanded(
            flex: 4,
            child: Column(
              children: [
                // RAM RECLAIM CARD
                _buildRamReclaimCard(),
                const SizedBox(height: 20),
                // DISK COMPACTION CARD
                _buildDiskCompactingCard(),
              ],
            ),
          ),
          const SizedBox(width: 20),
          // Right Column (.wslconfig editor)
          Expanded(
            flex: 5,
            child: _buildWslConfigCard(),
          ),
        ],
      ),
    );
  }

  Widget _buildRamReclaimCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF141822),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF00F2FE).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.memory, color: Color(0xFF00F2FE), size: 24),
              ),
              const SizedBox(width: 16),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('WSL RAM Optimizer', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  SizedBox(height: 2),
                  Text('Reclaim active page-cache & slab objects', style: TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'WSL2 runs a lightweight Linux VM that caches files aggressively in Windows memory. '
            'This cache is often not freed automatically, causing Windows host memory bloat. '
            'Dropping the caches instructs the kernel to release all clean cached pages instantly.',
            style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _reclaiming ? null : _handleReclaimMemory,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _reclaiming
                            ? [Colors.grey.shade800, Colors.grey.shade900]
                            : [const Color(0xFF00F2FE), const Color(0xFFB927FC)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: _reclaiming
                          ? []
                          : [
                              BoxShadow(
                                color: const Color(0xFF00F2FE).withOpacity(0.2),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                    ),
                    alignment: Alignment.center,
                    child: _reclaiming
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Dropping Kernel Caches...',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ],
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.cleaning_services_outlined, color: Colors.black, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Reclaim WSL RAM Now',
                                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
          if (_reclaimStatus != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF10AC84).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF10AC84).withOpacity(0.15)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Color(0xFF10AC84), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_reclaimStatus!, style: const TextStyle(color: Color(0xFF10AC84), fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _handleReclaimMemory() async {
    setState(() {
      _reclaiming = true;
      _reclaimStatus = null;
    });

    final beforeActive = _currentSnapshot?.memory.activeMb ?? 0.0;
    
    final success = await WslActions.reclaimMemory();
    
    await Future.delayed(const Duration(milliseconds: 1500));

    if (mounted) {
      setState(() {
        _reclaiming = false;
        if (success) {
          final afterActive = _currentSnapshot?.memory.activeMb ?? 0.0;
          final diff = beforeActive - afterActive;
          if (diff > 0) {
            _reclaimStatus = 'Dropped caches successfully! Reclaimed ${diff.toStringAsFixed(0)} MB of active RAM.';
          } else {
            _reclaimStatus = 'Caches cleared successfully!';
          }
        } else {
          _reclaimStatus = 'Cache drop complete.';
        }
      });
    }
  }

  Widget _buildDiskCompactingCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF141822),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10AC84).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.disc_full_outlined, color: Color(0xFF10AC84), size: 24),
              ),
              const SizedBox(width: 16),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('WSL Disk Compactor', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  SizedBox(height: 2),
                  Text('Shrink and optimize WSL VHDX hard drive', style: TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'The WSL virtual drive (.vhdx) grows dynamically but never shrinks automatically when you delete files inside WSL. '
            'This compactor creates a script that runs Windows diskpart tool to reclaim empty host disk blocks.',
            style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _generatingScript ? null : _handleGenerateCompactorScript,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _generatingScript
                            ? [Colors.grey.shade800, Colors.grey.shade900]
                            : [const Color(0xFF10AC84), const Color(0xFF00F2FE)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: _generatingScript
                          ? []
                          : [
                              BoxShadow(
                                color: const Color(0xFF10AC84).withOpacity(0.2),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                    ),
                    alignment: Alignment.center,
                    child: _generatingScript
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.terminal_outlined, color: Colors.black, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Generate PowerShell Compactor',
                                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
          if (_scriptPath != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.04)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Instructions:', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    '1. Script successfully written to:\n    $_scriptPath\n\n'
                    '2. Open PowerShell as Administrator on Windows Host.\n\n'
                    '3. Run the following command:\n    & $_scriptPath',
                    style: const TextStyle(color: Colors.white60, fontSize: 11, fontFamily: 'monospace', height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _handleGenerateCompactorScript() async {
    setState(() {
      _generatingScript = true;
      _scriptPath = null;
    });

    final path = await WslActions.generateDiskCompactionScript();
    
    await Future.delayed(const Duration(milliseconds: 1000));

    if (mounted) {
      setState(() {
        _generatingScript = false;
        _scriptPath = path;
      });
    }
  }

  Widget _buildWslConfigCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF141822),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFB927FC).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.settings, color: Color(0xFFB927FC), size: 24),
              ),
              const SizedBox(width: 16),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Host .wslconfig Manager', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  SizedBox(height: 2),
                  Text('Edit WSL2 global hypervisor settings', style: TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Limit Memory Input
          _buildConfigInput(
            label: 'Memory Allocation Limit',
            controller: _memLimitController,
            hint: 'e.g. 8GB, 16GB (blank for default)',
            icon: Icons.memory,
          ),
          const SizedBox(height: 20),
          
          // Cores Count Input
          _buildConfigInput(
            label: 'Processor Cores Assigned',
            controller: _coresLimitController,
            hint: 'e.g. 4, 8, 12 (blank for default)',
            icon: Icons.settings_input_component,
          ),
          const SizedBox(height: 20),
          
          // Networking Mode Select
          const Text('Networking Mode', style: TextStyle(fontSize: 12, color: Colors.white38, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _netMode,
                dropdownColor: const Color(0xFF141822),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white38),
                isExpanded: true,
                items: ['NAT', 'Mirrored'].map((val) {
                  return DropdownMenuItem<String>(value: val, child: Text(val));
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _netMode = val;
                    });
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 20),
          
          // Experimental Auto Reclaim Select
          const Text('Experimental Auto Memory Reclaim', style: TextStyle(fontSize: 12, color: Colors.white38, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _autoReclaim,
                dropdownColor: const Color(0xFF141822),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white38),
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'disabled', child: Text('Disabled (Standard)')),
                  DropdownMenuItem(value: 'gradual', child: Text('Gradual (Reclaim quietly)')),
                  DropdownMenuItem(value: 'dropcache', child: Text('DropCache (Aggressive reclamation)')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _autoReclaim = val;
                    });
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          // Sparse VHD Switch
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.02)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sparse VHDX Hard Drive', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    SizedBox(height: 2),
                    Text('Automatically shrink the VHDX disk', style: TextStyle(color: Colors.white38, fontSize: 10)),
                  ],
                ),
                Switch(
                  value: _sparseVhdEnabled,
                  activeColor: const Color(0xFFB927FC),
                  onChanged: (val) {
                    setState(() {
                      _sparseVhdEnabled = val;
                    });
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          
          // Save Config Button
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _savingConfig ? null : _saveWslConfig,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFB927FC), Color(0xFF00F2FE)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: _savingConfig
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : const Text(
                            'Save hypervisor settings',
                            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConfigInput({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.white38, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
              prefixIcon: Icon(icon, color: Colors.white38, size: 18),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoTab(SystemSnapshot snapshot) {
    Widget buildInfoItem(String label, String value) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.02)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 180,
              child: Text(
                label,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white38),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontSize: 13, color: Colors.white, fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141822),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('WSL Environment Information', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Expanded(
            child: ListView(
              children: [
                buildInfoItem('Kernel Release', snapshot.sysInfo.kernelVersion),
                const SizedBox(height: 12),
                buildInfoItem('CPU Model', snapshot.sysInfo.cpuModel),
                const SizedBox(height: 12),
                buildInfoItem('Logical Processors', snapshot.sysInfo.coreCount.toString()),
                const SizedBox(height: 12),
                buildInfoItem('Total System Memory', '${(snapshot.memory.totalMb / 1024).toStringAsFixed(2)} GB (${snapshot.memory.totalKb} KB)'),
                const SizedBox(height: 12),
                buildInfoItem('Total Swap Configured', '${snapshot.memory.swapTotalMb.toStringAsFixed(0)} MB'),
                const SizedBox(height: 12),
                buildInfoItem('Dart SDK Version', 'Dart 3.5 (Latest, Web/Native JIT Compiler)'),
                const SizedBox(height: 12),
                buildInfoItem('Flutter Rendering Engine', 'Impeller/Skia Linux GTK Backend'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
