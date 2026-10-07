part of '../../main.dart';

/// Hero tag of a product photo that opens [item]'s detail. [source] keeps
/// the same product shown in two places on one screen apart.
Object _productHeroTag(String source, _MenuItem item) =>
    ('product', source, item.id ?? item.name);

/// Lets the photo fly into the detail dialog when [tag] is set.
Widget _productHero(Object? tag, Widget child) =>
    tag == null ? child : Hero(tag: tag, child: child);

class _ProductDetailDialog extends StatelessWidget {
  final _MenuItem item;

  /// The tag of the photo that was tapped; the detail photo flies from it.
  final Object? heroTag;
  const _ProductDetailDialog({required this.item, this.heroTag});

  bool _hasDualPrice(String price) => price.contains('/');

  String _mPrice(String price) {
    final parts = price.split('/');
    return parts.isNotEmpty ? parts[0].trim() : price;
  }

  String _lPrice(String price) {
    final parts = price.split('/');
    return parts.length > 1 ? parts[1].trim() : price;
  }

  Widget _priceBadge(String label, String price) {
    return Container(
      padding: const EdgeInsets.only(right: 6),
      decoration: BoxDecoration(
        color: _gold.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _gold.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: 0.2),
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(9),
                right: Radius.circular(4),
              ),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: _fsBadge,
                fontWeight: FontWeight.w900,
                color: _gold,
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 44,
            child: Text(
              price,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: _cream,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSinglePrice(String price) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      decoration: BoxDecoration(
        color: _gold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gold.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.payments_rounded, color: _gold, size: 22),
          const SizedBox(width: 10),
          Text(
            price,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: _cream,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasTags = item.tags.isNotEmpty;
    final isPopular = item.tags.contains('Popüler');
    final isSpecial = item.tags.contains('Special');
    final dual = _hasDualPrice(item.price);

    String? displayImagePath = item.imagePath;
    if (displayImagePath != null &&
        displayImagePath.contains('assets/menu/png/')) {
      displayImagePath = displayImagePath.replaceFirst(
        'assets/menu/png/',
        'assets/menu/',
      );
      if (displayImagePath.endsWith('cay.png')) {
        displayImagePath = displayImagePath.replaceAll('.png', '.jpeg');
      } else {
        displayImagePath = displayImagePath.replaceAll('.png', '.jpg');
      }
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 460,
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 42),
        decoration: BoxDecoration(
          color: const Color(0xFF1F1A28),
          borderRadius: BorderRadius.circular(36),
          border: Border.all(color: _gold.withValues(alpha: 0.3), width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 30,
              offset: const Offset(0, 15),
            ),
            if (isSpecial)
              BoxShadow(
                color: _gold.withValues(alpha: 0.15),
                blurRadius: 40,
                spreadRadius: 5,
              ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _productHero(
                    heroTag,
                    Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        color: const Color(0xFF14101A),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child:
                          displayImagePath == null &&
                              item.remoteImageUrl == null
                          ? Center(
                              child: Icon(
                                item.icon,
                                size: 90,
                                color: _gold.withValues(alpha: 0.7),
                              ),
                            )
                          : _buildMenuImage(
                              fallbackIcon: item.icon,
                              assetPath: displayImagePath,
                              remoteImageUrl: item.remoteImageUrl,
                              cacheWidth: 400,
                              fit: BoxFit.cover,
                            ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    _menuItemName(item),
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: _gold,
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  if (_menuItemDescription(item).isNotEmpty) ...[
                    Text(
                      _menuItemDescription(item),
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withValues(alpha: 0.75),
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (hasTags) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      alignment: WrapAlignment.center,
                      children: item.tags.map((tag) {
                        final color =
                            _tagStyles[tag] ?? const Color(0xFFB2BEC3);
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: color.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            _menuItemTag(item, tag),
                            style: TextStyle(
                              fontSize: _fsBadge,
                              fontWeight: FontWeight.w800,
                              color: color,
                              letterSpacing: 0.5,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 28),
                  ],
                  dual
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _priceBadge('M', _mPrice(item.price)),
                            const SizedBox(width: 16),
                            _priceBadge('L', _lPrice(item.price)),
                          ],
                        )
                      : _buildSinglePrice(item.price),
                ],
              ),
            ),
            if (isPopular || isSpecial)
              Positioned(
                top: -22,
                left: -18,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: (isSpecial ? const Color(0xFFE879A8) : _gold)
                        .withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: (isSpecial ? const Color(0xFFE879A8) : _gold)
                          .withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.star_rounded,
                        size: 18,
                        color: (isSpecial ? const Color(0xFFE879A8) : _gold),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isSpecial ? 'Special' : trMenu('Popüler'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: (isSpecial ? const Color(0xFFE879A8) : _gold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // 16 px in from the card's corner (the card padding is 36/42).
            const Positioned(top: -26, right: -20, child: _KioskCloseButton()),
          ],
        ),
      ),
    );
  }
}
