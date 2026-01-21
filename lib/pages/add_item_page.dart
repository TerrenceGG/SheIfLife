import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../db/local_db.dart';
import '../models/inventory_item.dart';

class AddItemPage extends StatefulWidget {
  /// 如果传入 initialItem，则本页变成“编辑页”
  final InventoryItem? initialItem;

  const AddItemPage({super.key, this.initialItem});

  @override
  State<AddItemPage> createState() => _AddItemPageState();
}

class _AddItemPageState extends State<AddItemPage> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();

  String _category = 'Fresh';
  DateTime _expiryDate = DateTime.now().add(const Duration(days: 30));

  final _tagCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  String? _photoPath;
  String? _barcode;

  bool get _isEdit => widget.initialItem != null;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();

    final it = widget.initialItem;
    if (it != null) {
      _nameCtrl.text = it.name;
      _priceCtrl.text = it.originalPrice.toString();
      _category = it.category;
      _expiryDate = it.expiryDate;
      _tagCtrl.text = it.tag ?? '';
      _descCtrl.text = it.description ?? '';
      _photoPath = it.photoPath;
      _barcode = it.barcode;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _tagCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  // -----------------------
  // UI helpers 
  // -----------------------
  Widget _sectionCard({
    required BuildContext context,
    required String title,
    Widget? trailing,
    required Widget child,
  }) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const Spacer(),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _kvRow(
    BuildContext context, {
    required String label,
    required Widget value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 98,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).hintColor,
                ),
          ),
        ),
        Expanded(child: value),
      ],
    );
  }

  String _fmtDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  // -----------------------
  // 日期、选图、拍照、扫码、保存
  // -----------------------
  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate,
      firstDate: DateTime(now.year - 1, 1, 1),
      lastDate: DateTime(now.year + 5, 12, 31),
    );
    if (picked != null) {
      setState(() => _expiryDate = picked);
    }
  }

  /// 相册选图（实现：FilePicker）
  Future<void> _pickPhotoFromGallery() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: false,
      );

      final path = res?.files.single.path;
      if (path == null || path.trim().isEmpty) return;

      setState(() => _photoPath = path);
    } catch (_) {
      // V0：忽略错误（可后续加提示）
    }
  }

  /// 拍照
  Future<void> _pickPhotoFromCamera() async {
    // 只在移动端支持
    if (!(Platform.isAndroid || Platform.isIOS)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera capture is available on mobile only.')),
        );
      }
      return;
    }

    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );
      if (photo == null) return;
      setState(() => _photoPath = photo.path);
    } catch (_) {
      // ignore
    }
  }

  Future<void> _scanBarcode() async {
    // 只在移动端支持（桌面端一般没有摄像头权限/实现链路）
    if (!(Platform.isAndroid || Platform.isIOS)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Barcode scanning is available on mobile only.')),
        );
      }
      return;
    }

    final String? code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScanPage()),
    );

    if (code == null || code.trim().isEmpty) return;

    final barcode = code.trim();
    setState(() => _barcode = barcode);

    // 查条码库
    final product = LocalDb.getProductByBarcode(barcode);
    if (product != null) {
      // 命中：自动载入信息（图片/名称/分类/价格/tag/desc）
      setState(() {
        _nameCtrl.text = (product['name'] ?? '').toString();
        _category = (product['category'] ?? 'Fresh').toString();

        final p = product['originalPrice'];
        if (p is num) {
          _priceCtrl.text = p.toString();
        } else {
          _priceCtrl.text = (p ?? '').toString();
        }

        final tag = (product['tag'] ?? '').toString();
        _tagCtrl.text = tag;

        final desc = (product['description'] ?? '').toString();
        _descCtrl.text = desc;

        final photo = (product['photoPath'] ?? '').toString();
        _photoPath = photo.isEmpty ? _photoPath : photo;
      });

      // 自动弹出选择到期时间
      if (mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (mounted) await _pickExpiryDate();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Loaded product info from barcode catalog.')),
        );
      }
    } else {
      // 不存在：提示用户补全信息，保存时会写入条码库
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('New barcode. Please fill product info, then Save.')),
        );
      }
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final name = _nameCtrl.text.trim();
    final price = double.parse(_priceCtrl.text.trim());

    // ① 只有在有图片时，才尝试复制
    String? savedPhotoPath;
    if (_photoPath != null) {
      final alreadyInApp = await LocalDb.isInAppImagesDir(_photoPath);
      savedPhotoPath = alreadyInApp ? _photoPath : await LocalDb.savePhotoToAppDir(_photoPath);
    }

    // ② 决定最终要存的图片路径
    String? finalPhotoPath;
    if (_photoPath == null) {
      // 用户点了 Remove
      finalPhotoPath = null;
    } else {
      // 有图片：优先用复制后的路径，复制失败就用原路径
      finalPhotoPath = savedPhotoPath ?? _photoPath;
    }

    final now = DateTime.now();

    final InventoryItem item;
    if (_isEdit) {
      final old = widget.initialItem!;
      item = InventoryItem(
        id: old.id,
        name: name,
        category: _category,
        originalPrice: price,
        expiryDate: _expiryDate,
        createdAt: old.createdAt,
        tag: _tagCtrl.text.trim().isEmpty ? null : _tagCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        photoPath: finalPhotoPath,
        barcode: (_barcode == null || _barcode!.trim().isEmpty) ? null : _barcode!.trim(),
      );
      await LocalDb.updateItem(item);
    } else {
      item = InventoryItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        category: _category,
        originalPrice: price,
        expiryDate: _expiryDate,
        createdAt: now,
        tag: _tagCtrl.text.trim().isEmpty ? null : _tagCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        photoPath: savedPhotoPath,
        barcode: (_barcode == null || _barcode!.trim().isEmpty) ? null : _barcode!.trim(),
      );
      await LocalDb.addItem(item);
    }

    // 如果有 barcode，把“产品快照”写入条码库（用于下次扫码自动填充）
    final b = item.barcode?.trim();
    if (b != null && b.isNotEmpty) {
      await LocalDb.upsertProductBarcode(
        barcode: b,
        product: {
          'name': item.name,
          'category': item.category,
          'originalPrice': item.originalPrice,
          'photoPath': item.photoPath,
          'tag': item.tag,
          'description': item.description,
        },
      );
    }

    if (mounted) Navigator.of(context).pop(true); // 返回并通知刷新
  }

  @override
  Widget build(BuildContext context) {
    final canShowPreview = _photoPath != null && File(_photoPath!).existsSync();

    final String barcodeText = (_barcode == null || _barcode!.trim().isEmpty)
        ? 'Not set'
        : _barcode!.trim();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Item' : 'Add Item'),
        actions: [
          IconButton(
            tooltip: 'Scan barcode',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _scanBarcode,
          ),
        ],
      ),

      // 底部固定 Save 区
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            boxShadow: [
              BoxShadow(
                blurRadius: 10,
                offset: const Offset(0, -2),
                color: Colors.black.withValues(alpha: 0.06),
              ),
            ],
          ),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: Text(_isEdit ? 'Save Changes' : 'Save'),
            ),
          ),
        ),
      ),

      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 96),
          children: [
            // ===== Barcode =====
            _sectionCard(
              context: context,
              title: 'Barcode',
              trailing: TextButton.icon(
                onPressed: _scanBarcode,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan'),
              ),
              child: _kvRow(
                context,
                label: 'Code',
                value: InputDecorator(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  child: Text(barcodeText),
                ),
              ),
            ),

            // ===== Photo =====
            _sectionCard(
              context: context,
              title: 'Photo',
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 预览图：更圆润
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: canShowPreview
                        ? Image.file(
                            File(_photoPath!),
                            fit: BoxFit.cover,
                          )
                        : Icon(
                            Icons.image_outlined,
                            size: 36,
                            color: Theme.of(context).hintColor,
                          ),
                  ),
                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: _pickPhotoFromGallery,
                              icon: const Icon(Icons.photo_library_outlined),
                              label: const Text('Gallery'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: _pickPhotoFromCamera,
                              icon: const Icon(Icons.camera_alt_outlined),
                              label: const Text('Camera'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _photoPath == null
                                  ? null
                                  : () => setState(() => _photoPath = null),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Remove'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _photoPath ?? 'No photo selected',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).hintColor,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ===== Item Info =====
            _sectionCard(
              context: context,
              title: 'Item Info',
              child: Column(
                children: [
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Item Name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Please enter a name';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  DropdownButtonFormField<String>(
                    initialValue: _category,
                    items: const [
                      DropdownMenuItem(value: 'Fresh', child: Text('Fresh')),
                      DropdownMenuItem(value: 'Packaged', child: Text('Packaged')),
                      DropdownMenuItem(value: 'NonFood', child: Text('NonFood')),
                    ],
                    onChanged: (v) => setState(() => _category = v ?? 'Fresh'),
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _priceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Original Price (e.g. 4.99)',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Please enter a price';
                      final x = double.tryParse(v.trim());
                      if (x == null || x <= 0) return 'Invalid price';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // Expiry Date：做成“可点的行”，右侧 Pick
                  Row(
                    children: [
                      Expanded(
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Expiry Date',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          child: Text(_fmtDate(_expiryDate)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.tonalIcon(
                        onPressed: _pickExpiryDate,
                        icon: const Icon(Icons.date_range),
                        label: const Text('Pick'),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ===== Optional =====
            _sectionCard(
              context: context,
              title: 'Optional',
              child: Column(
                children: [
                  TextFormField(
                    controller: _tagCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tag (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),

            // 让底部不显得很挤
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// 扫码页面（mobile_scanner）
/// 返回扫描到的条码字符串（Ean/UPC/Code128 等）
class BarcodeScanPage extends StatefulWidget {
  const BarcodeScanPage({super.key});

  @override
  State<BarcodeScanPage> createState() => _BarcodeScanPageState();
}

class _BarcodeScanPageState extends State<BarcodeScanPage> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Barcode'),
      ),
      body: MobileScanner(
        onDetect: (capture) {
          if (_handled) return;
          final codes = capture.barcodes;
          if (codes.isEmpty) return;

          final raw = codes.first.rawValue;
          if (raw == null || raw.trim().isEmpty) return;

          _handled = true;
          Navigator.of(context).pop(raw.trim());
        },
      ),
    );
  }
}
