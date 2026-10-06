part of '../../main.dart';

class _AdminPickerField extends StatelessWidget {
  const _AdminPickerField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final _MenuItem value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BouncyButton(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: _mutedText),
          filled: true,
          fillColor: _bgDark.withValues(alpha: 0.55),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: _gold),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _cream,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.keyboard_arrow_down_rounded, color: _gold),
          ],
        ),
      ),
    );
  }
}

Future<_MenuItem?> _showAdminPicker({
  required BuildContext context,
  required String title,
  required String searchHint,
  required List<_MenuItem> items,
  required _MenuItem selected,
}) {
  return showDialog<_MenuItem>(
    context: context,
    barrierDismissible: true,
    builder: (context) => _AdminSearchPickerDialog(
      title: title,
      searchHint: searchHint,
      items: items,
      selected: selected,
    ),
  );
}

class _AdminSearchPickerDialog extends StatefulWidget {
  const _AdminSearchPickerDialog({
    required this.title,
    required this.searchHint,
    required this.items,
    required this.selected,
  });

  final String title;
  final String searchHint;
  final List<_MenuItem> items;
  final _MenuItem selected;

  @override
  State<_AdminSearchPickerDialog> createState() =>
      _AdminSearchPickerDialogState();
}

class _AdminSearchPickerDialogState extends State<_AdminSearchPickerDialog> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_MenuItem> get _filteredItems {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return widget.items;
    return widget.items
        .where(
          (item) =>
              _menuItemName(item).toLowerCase().contains(query) ||
              _menuItemDescription(item).toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final filteredItems = _filteredItems;
    final screenHeight = MediaQuery.sizeOf(context).height;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 560,
        constraints: BoxConstraints(maxHeight: screenHeight * 0.82),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1724),
          borderRadius: BorderRadius.circular(30),
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
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      color: _cream,
                      fontSize: 22,
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
            const SizedBox(height: 14),
            TextField(
              controller: _searchController,
              autofocus: false,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(
                color: _cream,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                hintText: widget.searchHint,
                hintStyle: const TextStyle(color: _mutedText),
                prefixIcon: const Icon(Icons.search_rounded, color: _gold),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded),
                        color: _muted,
                      ),
                filled: true,
                fillColor: _bgDark.withValues(alpha: 0.55),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: _gold),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: filteredItems.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 34),
                        child: Text(
                          tr('Sonuç bulunamadı', 'No results found'),
                          style: const TextStyle(
                            color: _mutedText,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: filteredItems.length,
                      separatorBuilder: (context, index) => Divider(
                        color: Colors.white.withValues(alpha: 0.06),
                        height: 1,
                      ),
                      itemBuilder: (context, index) {
                        final item = filteredItems[index];
                        final isSelected = item == widget.selected;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          leading: _AdminPickerThumb(item: item),
                          title: Text(
                            _menuItemName(item),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _cream,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          subtitle: _menuItemDescription(item).isEmpty
                              ? null
                              : Text(
                                  _menuItemDescription(item),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: _mutedText),
                                ),
                          trailing: isSelected
                              ? const Icon(
                                  Icons.check_circle_rounded,
                                  color: _mint,
                                )
                              : const Icon(
                                  Icons.chevron_right_rounded,
                                  color: _muted,
                                ),
                          onTap: () => Navigator.of(context).pop(item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminPickerThumb extends StatelessWidget {
  const _AdminPickerThumb({required this.item});

  final _MenuItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: _bgDark.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: item.imagePath == null
          ? Icon(item.icon, color: _gold, size: 22)
          : Image.asset(
              item.imagePath!,
              cacheWidth: 92,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Icon(item.icon, color: _gold, size: 22);
              },
            ),
    );
  }
}
