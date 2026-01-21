import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/inventory_item.dart';

class LocalDb {
  static final List<InventoryItem> _items = [];
  static bool _inited = false;

  // ===== Barcode Catalog (barcode -> product snapshot) =====
  // 结构示例：
  // {
  //   "0123456789012": {
  //     "name": "...",
  //     "category": "Fresh",
  //     "originalPrice": 4.99,
  //     "photoPath": "...",
  //     "tag": "...",
  //     "description": "..."
  //   }
  // }
  static final Map<String, Map<String, dynamic>> _barcodeCatalog = {};

  // 文件路径：Documents/ExpiryManagerV0/data/items.json
  static Future<File> _dataFile() async {
    final baseDir = await getApplicationDocumentsDirectory();
    final dataDir = Directory(
      '${baseDir.path}${Platform.pathSeparator}ExpiryManagerV0${Platform.pathSeparator}data',
    );
    if (!await dataDir.exists()) {
      await dataDir.create(recursive: true);
    }
    return File('${dataDir.path}${Platform.pathSeparator}items.json');
  }

  // 条码库：Documents/ExpiryManagerV0/data/barcode_catalog.json
  static Future<File> _barcodeFile() async {
    final baseDir = await getApplicationDocumentsDirectory();
    final dataDir = Directory(
      '${baseDir.path}${Platform.pathSeparator}ExpiryManagerV0${Platform.pathSeparator}data',
    );
    if (!await dataDir.exists()) {
      await dataDir.create(recursive: true);
    }
    return File('${dataDir.path}${Platform.pathSeparator}barcode_catalog.json');
  }

  // 图片目录：Documents/ExpiryManagerV0/data/images/
  static Future<Directory> _imageDir() async {
    final baseDir = await getApplicationDocumentsDirectory();
    final dir = Directory(
      '${baseDir.path}'
      '${Platform.pathSeparator}ExpiryManagerV0'
      '${Platform.pathSeparator}data'
      '${Platform.pathSeparator}images',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 把用户选择的图片复制到 App 的 images 目录，返回新路径
  /// 这样用户移动/删除原文件也不会影响 App 显示。
  static Future<String?> savePhotoToAppDir(String? sourcePath) async {
    if (sourcePath == null || sourcePath.trim().isEmpty) return null;

    try {
      final src = File(sourcePath);
      if (!await src.exists()) return null;

      final dir = await _imageDir();
      final ext = _safeExt(sourcePath);
      final fileName = 'img_${DateTime.now().microsecondsSinceEpoch}$ext';
      final dst = File('${dir.path}${Platform.pathSeparator}$fileName');

      await src.copy(dst.path);
      return dst.path;
    } catch (_) {
      return null;
    }
  }

  /// 判断路径是不是已经在 App 自己的 images 目录里
  /// 是的话就不用再 copy，避免重复生成图片文件
  static Future<bool> isInAppImagesDir(String? path) async {
    if (path == null || path.trim().isEmpty) return false;
    try {
      final dir = await _imageDir();
      return path.startsWith(dir.path);
    } catch (_) {
      return false;
    }
  }

  static String _safeExt(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.png')) return '.png';
    if (p.endsWith('.jpg')) return '.jpg';
    if (p.endsWith('.jpeg')) return '.jpeg';
    if (p.endsWith('.webp')) return '.webp';
    return '.png';
  }

  /// 启动时调用：读取磁盘数据到内存
  static Future<void> init() async {
    if (_inited) return;
    _inited = true;

    await _loadFromDisk();
    await _loadBarcodeCatalogFromDisk();
  }

  static List<InventoryItem> getAllItems() {
    return List<InventoryItem>.unmodifiable(_items);
  }

  static InventoryItem? getById(String id) {
    for (final it in _items) {
      if (it.id == id) return it;
    }
    return null;
  }

  // ===== Barcode Catalog API =====

  /// 查条码库：存在则返回产品快照 Map；不存在返回 null
  static Map<String, dynamic>? getProductByBarcode(String barcode) {
    final b = barcode.trim();
    if (b.isEmpty) return null;
    return _barcodeCatalog[b];
  }

  /// 写入/更新条码库（保存商品时调用）
  static Future<void> upsertProductBarcode({
    required String barcode,
    required Map<String, dynamic> product,
  }) async {
    final b = barcode.trim();
    if (b.isEmpty) return;

    // 只保留我们关心的字段，防止写入乱结构
    final sanitized = <String, dynamic>{
      'name': (product['name'] ?? '').toString(),
      'category': (product['category'] ?? 'Fresh').toString(),
      'originalPrice': _toNum(product['originalPrice']),
      'photoPath': product['photoPath'],
      'tag': product['tag'],
      'description': product['description'],
    };

    _barcodeCatalog[b] = sanitized;
    await _saveBarcodeCatalogToDisk();
  }

  static num? _toNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }

  // ===== CRUD =====
  static Future<void> addItem(InventoryItem item) async {
    _items.add(item);
    await _saveToDisk();
  }

  static Future<bool> deleteById(String id) async {
    // 1) 先找到要删的 item（为了拿到 photoPath）
    InventoryItem? target;
    for (final it in _items) {
      if (it.id == id) {
        target = it;
        break;
      }
    }

    // 2) 删除记录
    final before = _items.length;
    _items.removeWhere((e) => e.id == id);
    final changed = _items.length != before;

    if (!changed) return false;

    // 3) 先保存数据（保证主流程成功）
    await _saveToDisk();

    // 4) 尝试删除图片文件：存在才删，失败不影响主流程
    //    ✅ 修正：如果该图片仍被其它 item 或条码库引用，则不删
    final path = target?.photoPath;
    await _tryDeletePhotoIfUnreferenced(path, excludingItemId: id);

    return true;
  }

  static Future<bool> updateItem(InventoryItem updated) async {
    for (int i = 0; i < _items.length; i++) {
      if (_items[i].id == updated.id) {
        final old = _items[i];
        _items[i] = updated;
        await _saveToDisk();

        // ✅ 可选增强：如果旧图片与新图片不同，且旧图片无人引用，则尝试删除旧图片
        if ((old.photoPath ?? '').trim().isNotEmpty &&
            old.photoPath != updated.photoPath) {
          await _tryDeletePhotoIfUnreferenced(old.photoPath, excludingItemId: updated.id);
        }

        return true;
      }
    }
    return false;
  }

  static Future<void> clearAll() async {
    _items.clear();
    await _saveToDisk();
    // 条码库一般不跟随清空 items，一般更像“产品库”
    // 如果你希望 clearAll 同时清空条码库，可取消下面两行注释：
    // _barcodeCatalog.clear();
    // await _saveBarcodeCatalogToDisk();
  }

  // ===== Disk IO: items.json =====

  static Future<void> _loadFromDisk() async {
    try {
      final f = await _dataFile();
      if (!await f.exists()) return;

      final txt = await f.readAsString();
      if (txt.trim().isEmpty) return;

      final decoded = jsonDecode(txt);
      if (decoded is! List) return;

      _items
        ..clear()
        ..addAll(
          decoded.whereType<Map>().map((m) {
            final map = m.map((k, v) => MapEntry(k.toString(), v));
            return InventoryItem.fromJson(map);
          }),
        );
    } catch (_) {
      // V0：读失败就当没有数据，避免启动崩溃
      _items.clear();
    }
  }

  static Future<void> _saveToDisk() async {
    try {
      final f = await _dataFile();
      final list = _items.map((e) => e.toJson()).toList();
      final txt = const JsonEncoder.withIndent('  ').convert(list);
      await f.writeAsString(txt, flush: true);
    } catch (_) {
      // V0：写失败先忽略（可后续加入日志/提示）
    }
  }

  // ===== Disk IO: barcode_catalog.json =====

  static Future<void> _loadBarcodeCatalogFromDisk() async {
    try {
      final f = await _barcodeFile();
      if (!await f.exists()) return;

      final txt = await f.readAsString();
      if (txt.trim().isEmpty) return;

      final decoded = jsonDecode(txt);
      if (decoded is! Map) return;

      _barcodeCatalog.clear();
      for (final entry in decoded.entries) {
        final k = entry.key.toString().trim();
        if (k.isEmpty) continue;

        final v = entry.value;
        if (v is Map) {
          _barcodeCatalog[k] = v.map((kk, vv) => MapEntry(kk.toString(), vv));
        }
      }
    } catch (_) {
      _barcodeCatalog.clear();
    }
  }

  static Future<void> _saveBarcodeCatalogToDisk() async {
    try {
      final f = await _barcodeFile();
      final txt = const JsonEncoder.withIndent('  ').convert(_barcodeCatalog);
      await f.writeAsString(txt, flush: true);
    } catch (_) {
      // ignore
    }
  }

  // ===== Photo reference check & safe delete =====

  static bool _isPhotoReferenced(String photoPath, {String? excludingItemId}) {
    final p = photoPath.trim();
    if (p.isEmpty) return false;

    // 1) 还在其它 item 上被引用？
    for (final it in _items) {
      if (excludingItemId != null && it.id == excludingItemId) continue;
      final ip = (it.photoPath ?? '').trim();
      if (ip.isNotEmpty && ip == p) return true;
    }

    // 2) 还在条码库里被引用？
    for (final v in _barcodeCatalog.values) {
      final bp = (v['photoPath'] ?? '').toString().trim();
      if (bp.isNotEmpty && bp == p) return true;
    }

    return false;
  }

  static Future<void> _tryDeletePhotoIfUnreferenced(
    String? photoPath, {
    String? excludingItemId,
  }) async {
    try {
      final path = (photoPath ?? '').trim();
      if (path.isEmpty) return;

      // 只删除我们自己 images 目录下的文件（更安全）
      // 如果你想允许删除任意路径图片，删除这一段检查即可
      final imagesDir = await _imageDir();
      final imagesPrefix = imagesDir.path;
      if (!path.startsWith(imagesPrefix)) {
        return;
      }

      if (_isPhotoReferenced(path, excludingItemId: excludingItemId)) {
        return;
      }

      final f = File(path);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {
      // ignore
    }
  }
}
