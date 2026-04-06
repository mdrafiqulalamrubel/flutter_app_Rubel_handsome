import 'package:flutter/material.dart';
import '../models/news_model.dart';
import '../services/api_service.dart';
import '../widgets/news_card.dart';

const List<String> kTrendingTopics = [
  'AI Technology', 'Climate Change', 'World Economy', 'Space Exploration',
  'Sports', 'Politics', 'Health', 'Science', 'Entertainment', 'Bangladesh',
  'Cryptocurrency', 'Stock Market', 'Education', 'Innovation', 'War & Peace',
];

class SearchScreen extends StatefulWidget {
  final ApiService apiService;
  const SearchScreen({super.key, required this.apiService});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchCtrl = TextEditingController();
  List<NewsArticle> _results = [];
  bool _loading = false;
  bool _hasSearched = false;

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() { _loading = true; _hasSearched = true; });
    final results = await widget.apiService.searchNews(query.trim());
    setState(() { _results = results; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F5),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFFF6B00), Color(0xFFFF9A3C)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Search News', style: TextStyle(
                    color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold,
                  )),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(
                        color: Colors.black.withOpacity(0.1), blurRadius: 10,
                      )],
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      onSubmitted: _search,
                      decoration: InputDecoration(
                        hintText: 'Search any topic...',
                        hintStyle: TextStyle(color: Colors.grey[400]),
                        prefixIcon: const Icon(Icons.search, color: Color(0xFFFF6B00)),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Colors.grey),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() { _results = []; _hasSearched = false; });
                                },
                              )
                            : IconButton(
                                icon: const Icon(Icons.arrow_forward, color: Color(0xFFFF6B00)),
                                onPressed: () => _search(_searchCtrl.text),
                              ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onChanged: (v) => setState(() {}),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF6B00)))
                  : !_hasSearched
                      ? _buildTrendingTopics()
                      : _results.isEmpty
                          ? Center(child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                                const SizedBox(height: 12),
                                Text('No results found', style: TextStyle(color: Colors.grey[600])),
                              ],
                            ))
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _results.length,
                              itemBuilder: (ctx, i) => NewsCard(article: _results[i]),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendingTopics() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🔥 Trending Topics', style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E),
          )),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: kTrendingTopics.map((topic) => GestureDetector(
              onTap: () {
                _searchCtrl.text = topic;
                _search(topic);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFFFE0C7)),
                  boxShadow: [BoxShadow(
                    color: Colors.black.withOpacity(0.05), blurRadius: 6,
                  )],
                ),
                child: Text(
                  topic,
                  style: const TextStyle(
                    color: Color(0xFF555555), fontWeight: FontWeight.w500, fontSize: 13,
                  ),
                ),
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }
}
