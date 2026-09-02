import 'package:flutter/material.dart';
import 'package:flutter_hbb/utils/inventory_service.dart';

/// 本机信息登记弹窗
///
/// - 科室名称：必填（下拉名录由服务端下发，也允许手输）
/// - 电脑位置：必填
/// - 使用人：选填
///
/// 返回 true 表示已保存并触发上报；null/false 表示跳过。
Future<bool?> showInventoryRegisterDialog(
  BuildContext context, {
  bool allowSkip = true,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: allowSkip,
    builder: (_) => _InventoryRegisterDialog(allowSkip: allowSkip),
  );
}

class _InventoryRegisterDialog extends StatefulWidget {
  final bool allowSkip;
  const _InventoryRegisterDialog({required this.allowSkip});

  @override
  State<_InventoryRegisterDialog> createState() =>
      _InventoryRegisterDialogState();
}

class _InventoryRegisterDialogState extends State<_InventoryRegisterDialog> {
  final _deptController = TextEditingController();
  final _locationController = TextEditingController();
  final _userController = TextEditingController();

  List<String> _depts = [];
  bool _loadingDepts = true;
  String? _errorText;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final inv = InventoryService.instance;
    _deptController.text = inv.dept;
    _locationController.text = inv.location;
    _userController.text = inv.user;
    _loadDepts();
  }

  Future<void> _loadDepts() async {
    final depts = await InventoryService.instance.fetchDepts();
    if (!mounted) return;
    setState(() {
      _depts = depts;
      _loadingDepts = false;
    });
  }

  @override
  void dispose() {
    _deptController.dispose();
    _locationController.dispose();
    _userController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final dept = _deptController.text.trim();
    final location = _locationController.text.trim();
    if (dept.isEmpty) {
      setState(() => _errorText = '科室名称必填');
      return;
    }
    if (location.isEmpty) {
      setState(() => _errorText = '电脑位置必填');
      return;
    }
    setState(() {
      _errorText = null;
      _saving = true;
    });

    await InventoryService.instance.saveInfo(
      dept: dept,
      location: location,
      user: _userController.text,
    );
    // 立即上报一次，管理员端可即时看到登记结果
    await InventoryService.instance.report();
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('本机信息登记'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '请填写本机所属科室与物理位置，便于管理员快速定位并远程协助。',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _deptController,
                decoration: const InputDecoration(
                  labelText: '科室名称 *',
                  hintText: '如：放射科',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) {
                  if (_errorText != null) setState(() => _errorText = null);
                },
              ),
              const SizedBox(height: 10),
              if (_loadingDepts)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (_depts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _depts
                        .map(
                          (d) => ActionChip(
                            label: Text(d),
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              _deptController.text = d;
                              setState(() => _errorText = null);
                            },
                          ),
                        )
                        .toList(),
                  ),
                ),
              TextField(
                controller: _locationController,
                decoration: const InputDecoration(
                  labelText: '电脑位置 *',
                  hintText: '如：门诊楼3层 CT操作间',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) {
                  if (_errorText != null) setState(() => _errorText = null);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _userController,
                decoration: const InputDecoration(
                  labelText: '使用人（选填）',
                  hintText: '如：张三',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              if (_errorText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _errorText!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.allowSkip)
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            child: const Text('稍后提醒'),
          ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }
}
