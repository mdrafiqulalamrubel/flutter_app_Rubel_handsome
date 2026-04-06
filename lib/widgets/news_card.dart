import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/news_model.dart';
import '../screens/news_detail_screen.dart';

// NOTE: This file uses Image.network() directly — no cached_network_image
// dependency. This is intentional: cached_network_image pulls in sqflite
// which has no Windows implementation and breaks flutter run -d windows.

class NewsCard extends StatelessWidget {
  final NewsArticle article;
  const NewsCard({super.key, required this.article});

  String _formatDate(String? date) {
    if (date == null) return '';
    try {
      final dt = DateTime.parse(date);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return DateFormat('MMM d').format(dt.toLocal());
    } catch (_) { return ''; }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showNewsBottomSheet(context, article),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12, offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (article.urlToImage != null)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: Image.network(
                  article.urlToImage!,
                  height: 180, width: double.infinity,
                  fit: BoxFit.cover,
                  // Graceful fallback — no crash on broken image URLs
                  errorBuilder: (_, __, ___) => Container(
                    height: 120,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFFF6B00), Color(0xFFFF9A3C)],
                      ),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: const Center(child: Icon(Icons.newspaper, size: 48, color: Colors.white)),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (article.sourceName != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF6B00).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            article.sourceName!,
                            style: const TextStyle(
                              color: Color(0xFFFF6B00), fontSize: 11, fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      const Spacer(),
                      Text(
                        _formatDate(article.publishedAt),
                        style: const TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    article.title,
                    style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A2E), height: 1.3,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (article.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      article.description,
                      style: const TextStyle(
                        fontSize: 13, color: Color(0xFF777777), height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.touch_app_outlined, size: 14, color: Color(0xFFFF9A3C)),
                      const SizedBox(width: 4),
                      const Text(
                        'Tap to read more',
                        style: TextStyle(
                          fontSize: 12, color: Color(0xFFFF9A3C), fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.arrow_forward_ios, size: 12, color: Color(0xFFFF9A3C)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
