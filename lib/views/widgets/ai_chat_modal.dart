import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/dto/dashboard_dto.dart';
import 'package:flutter_app/services/gemini_ai_service.dart';
import 'package:flutter_app/views/pages/sidebar/configuration_page.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';

/// Interactive AI Assistant Dialog / Bottom Sheet for Selecta operations
class AiChatModal extends StatefulWidget {
  final DashboardDTO? dashboardDTO;
  final String? userRole;

  const AiChatModal({super.key, this.dashboardDTO, this.userRole});

  static void show(BuildContext context, {DashboardDTO? dashboardDTO, String? userRole}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AiChatModal(dashboardDTO: dashboardDTO, userRole: userRole),
    );
  }

  @override
  State<AiChatModal> createState() => _AiChatModalState();
}

class _ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  bool? isLiked;

  _ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}

class _ParsedAiMessage {
  final String mainContent;
  final List<String> suggestedQuestions;

  _ParsedAiMessage({required this.mainContent, required this.suggestedQuestions});

  factory _ParsedAiMessage.parse(String text) {
    const markers = [
      '💡 Suggested questions:',
      '💡 Suggested follow-ups:',
      'Suggested questions:',
      'Suggested follow-ups:',
    ];

    int markerIndex = -1;
    String matchedMarker = '';
    for (final marker in markers) {
      final idx = text.indexOf(marker);
      if (idx != -1 && (markerIndex == -1 || idx < markerIndex)) {
        markerIndex = idx;
        matchedMarker = marker;
      }
    }

    if (markerIndex == -1) {
      return _ParsedAiMessage(
        mainContent: _normalizeAiMarkdown(_convertMarkdownTablesToCards(text)),
        suggestedQuestions: [],
      );
    }

    final rawContent = text.substring(0, markerIndex).trim();
    final mainContent = _normalizeAiMarkdown(_convertMarkdownTablesToCards(rawContent));
    final suggestionsPart = text.substring(markerIndex + matchedMarker.length).trim();
    final lines = suggestionsPart.split('\n');
    final questions = <String>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('-') || trimmed.startsWith('*') || trimmed.startsWith('•') || RegExp(r'^\d+\.').hasMatch(trimmed)) {
        final q = trimmed.replaceFirst(RegExp(r'^[-*•\d.]+\s*'), '').replaceAll('*', '').trim();
        if (q.isNotEmpty) {
          questions.add(q);
        }
      }
    }

    return _ParsedAiMessage(mainContent: mainContent, suggestedQuestions: questions);
  }

  /// Automatically transforms multi-column Markdown tables into vertical mobile card blocks
  /// so users never have to scroll back and forth horizontally.
  static String _convertMarkdownTablesToCards(String text) {
    if (!text.contains('|')) return text;

    final lines = text.split('\n');
    final result = <String>[];
    int i = 0;

    bool isSeparator(String line) {
      final trimmed = line.trim();
      if (!trimmed.contains('|') || !trimmed.contains('-')) return false;
      return RegExp(r'^[\|\s:\-]+$').hasMatch(trimmed) && trimmed.contains('--');
    }

    List<String> parseRow(String line) {
      var trimmed = line.trim();
      if (trimmed.startsWith('|')) trimmed = trimmed.substring(1);
      if (trimmed.endsWith('|')) trimmed = trimmed.substring(0, trimmed.length - 1);
      return trimmed.split('|').map((c) => c.trim()).toList();
    }

    while (i < lines.length) {
      final line = lines[i];
      if (line.contains('|') && i + 1 < lines.length && isSeparator(lines[i + 1])) {
        final headers = parseRow(line);
        i += 2; // skip header and separator row

        final rows = <List<String>>[];
        while (i < lines.length && lines[i].trim().isNotEmpty && lines[i].contains('|')) {
          rows.add(parseRow(lines[i]));
          i++;
        }

        if (headers.length <= 1) {
          for (final row in rows) {
            if (row.isNotEmpty && row[0].isNotEmpty) {
              result.add('- **${row[0]}**');
            }
          }
          result.add('');
        } else if (headers.length == 2) {
          // 2-column key-value summary with clear indents
          for (final row in rows) {
            final key = row.isNotEmpty ? row[0] : '';
            final val = row.length > 1 ? row[1] : '';
            if (key.isNotEmpty) {
              result.add('- **$key**: $val');
            }
          }
          result.add('');
        } else {
          // Multi-column cards with indented sub-bullets and generous spacing
          for (int r = 0; r < rows.length; r++) {
            final row = rows[r];
            if (row.isEmpty) continue;
            final title = row[0];
            final hasEmoji = RegExp(r'[\u{1F300}-\u{1FAFF}]', unicode: true).hasMatch(title);
            final titlePrefix = hasEmoji ? '' : '🔹 ';
            result.add('$titlePrefix**$title**');
            for (int c = 1; c < headers.length && c < row.length; c++) {
              final h = headers[c];
              final v = row[c];
              if (v.isNotEmpty) {
                result.add('  - **$h**: $v');
              }
            }
            result.add(''); // Blank line spacing after each card for readability
          }
        }
      } else {
        result.add(line);
        i++;
      }
    }

    return result.join('\n');
  }

  /// Normalizes incoming AI text to ensure standard Markdown list markers (- and   -)
  /// are used instead of Unicode bullets (•), preserving and standardizing hierarchical indents.
  static String _normalizeAiMarkdown(String text) {
    final lines = text.split('\n');
    final result = <String>[];
    bool inCodeBlock = false;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.startsWith('```')) {
        inCodeBlock = !inCodeBlock;
        result.add(line);
        continue;
      }

      if (inCodeBlock) {
        result.add(line);
        continue;
      }

      if (trimmed.isEmpty) {
        result.add('');
        continue;
      }

      // Check if line starts with a bullet symbol (•, ◦, ▪, ‣, -, *)
      final bulletMatch = RegExp(r'^(\s*)([•◦▪‣\-\*])\s+(.*)$').firstMatch(line);
      if (bulletMatch != null) {
        final leadingSpaces = bulletMatch.group(1)!.length;
        final content = bulletMatch.group(3)!;
        if (leadingSpaces >= 3) {
          result.add('    - $content');
        } else if (leadingSpaces >= 1) {
          result.add('  - $content');
        } else {
          result.add('- $content');
        }
        continue;
      }

      // Numbered list items
      final numMatch = RegExp(r'^(\s*)(\d+[\.\)])\s+(.*)$').firstMatch(line);
      if (numMatch != null) {
        final leadingSpaces = numMatch.group(1)!.length;
        final marker = numMatch.group(2)!;
        final content = numMatch.group(3)!;
        if (leadingSpaces >= 2) {
          result.add('  $marker $content');
        } else {
          result.add('$marker $content');
        }
        continue;
      }

      // If line has 2 or more leading spaces, treat as indented detail item
      final leadingSpaces = line.length - line.trimLeft().length;
      if (leadingSpaces >= 2 && !trimmed.startsWith('#') && !trimmed.startsWith('>') && !trimmed.startsWith('|')) {
        if (leadingSpaces >= 4) {
          result.add('    - $trimmed');
        } else {
          result.add('  - $trimmed');
        }
        continue;
      }

      result.add(trimmed);
    }

    return result.join('\n');
  }
}

class _AiChatModalState extends State<AiChatModal> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GeminiAiService _aiService = GeminiAiService();

  final List<_ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _hasApiKey = false;
  bool _checkingKey = true;

  @override
  void initState() {
    super.initState();
    _checkApiKeyAndInit();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  AiStatusCheck? _statusCheck;
  String? _quotaAlertMessage;

  Future<void> _checkApiKeyAndInit() async {
    final status = await _aiService.checkAiAvailability();
    if (!mounted) return;

    setState(() {
      _statusCheck = status;
      _hasApiKey = status.isAllowed;
      _quotaAlertMessage = status.isAllowed && status.message != null ? status.message : null;
      _checkingKey = false;
    });

    if (status.isAllowed) {
      _initSession();
    }
  }

  String _buildOperationalContext() {
    final buffer = StringBuffer();
    if (widget.userRole != null) {
      buffer.writeln('Logged-in Role: ${widget.userRole}');
    }
    if (widget.dashboardDTO != null) {
      final d = widget.dashboardDTO!;
      buffer.writeln('Total Buying Sales: ${d.totalBuyingSales}');
      buffer.writeln('Total Invoice Amount: ${d.totalInvoiceAmount}');
      buffer.writeln('Pending Deliveries: ${d.pendingDeliveryCount}, Returned Deliveries: ${d.returnedDeliveryCount}');
      buffer.writeln('Buying Stores: ${d.buyingCount}, Non-Buying Stores: ${d.nonBuyingCount}, Total Hapi Stores: ${d.totalHapiStores}');
      buffer.writeln('Buying Throughput: ${d.buyingThruput}');
      buffer.writeln('Total Placements: ${d.totalPlacementCount}, Total Expansions: ${d.totalExpansionCount}');
      buffer.writeln('Scanned Stores: ${d.totalScanCount}, Not Scanned: ${d.totalNotScannedCount}, Unassigned: ${d.totalUnassignedCount}');
      buffer.writeln('Pending PJP Visits: ${d.pendingPjpCount}, Unpaid Credits: ${d.unpaidCreditCount}');
    }
    return buffer.toString();
  }

  Future<void> _initSession() async {
    final contextPrompt = _buildOperationalContext();
    await _aiService.startChat(contextPrompt: contextPrompt.isNotEmpty ? contextPrompt : null);

    if (mounted) {
      setState(() {
        _messages.add(
          _ChatMessage(
            text:
                'Hello! I am Sedy, your AI assistant. 🚀\n'
                'I can help you review today\'s sales KPIs, check pending deliveries, plan your store visits, or draft reports. How can I assist you?',
            isUser: false,
            timestamp: DateTime.now(),
          ),
        );
      });
    }
  }

  Future<void> _handleSendMessage([String? predefinedText]) async {
    final text = predefinedText ?? _textController.text.trim();
    if (text.isEmpty || _isLoading) return;

    if (predefinedText == null) {
      _textController.clear();
    }

    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true, timestamp: DateTime.now()));
      _isLoading = true;
    });

    _scrollToBottom();

    try {
      final response = await _aiService.sendMessage(text);
      if (mounted) {
        setState(() {
          _messages.add(_ChatMessage(text: response, isUser: false, timestamp: DateTime.now()));
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(_ChatMessage(text: '⚠️ Error: ${e.toString().replaceAll('Exception: ', '')}', isUser: false, timestamp: DateTime.now()));
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 60,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildPresetChips() {
    final suggestions = [
      '📊 Summarize today\'s KPIs',
      '🚚 How many pending deliveries?',
      '🎯 Tips to hit sales target',
      '📝 Suggest action plan for today',
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: suggestions.map((chipText) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              label: Text(chipText, style: const TextStyle(fontSize: 12)),
              onPressed: _isLoading ? null : () => _handleSendMessage(chipText),
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildApiKeyNotice() {
    final colorScheme = Theme.of(context).colorScheme;
    final message = _statusCheck?.message ?? 'To activate the AI Assistant, please set your Gemini API key in the App Configurations.';
    final isQuotaOrDisabled = _statusCheck != null && !_statusCheck!.isAllowed;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: (isQuotaOrDisabled ? colorScheme.error : colorScheme.primary).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isQuotaOrDisabled ? Icons.shield_outlined : Icons.key_rounded,
                size: 40,
                color: isQuotaOrDisabled ? colorScheme.error : colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(isQuotaOrDisabled ? 'AI Assistant Paused' : 'Gemini Key Needed', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: const Text('Open Configurations'),
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConfigurationPage()));
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mediaQuery = MediaQuery.of(context);

    return Container(
      height: mediaQuery.size.height * 0.82,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 20, offset: const Offset(0, -4))],
      ),
      child: Column(
        children: [
          // Header handle & title
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [colorScheme.primary, colorScheme.secondary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Sedy AI', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('Powered by Google Gemini', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(context).pop(), tooltip: 'Close'),
              ],
            ),
          ),

          // Body
          Expanded(
            child: _checkingKey
                ? const Center(child: CircularProgressIndicator())
                : !_hasApiKey
                ? _buildApiKeyNotice()
                : Column(
                    children: [
                      if (_quotaAlertMessage != null)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded, size: 18, color: Colors.orange),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _quotaAlertMessage!,
                                  style: TextStyle(fontSize: 11.5, color: Colors.orange[900], fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Expanded(
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          itemCount: _messages.length,
                          itemBuilder: (ctx, index) {
                            return _buildMessageBubble(_messages[index], context, theme, mediaQuery);
                          },
                        ),
                      ),

                      if (_isLoading) _buildThinkingIndicator(theme),

                      // Prompt suggestions
                      _buildPresetChips(),

                      // Input bar
                      Container(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, mediaQuery.viewInsets.bottom + 12),
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5))),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _textController,
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) => _handleSendMessage(),
                                decoration: InputDecoration(
                                  hintText: 'Ask anything about your route, sales...',
                                  hintStyle: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  filled: true,
                                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                              onPressed: _isLoading ? null : () => _handleSendMessage(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildThinkingIndicator(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            margin: const EdgeInsets.only(top: 2, right: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 15),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 10),
                Text(
                  'Sedy is analyzing your data...',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(
    _ChatMessage message,
    BuildContext context,
    ThemeData theme,
    MediaQueryData mediaQuery,
  ) {
    if (message.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(maxWidth: mediaQuery.size.width * 0.78),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(4),
            ),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SelectableText(
                message.text,
                style: const TextStyle(fontSize: 13.5, color: Colors.white, height: 1.4),
              ),
              const SizedBox(height: 3),
              Text(
                DateFormat.jm().format(message.timestamp),
                style: TextStyle(fontSize: 9.5, color: Colors.white.withValues(alpha: 0.7)),
              ),
            ],
          ),
        ),
      );
    }

    // Sedy AI response
    final parsed = _ParsedAiMessage.parse(message.text);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sedy Avatar
          Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.only(top: 2, right: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
          ),

          // Message bubble + Action bar
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  constraints: BoxConstraints(maxWidth: mediaQuery.size.width * 0.88),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MarkdownBody(
                        data: parsed.mainContent,
                        selectable: true,
                        styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                          blockSpacing: 12.0,
                          listIndent: 28.0,
                          listBulletPadding: const EdgeInsets.only(right: 8),
                          p: TextStyle(
                            fontSize: 13.5,
                            color: theme.colorScheme.onSurface,
                            height: 1.55,
                          ),
                          listBullet: TextStyle(
                            color: theme.colorScheme.primary,
                            height: 1.55,
                          ),
                          strong: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                          h1: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                          h2: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                          h3: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                          code: TextStyle(
                            backgroundColor: theme.colorScheme.surfaceContainerHighest,
                            color: theme.colorScheme.primary,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                          codeblockDecoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                            ),
                          ),
                          blockquoteDecoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(6),
                            border: Border(
                              left: BorderSide(color: theme.colorScheme.primary, width: 3.5),
                            ),
                          ),
                          blockquotePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          tableColumnWidth: const IntrinsicColumnWidth(),
                          tableScrollbarThumbVisibility: true,
                          tablePadding: const EdgeInsets.symmetric(vertical: 8),
                          tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          tableCellsDecoration: BoxDecoration(
                            color: theme.colorScheme.surface.withValues(alpha: 0.35),
                          ),
                          tableVerticalAlignment: TableCellVerticalAlignment.middle,
                          tableBorder: TableBorder.all(
                            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                            width: 1,
                          ),
                          tableHead: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),

                      // Interactive Follow-up Question Chips
                      if (parsed.suggestedQuestions.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Divider(
                          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                          height: 1,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.lightbulb_outline_rounded, size: 14, color: theme.colorScheme.primary),
                            const SizedBox(width: 4),
                            Text(
                              'Suggested Follow-ups',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: parsed.suggestedQuestions.map((q) {
                            return ActionChip(
                              avatar: Icon(Icons.touch_app_rounded, size: 13, color: theme.colorScheme.primary),
                              label: Text(
                                q,
                                style: TextStyle(fontSize: 11.5, color: theme.colorScheme.onSurface),
                              ),
                              backgroundColor: theme.colorScheme.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                                ),
                              ),
                              onPressed: _isLoading ? null : () => _handleSendMessage(q),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),

                // Interactive Bottom Action Bar (Copy, Like/Dislike, Timestamp)
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 4),
                  child: Row(
                    children: [
                      Text(
                        DateFormat.jm().format(message.timestamp),
                        style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: message.text));
                          ShowMessage.success(context, 'Copied response to clipboard');
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.copy_rounded, size: 13, color: theme.colorScheme.onSurfaceVariant),
                              const SizedBox(width: 3),
                              Text(
                                'Copy',
                                style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          setState(() {
                            message.isLiked = (message.isLiked == true) ? null : true;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(3.0),
                          child: Icon(
                            message.isLiked == true ? Icons.thumb_up_rounded : Icons.thumb_up_outlined,
                            size: 13,
                            color: message.isLiked == true
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          setState(() {
                            message.isLiked = (message.isLiked == false) ? null : false;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(3.0),
                          child: Icon(
                            message.isLiked == false ? Icons.thumb_down_rounded : Icons.thumb_down_outlined,
                            size: 13,
                            color: message.isLiked == false
                                ? Colors.redAccent
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
