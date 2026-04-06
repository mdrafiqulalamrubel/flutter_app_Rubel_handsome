import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/news_model.dart';
import 'package:intl/intl.dart';

class NewsDetailScreen extends StatelessWidget {
  final NewsArticle article;
  const NewsDetailScreen({super.key, required this.article});

  String _formatDate(String? date) {
    if (date == null) return '';
    try {
      return DateFormat('MMM d, yyyy · h:mm a').format(DateTime.parse(date).toLocal());
    } catch (_) { return ''; }
  }

  Future<void> _openBrowser() async {
    final uri = Uri.parse(article.url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F5),
      body: SafeArea(
        child: Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFFFF6B00), Color(0xFFFF9A3C)]),
            ),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              Expanded(
                child: Text(
                  article.sourceName ?? 'News',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.open_in_browser, color: Colors.white),
                onPressed: _openBrowser,
              ),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (article.urlToImage != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(
                      article.urlToImage!,
                      height: 220, width: double.infinity, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        height: 180,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFFFF6B00), Color(0xFFFF9A3C)]),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Center(child: Icon(Icons.newspaper, size: 64, color: Colors.white)),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                if (article.sourceName != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B00).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(article.sourceName!,
                        style: const TextStyle(color: Color(0xFFFF6B00), fontWeight: FontWeight.w600, fontSize: 12)),
                  ),
                const SizedBox(height: 12),
                Text(article.title,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E), height: 1.3)),
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.access_time, size: 12, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(_formatDate(article.publishedAt),
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ]),
                const Divider(height: 28),
                Text(article.description,
                    style: const TextStyle(fontSize: 16, color: Color(0xFF444444), height: 1.7)),
                if (article.content != null && article.content!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(article.content!.replaceAll(RegExp(r'\[\+\d+ chars\]'), ''),
                      style: const TextStyle(fontSize: 15, color: Color(0xFF555555), height: 1.7)),
                ],
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _openBrowser,
                    icon: const Icon(Icons.open_in_browser, color: Colors.white),
                    label: const Text('Read Full Article in Browser',
                        style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B00),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

void showNewsBottomSheet(BuildContext context, NewsArticle article) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _NewsBottomSheet(article: article),
  );
}

class _NewsBottomSheet extends StatelessWidget {
  final NewsArticle article;
  const _NewsBottomSheet({required this.article});

  String _formatDate(String? date) {
    if (date == null) return '';
    try { return DateFormat('MMM d, yyyy').format(DateTime.parse(date).toLocal()); }
    catch (_) { return ''; }
  }

  Future<void> _openBrowser() async {
    final uri = Uri.parse(article.url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFFF8F5),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: Container(
          margin: const EdgeInsets.only(top: 12),
          width: 40, height: 4,
          decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
        )),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (article.urlToImage != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(article.urlToImage!,
                    height: 200, width: double.infinity, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 200,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFFFF6B00), Color(0xFFFF9A3C)]),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.newspaper, size: 64, color: Colors.white),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              if (article.sourceName != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B00).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(article.sourceName!,
                      style: const TextStyle(color: Color(0xFFFF6B00), fontWeight: FontWeight.w600, fontSize: 12)),
                ),
              const SizedBox(height: 10),
              Text(article.title,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E), height: 1.3)),
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.access_time, size: 12, color: Colors.grey),
                const SizedBox(width: 4),
                Text(_formatDate(article.publishedAt), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                if (article.author != null) ...[
                  const Text(' · ', style: TextStyle(color: Colors.grey)),
                  const Icon(Icons.person_outline, size: 12, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(child: Text(article.author!,
                      style: const TextStyle(color: Colors.grey, fontSize: 12), overflow: TextOverflow.ellipsis)),
                ],
              ]),
              const Divider(height: 24),
              Text(article.description,
                  style: const TextStyle(fontSize: 15, color: Color(0xFF444444), height: 1.6)),
              if (article.content != null) ...[
                const SizedBox(height: 12),
                Text(article.content!.replaceAll(RegExp(r'\[\+\d+ chars\]'), '...'),
                    style: const TextStyle(fontSize: 14, color: Color(0xFF666666), height: 1.6)),
              ],
              const SizedBox(height: 20),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => NewsDetailScreen(article: article)));
                },
                icon: const Icon(Icons.article, color: Colors.white),
                label: const Text('Read More', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B00),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFFF6B00)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: IconButton(
                icon: const Icon(Icons.open_in_browser, color: Color(0xFFFF6B00)),
                onPressed: _openBrowser,
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
