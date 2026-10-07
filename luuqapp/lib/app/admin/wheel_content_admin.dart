part of '../../main.dart';

class _WheelContentAdminDialog extends StatefulWidget {
  const _WheelContentAdminDialog({
    required this.initialItems,
    required this.iceCoffeeOptions,
    required this.hotCoffeeOptions,
    required this.dessertOptions,
    required this.cocktailOptions,
    required this.herbalTeaOptions,
    required this.iceCreamOptions,
    required this.blockedItems,
    required this.onSave,
  });

  final List<_MenuItem> initialItems;
  final List<_MenuItem> iceCoffeeOptions;
  final List<_MenuItem> hotCoffeeOptions;
  final List<_MenuItem> dessertOptions;
  final List<_MenuItem> cocktailOptions;
  final List<_MenuItem> herbalTeaOptions;
  final List<_MenuItem> iceCreamOptions;
  final List<_MenuItem> blockedItems;
  final ValueChanged<List<_MenuItem>> onSave;

  @override
  State<_WheelContentAdminDialog> createState() =>
      _WheelContentAdminDialogState();
}

class _WheelContentAdminDialogState extends State<_WheelContentAdminDialog> {
  late final List<_MenuItem> _items = List<_MenuItem>.from(widget.initialItems);

  List<_WheelSlot> get _slots {
    final isSummer = appThemeNotifier.value == AppTheme.summer;
    return [
      _WheelSlot(
        tr('Ice kahve 1', 'Ice coffee 1'),
        widget.iceCoffeeOptions,
        tr('Ice kahve ara', 'Search ice coffee'),
      ),
      _WheelSlot(
        isSummer
            ? tr('Ice kahve 2', 'Ice coffee 2')
            : tr('Sıcak kahve', 'Hot coffee'),
        isSummer ? widget.iceCoffeeOptions : widget.hotCoffeeOptions,
        isSummer
            ? tr('Ice kahve ara', 'Search ice coffee')
            : tr('Sıcak kahve ara', 'Search hot coffee'),
      ),
      _WheelSlot(
        tr('Tatlı 1', 'Dessert 1'),
        widget.dessertOptions,
        tr('Tatlı ara', 'Search dessert'),
      ),
      _WheelSlot(
        tr('Tatlı 2', 'Dessert 2'),
        widget.dessertOptions,
        tr('Tatlı ara', 'Search dessert'),
      ),
      _WheelSlot(
        tr('Kokteyl 1', 'Cocktail 1'),
        widget.cocktailOptions,
        tr('Kokteyl ara', 'Search cocktail'),
      ),
      _WheelSlot(
        tr('Kokteyl 2', 'Cocktail 2'),
        widget.cocktailOptions,
        tr('Kokteyl ara', 'Search cocktail'),
      ),
      _WheelSlot(
        isSummer
            ? tr('Dondurma 1', 'Ice cream 1')
            : tr('Bitki çayı 1', 'Herbal tea 1'),
        isSummer ? widget.iceCreamOptions : widget.herbalTeaOptions,
        isSummer
            ? tr('Dondurma ara', 'Search ice cream')
            : tr('Bitki çayı ara', 'Search herbal tea'),
      ),
      _WheelSlot(
        isSummer
            ? tr('Dondurma 2', 'Ice cream 2')
            : tr('Bitki çayı 2', 'Herbal tea 2'),
        isSummer ? widget.iceCreamOptions : widget.herbalTeaOptions,
        isSummer
            ? tr('Dondurma ara', 'Search ice cream')
            : tr('Bitki çayı ara', 'Search herbal tea'),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 620,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        padding: const EdgeInsets.all(26),
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.casino_rounded, color: _gold),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tr('Çark içeriği', 'Wheel items'),
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
                'Ana çark 8 üründen oluşur. Her slotu menüden seçebilirsin.',
                'The main wheel consists of 8 products. You can select each slot from the menu.',
              ),
              style: const TextStyle(
                color: _mutedText,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: ListView.separated(
                itemCount: _slots.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final slot = _slots[index];
                  return _WheelSlotPicker(
                    label: slot.label,
                    item: _items[index],
                    onTap: () async {
                      final selected = await _showAdminPicker(
                        context: context,
                        title: slot.label,
                        searchHint: slot.searchHint,
                        items: slot.options,
                        selected: _items[index],
                      );
                      if (selected != null) {
                        setState(() => _items[index] = selected);
                      }
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 18),
            BouncyButton(
              onTap: () async {
                final duplicate = _firstDuplicateItem(_items);
                if (duplicate != null) {
                  await _showAdminError(
                    context,
                    '${tr('Bu ürün çarkta iki kez seçilemez', 'This product cannot be selected twice on the wheel')}: ${_menuItemName(duplicate)}',
                  );
                  return;
                }
                final conflict = _firstContained(_items, widget.blockedItems);
                if (conflict != null) {
                  await _showAdminError(
                    context,
                    '${tr('Bu ürün Barista önerisinde seçili', 'This product is selected in Barista recommendation')}: ${_menuItemName(conflict)}',
                  );
                  return;
                }
                widget.onSave(List<_MenuItem>.from(_items));
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

class _WheelSlot {
  const _WheelSlot(this.label, this.options, this.searchHint);
  final String label;
  final List<_MenuItem> options;
  final String searchHint;
}

class _WheelSlotPicker extends StatelessWidget {
  const _WheelSlotPicker({
    required this.label,
    required this.item,
    required this.onTap,
  });

  final String label;
  final _MenuItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BouncyButton(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _bgDark.withValues(alpha: 0.50),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            _AdminPickerThumb(item: item),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: _gold,
                      fontSize: _fsBadge,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _menuItemName(item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _cream,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.edit_rounded, color: _muted, size: 20),
          ],
        ),
      ),
    );
  }
}

_MenuItem? _firstDuplicateItem(List<_MenuItem> items) {
  final seen = <_MenuItem>{};
  for (final item in items) {
    if (!seen.add(item)) return item;
  }
  return null;
}

_MenuItem? _firstContained(
  Iterable<_MenuItem> items,
  Iterable<_MenuItem> blockedItems,
) {
  for (final item in items) {
    if (blockedItems.contains(item)) return item;
  }
  return null;
}

Future<void> _showAdminError(
  BuildContext context,
  String message, {
  String? title,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      return AlertDialog(
        backgroundColor: const Color(0xFF1C1724),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: _gold),
            const SizedBox(width: 10),
            Text(
              title ?? tr('Seçim çakışıyor', 'Selection Conflict'),
              style: const TextStyle(
                color: _cream,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(
            color: _mutedText,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              tr('TAMAM', 'OK'),
              style: const TextStyle(color: _gold, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      );
    },
  );
}
