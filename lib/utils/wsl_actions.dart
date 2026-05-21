import 'dart:io';

class WslActions {
  static const String _wslConfigPath = '/mnt/c/Users/gbast/.wslconfig';

  // Reclaim WSL Memory Cache
  static Future<bool> reclaimMemory() async {
    try {
      final result = await Process.run('sh', [
        '-c',
        'echo 1960 | sudo -S sysctl -w vm.drop_caches=3'
      ]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  // Kill Process
  static Future<bool> killProcess(int pid, {bool useSudo = false}) async {
    try {
      if (useSudo) {
        final result = await Process.run('sh', [
          '-c',
          'echo 1960 | sudo -S kill -9 $pid'
        ]);
        return result.exitCode == 0;
      } else {
        final result = await Process.run('kill', ['-9', '$pid']);
        return result.exitCode == 0;
      }
    } catch (_) {
      return false;
    }
  }

  // Parse .wslconfig
  static Map<String, Map<String, String>> readWslConfig() {
    final Map<String, Map<String, String>> sections = {};
    try {
      final file = File(_wslConfigPath);
      if (!file.existsSync()) {
        // Return default empty configurations so the user can initialize them
        sections['wsl2'] = {};
        sections['experimental'] = {};
        return sections;
      }
      final lines = file.readAsLinesSync();
      String currentSection = 'wsl2'; // default fallback
      sections[currentSection] = {};

      for (var line in lines) {
        line = line.trim();
        if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) {
          continue;
        }
        if (line.startsWith('[') && line.endsWith(']')) {
          currentSection = line.substring(1, line.length - 1).trim();
          sections[currentSection] ??= {};
        } else if (line.contains('=')) {
          final parts = line.split('=');
          final key = parts[0].trim();
          final val = parts.sublist(1).join('=').trim();
          sections[currentSection]![key] = val;
        }
      }
    } catch (_) {
      // ignore
    }
    // Guarantee basic sections exist
    sections.putIfAbsent('wsl2', () => {});
    sections.putIfAbsent('experimental', () => {});
    return sections;
  }

  // Write .wslconfig
  static Future<bool> writeWslConfig(Map<String, Map<String, String>> config) async {
    try {
      final file = File(_wslConfigPath);
      final buffer = StringBuffer();
      
      // Ensure wsl2 section exists and is written first
      final wsl2 = config['wsl2'] ?? {};
      buffer.writeln('[wsl2]');
      wsl2.forEach((k, v) {
        if (v.isNotEmpty) {
          buffer.writeln('$k=$v');
        }
      });
      buffer.writeln();

      // Write other sections
      config.forEach((section, values) {
        if (section == 'wsl2') return;
        if (values.isEmpty) return;
        buffer.writeln('[$section]');
        values.forEach((k, v) {
          if (v.isNotEmpty) {
            buffer.writeln('$k=$v');
          }
        });
        buffer.writeln();
      });

      await file.writeAsString('${buffer.toString().trim()}\n');
      return true;
    } catch (_) {
      return false;
    }
  }

  // Generate disk compaction script on Windows Host
  static Future<String?> generateDiskCompactionScript() async {
    try {
      final destDir = Directory('/mnt/c/Users/gbast');
      if (!destDir.existsSync()) {
        return null;
      }
      
      final psScriptPath = '/mnt/c/Users/gbast/compact-wsl.ps1';
      final psScriptContent = '''# PowerShell script to compact WSL virtual disk (.vhdx)
# Run this from Windows PowerShell as Administrator!

Write-Host "Starting WSL Disk Compactor..." -ForegroundColor Cyan
Write-Host "This will stop all running WSL instances." -ForegroundColor Yellow

Read-Host "Press ENTER to stop WSL and begin compaction, or Ctrl+C to cancel"

# Shut down WSL
Write-Host "Shutting down WSL instances..." -ForegroundColor Cyan
wsl --shutdown

# Path to the virtual hard disk
\$vhdxPath = "\$env:LOCALAPPDATA\\Packages\\CanonicalGroupLimited.Ubuntu24.04LTS_79rhkp1fndgsc\\LocalState\\ext4.vhdx"

if (-not (Test-Path \$vhdxPath)) {
    \$vhdxPath = "\$env:LOCALAPPDATA\\Packages\\CanonicalGroupLimited.Ubuntu_79rhkp1fndgsc\\LocalState\\ext4.vhdx"
}

if (-not (Test-Path \$vhdxPath)) {
    \$vhdxPath = Read-Host "ubuntu ext4.vhdx file not found at default location. Please enter absolute path to ext4.vhdx"
}

if (Test-Path \$vhdxPath) {
    Write-Host "Found VHDX at \$vhdxPath" -ForegroundColor Green
    
    # Create diskpart command file
    \$tempFile = [System.IO.Path]::GetTempFileName()
    @"
select vdisk file="\$vhdxPath"
attach vdisk readonly
compact vdisk
detach vdisk
"@ | Out-File -FilePath \$tempFile -Encoding ascii

    Write-Host "Running diskpart compaction..." -ForegroundColor Cyan
    diskpart /s \$tempFile
    Remove-Item \$tempFile
    
    Write-Host "WSL Disk Compactor completed!" -ForegroundColor Green
} else {
    Write-Host "ext4.vhdx path is invalid. Compaction aborted." -ForegroundColor Red
}

Read-Host "Press ENTER to exit"
''';
      final file = File(psScriptPath);
      await file.writeAsString(psScriptContent);
      return 'C:\\Users\\gbast\\compact-wsl.ps1';
    } catch (_) {
      return null;
    }
  }
}
