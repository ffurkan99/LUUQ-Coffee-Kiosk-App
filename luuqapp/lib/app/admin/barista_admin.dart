part of '../../main.dart';

class _BaristaAdminDialog extends StatefulWidget {
  const _BaristaAdminDialog({
    required this.drinkOptions,
    required this.dessertOptions,
    required this.selectedDrink,
    required this.selectedDessert,
    required this.blockedItems,
    required this.onSave,
  });

  final List<_MenuItem> drinkOptions;
  final List<_MenuItem> dessertOptions;
  final _MenuItem selectedDrink;
  final _MenuItem selectedDessert;
  final List<_MenuItem> blockedItems;
  final void Function(_MenuItem drink, _MenuItem dessert) onSave;

  @override
  State<_BaristaAdminDialog> createState() => _BaristaAdminDialogState();
}

class _BaristaAdminDialogState extends State<_BaristaAdminDialog> {
  late _MenuItem _drink = widget.selectedDrink;
  late _MenuItem _dessert = widget.selectedDessert;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1724),
          borderRadius: BorderRadius.circular(34),
          border: Border.all(color: _gold.withValues(alpha: 0.24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.65),
              blurRadius: 56,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.admin_panel_settings_rounded, color: _gold),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tr('Admin Menüsü', 'Admin Menu'),
                    style: const TextStyle(
                      color: _cream,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  color: _muted,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              tr(
                'Baristanın tavsiye edeceği içecek ve tatlıyı seç.',
                'Choose the drink and dessert for barista recommendation.',
              ),
              style: TextStyle(
                color: _mutedText,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
            _AdminPickerField(
              label: tr('Tavsiye içecek', 'Recommended drink'),
              value: _drink,
              onTap: () async {
                final selected = await _showAdminPicker(
                  context: context,
                  title: tr('Tavsiye içecek', 'Recommended drink'),
                  searchHint: tr('İçecek ara', 'Search drink'),
                  items: widget.drinkOptions,
                  selected: _drink,
                );
                if (selected != null) {
                  setState(() => _drink = selected);
                }
              },
            ),
            const SizedBox(height: 16),
            _AdminPickerField(
              label: tr('Tavsiye tatlı', 'Recommended dessert'),
              value: _dessert,
              onTap: () async {
                final selected = await _showAdminPicker(
                  context: context,
                  title: tr('Tavsiye tatlı', 'Recommended dessert'),
                  searchHint: tr('Tatlı ara', 'Search dessert'),
                  items: widget.dessertOptions,
                  selected: _dessert,
                );
                if (selected != null) {
                  setState(() => _dessert = selected);
                }
              },
            ),
            const SizedBox(height: 26),
            BouncyButton(
              onTap: () async {
                final conflict = _firstContained([
                  _drink,
                  _dessert,
                ], widget.blockedItems);
                if (conflict != null) {
                  await _showAdminError(
                    context,
                    '${tr('Bu ürün çark içeriğinde seçili', 'This product is selected in the wheel items')}: ${_menuItemName(conflict)}',
                  );
                  return;
                }
                widget.onSave(_drink, _dessert);
                Navigator.of(context).pop();
              },
              child: Container(
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _gold,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: _gold.withValues(alpha: 0.25),
                      blurRadius: 22,
                    ),
                  ],
                ),
                child: Text(
                  tr('KAYDET', 'SAVE'),
                  style: const TextStyle(
                    color: _bgDark,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
