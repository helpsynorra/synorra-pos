import 'package:flutter/material.dart';
import '../../models/menu_item.dart';

class ProductCard extends StatelessWidget {
  final MenuItem item;
  final bool isSelected;
  final bool isDisabled;
  final VoidCallback onTap;

  const ProductCard({
    super.key,
    required this.item,
    this.isSelected = false,
    this.isDisabled = false,
    required this.onTap,
  });

  String _buildSubtitle() {
    final styleLabels = item.styles
        .map((s) => s.toLowerCase() == 'hot' ? 'Hot' : 'Iced')
        .toList();
    final hasAddons = item.addons.isNotEmpty;

    if (styleLabels.isNotEmpty) {
      final joinedStyles = styleLabels.join(' / ');
      return hasAddons ? '$joinedStyles · Add-ons' : joinedStyles;
    }
    if (hasAddons) {
      return 'Add-ons';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = _buildSubtitle();

    return Material(
      color: isDisabled ? const Color(0xFFF3F4F6) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected ? Colors.black : const Color(0xFFE5E7EB),
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isDisabled ? null : onTap,
        splashColor: const Color(0xFFF3F4F6),
        highlightColor: const Color(0xFFE5E7EB),
        child: Opacity(
          opacity: isDisabled ? 0.45 : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    height: 78,
                    width: double.infinity,
                    child: item.image.isEmpty ? const Icon(Icons.local_cafe_outlined, color: Color(0xFF9CA3AF)) : Image.network(
                      item.image,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.local_cafe_outlined, color: Color(0xFF9CA3AF)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Flexible(
                    child: Text(
                      item.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF111827),
                        height: 1.1,
                      ),
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    '₱${item.price.toInt()}',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.normal,
                      color: Color(0xFF111827),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
