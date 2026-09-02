import 'dart:convert';
import 'dart:io';

import 'package:flutter_hbb/models/platform_model.dart';
import 'package:http/http.dart' as http;

/// 台账服务器内置默认地址（服务端部署在 10.196.23.235:8848，单位静态 IP 不会变）
const String kDefaultInventoryServer = 'http://10.196.23.235:8848';

const String kOptInventoryDept = 'inventory-dept';
const String kOptInventoryLocation = 'inventory-location';
const String kOptInventoryUser = 'inventory-user';

/// 本机信息登记 + 上报服务
///
/// 职责：
/// 1. 读取/保存本机登记信息（科室、位置、使用人），存于客户端本地配置
/// 2. 每次启动向台账服务端上报（ID + IP + 计算机名 + 登记信息）
/// 3. 从服务端拉取科室名录，供登记弹窗下拉选择
///
/// 服务端地址解析优先级（高 -> 低）：
///   1. %APPDATA%\RustDesk\inventory-server.txt
///   2. exe 同目录 inventory-server.txt
///   3. 内置默认 kDefaultInventoryServer
class InventoryService {
  InventoryService._();
  static final InventoryService instance = InventoryService._();

  String? _serverCache;

  /// 解析台账服务器基地址
  Future<String> getServerBase() async {
    if (_serverCache != null) return _serverCache!;
    var fromFile = _readServerFile(_appDataServerFile());
    fromFile ??= _readServerFile(_exeDirServerFile());
    final base = (fromFile == null || fromFile.isEmpty)
        ? kDefaultInventoryServer
        : fromFile;
    _serverCache = base.trim().replaceAll(RegExp(r'/+$'), '');
    return _serverCache!;
  }

  /// 强制刷新地址缓存（设置变更后调用）
  void invalidateServerCache() => _serverCache = null;

  File? _appDataServerFile() {
    try {
      final appData = Platform.environment['APPDATA'];
      if (appData == null || appData.isEmpty) return null;
      return File('$appData\\RustDesk\\inventory-server.txt');
    } catch (_) {
      return null;
    }
  }

  File? _exeDirServerFile() {
    try {
      return File(
          '${File(Platform.resolvedExecutable).parent.path}\\inventory-server.txt');
    } catch (_) {
      return null;
    }
  }

  String? _readServerFile(File? f) {
    if (f == null) return null;
    try {
      if (!f.existsSync()) return null;
      final s = f.readAsStringSync().trim();
      if (s.isEmpty) return null;
      if (!s.startsWith('http://') && !s.startsWith('https://')) {
        return 'http://$s';
      }
      return s;
    } catch (_) {
      return null;
    }
  }

  // ---------- 本机登记信息（本地配置读写，同步） ----------

  String get dept => bind.mainGetLocalOption(key: kOptInventoryDept);
  String get location => bind.mainGetLocalOption(key: kOptInventoryLocation);
  String get user => bind.mainGetLocalOption(key: kOptInventoryUser);

  /// 是否已登记（科室 + 位置都填了才算）
  bool get isRegistered => dept.trim().isNotEmpty && location.trim().isNotEmpty;

  Future<void> saveInfo({
    required String dept,
    required String location,
    required String user,
  }) async {
    await bind.mainSetLocalOption(key: kOptInventoryDept, value: dept.trim());
    await bind.mainSetLocalOption(key: kOptInventoryLocation, value: location.trim());
    await bind.mainSetLocalOption(key: kOptInventoryUser, value: user.trim());
  }

  // ---------- 网络 ----------

  /// 取本机 IPv4（优先 192.168 / 10 / 172 私网段）
  static Future<String> localIp() async {
    try {
      final ifaces = await NetworkInterface.list(
          includeLoopback: false, type: InternetAddressType.IPv4);
      String? picked;
      var bestRank = 999;
      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('169.254.') || ip == '0.0.0.0') continue;
          int rank;
          if (ip.startsWith('192.168.')) {
            rank = 1;
          } else if (ip.startsWith('10.')) {
            rank = 2;
          } else if (RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip)) {
            rank = 3;
          } else {
            rank = 4;
          }
          if (rank < bestRank) {
            bestRank = rank;
            picked = ip;
          }
        }
      }
      if (picked != null) return picked;
    } catch (_) {}
    return '';
  }

  /// 拉取科室名录，失败返回空列表
  Future<List<String>> fetchDepts() async {
    try {
      final base = await getServerBase();
      final client = http.Client();
      http.Response res;
      try {
        res = await client
            .get(Uri.parse('$base/api/depts'))
            .timeout(const Duration(seconds: 8));
      } finally {
        client.close();
      }
      if (res.statusCode != 200) return [];
      final decoded = jsonDecode(res.body);
      if (decoded is Map && decoded['items'] is List) {
        return (decoded['items'] as List)
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    return [];
  }

  /// 上报本机信息。静默失败，不影响客户端使用。
  Future<bool> report() async {
    try {
      final id = await bind.mainGetMyId();
      if (id.isEmpty) return false;
      final base = await getServerBase();
      final ip = await localIp();
      String hostname = '';
      try {
        hostname = Platform.localHostname;
      } catch (_) {}

      final body = jsonEncode({
        'rustdesk_id': id,
        'dept': dept,
        'location': location,
        'user_name': user,
        'ip_addr': ip,
        'hostname': hostname,
      });

      final client = http.Client();
      http.Response res;
      try {
        res = await client
            .post(
              Uri.parse('$base/api/report'),
              headers: {'Content-Type': 'application/json'},
              body: body,
            )
            .timeout(const Duration(seconds: 8));
      } finally {
        client.close();
      }
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
