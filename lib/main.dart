// ============================================================================
//  Meatla Browser - Smart AI-Powered Browser
//  Developer: Mudasser Meatla (Meatla Creation)
//
//  pubspec.yaml dependencies:
//    flutter_inappwebview: ^6.1.5
//  Android: add <uses-permission android:name="android.permission.INTERNET"/>
//           and minSdkVersion 21+.   iOS: platform :ios, '12.0'
// ============================================================================

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MeatlaApp());
}

// ============================================================================
// 1. CONSTANTS & DATA
// ============================================================================
const kAppName = 'Meatla Browser';
const kTagline = 'Meatla Browser - Smart AI-Powered Browser';
const kVersion = '1.0.0';
const kDeveloper = 'Mudasser Meatla (Meatla Creation)';
const kEmail = 'mudassermeatla576@gmail.com';

const kNavy = Color(0xFF050B24);
const kNavy2 = Color(0xFF0B1B4D);
const kSky = Color(0xFF38BDF8);

class AiSite {
  const AiSite(this.name, this.url, this.icon, this.color, [this.queryUrl]);
  final String name;
  final String url;
  final IconData icon;
  final Color color;

  /// If the site accepts a prompt via URL, this is the prefix to append to.
  final String? queryUrl;
}

const kAiSites = <AiSite>[
  AiSite('ChatGPT', 'https://chatgpt.com', Icons.chat_bubble_rounded,
      Color(0xFF10A37F), 'https://chatgpt.com/?q='),
  AiSite('Gemini', 'https://gemini.google.com', Icons.auto_awesome,
      Color(0xFF4285F4)),
  AiSite('Claude', 'https://claude.ai', Icons.psychology_alt_rounded,
      Color(0xFFD97757)),
  AiSite('Copilot', 'https://copilot.microsoft.com', Icons.flight_takeoff,
      Color(0xFF7C4DFF)),
  AiSite('Perplexity', 'https://perplexity.ai', Icons.travel_explore,
      Color(0xFF20B8CD), 'https://www.perplexity.ai/search?q='),
];

enum SearchEngine {
  google('Google', 'https://www.google.com/search?q='),
  bing('Bing', 'https://www.bing.com/search?q='),
  duckduckgo('DuckDuckGo', 'https://duckduckgo.com/?q=');

  const SearchEngine(this.label, this.searchUrl);
  final String label;
  final String searchUrl;
}

/// Hosts blocked by the built-in ad & tracker blocker.
const kBlockedHosts = <String>[
  'doubleclick.net',
  'googlesyndication.com',
  'googleadservices.com',
  'google-analytics.com',
  'googletagmanager.com',
  'adservice.google.com',
  'adnxs.com',
  'taboola.com',
  'outbrain.com',
  'scorecardresearch.com',
  'facebook.net/en_US/fbevents.js',
  'hotjar.com',
  'criteo.com',
  'amazon-adsystem.com',
  'moatads.com',
  'quantserve.com',
];
// ============================================================================
// 2. STATE MODEL
// ============================================================================
class BrowserTab {
  BrowserTab({this.url, this.isIncognito = false}) : id = _counter++;
  static int _counter = 0;

  final int id;
  final bool isIncognito;

  /// null => the tab shows the AI dashboard (home).
  String? url;
  String title = 'New Tab';
  double progress = 0;
  bool loading = false;
  bool canBack = false;
  bool canForward = false;
  InAppWebViewController? controller;

  bool get isHome => url == null;
}

class BrowserModel extends ChangeNotifier {
  final List<BrowserTab> tabs = [BrowserTab()];
  int current = 0;

  SearchEngine engine = SearchEngine.google;
  bool adBlock = true;
  ThemeMode themeMode = ThemeMode.dark;

  // Split-screen state
  bool splitActive = false;
  AiSite splitLeft = kAiSites[0];
  AiSite splitRight = kAiSites[2];

  // AI panel state
  AiSite panelAi = kAiSites[0];

  BrowserTab get tab => tabs[current];

  void refresh() => notifyListeners();

  // ---- URL parsing --------------------------------------------------------
  /// Turns whatever the user typed into a loadable URL.
  String resolve(String input) {
    final text = input.trim();
    if (text.isEmpty) return engine.searchUrl;
    final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(text);
    if (hasScheme) return text;
    final looksLikeHost = !text.contains(' ') &&
        (RegExp(r'^[\w-]+(\.[\w-]+)+(:\d+)?(/.*)?$').hasMatch(text) ||
            text.startsWith('localhost'));
    if (looksLikeHost) return 'https://$text';
    return engine.searchUrl + Uri.encodeQueryComponent(text);
  }

  // ---- Navigation ---------------------------------------------------------
  void navigate(String input) {
    final url = resolve(input);
    final t = tab;
    splitActive = false;
    if (t.controller != null && !t.isHome) {
      t.controller!.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    } else {
      t.url = url; // builds a new webview which loads this URL
      t.loading = true;
    }
    notifyListeners();
  }

  Future<void> goBack() async {
    final c = tab.controller;
    if (splitActive) {
      splitActive = false;
    } else if (c != null && await c.canGoBack()) {
      await c.goBack();
    } else if (!tab.isHome) {
      goHome();
    }
    notifyListeners();
  }

  Future<void> goForward() async {
    final c = tab.controller;
    if (c != null && await c.canGoForward()) await c.goForward();
  }

  void reload() => tab.controller?.reload();

  void goHome() {
    splitActive = false;
    tab
      ..url = null
      ..title = 'New Tab'
      ..controller = null
      ..progress = 0
      ..loading = false
      ..canBack = false
      ..canForward = false;
    notifyListeners();
  }

  // ---- Tabs ---------------------------------------------------------------
  void newTab({String? url, bool incognito = false}) {
    tabs.add(BrowserTab(url: url, isIncognito: incognito));
    current = tabs.length - 1;
    splitActive = false;
    notifyListeners();
  }

  void closeTab(int i) {
    if (i < 0 || i >= tabs.length) return;
    if (tabs.length == 1) {
      if (tabs.first.isIncognito) {
        tabs[0] = BrowserTab();
        current = 0;
        splitActive = false;
        notifyListeners();
      } else {
        goHome();
      }
      return;
    }
    tabs.removeAt(i);
    if (i < current) current--;
    if (current >= tabs.length) current = tabs.length - 1;
    splitActive = false;
    notifyListeners();
  }

  void selectTab(int i) {
    if (i < 0 || i >= tabs.length) return;
    current = i;
    splitActive = false;
    notifyListeners();
  }

  // ---- Settings -----------------------------------------------------------
  void setEngine(SearchEngine e) {
    engine = e;
    notifyListeners();
  }

  void setTheme(ThemeMode m) {
    themeMode = m;
    notifyListeners();
  }

  List<ContentBlocker> blockers() {
    if (!adBlock) return [];
    return [
      for (final host in kBlockedHosts)
        ContentBlocker(
          trigger: ContentBlockerTrigger(
              urlFilter: '.*${host.replaceAll('.', r'\.')}.*'),
          action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
        ),
      // Hide leftover ad containers.
      ContentBlocker(
        trigger: ContentBlockerTrigger(urlFilter: '.*'),
        action: ContentBlockerAction(
          type: ContentBlockerActionType.CSS_DISPLAY_NONE,
          selector:
              '.adsbygoogle, [id^="google_ads"], [class*="ad-banner"], [class*="sponsored-ad"], ins.adsbygoogle',
        ),
      ),
    ];
  }

  Future<void> setAdBlock(bool value) async {
    adBlock = value;
    notifyListeners();
    for (final t in tabs) {
      final c = t.controller;
      if (c == null) continue;
      await c.setSettings(
          settings: InAppWebViewSettings(contentBlockers: blockers()));
      await c.reload();
    }
  }

  void openSplit() {
    splitActive = true;
    notifyListeners();
  }
}
// ============================================================================
// 3. THEME & GLASS UI
// ============================================================================
class MeatlaApp extends StatelessWidget {
  MeatlaApp({super.key});
  final BrowserModel model = BrowserModel();

  ThemeData _theme(Brightness b) {
    final dark = b == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: kSky,
      brightness: b,
      surface: dark ? kNavy : const Color(0xFFEAF4FF),
    ).copyWith(primary: kSky);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? kNavy : const Color(0xFFEAF4FF),
      fontFamily: 'Roboto',
      textTheme: ThemeData(brightness: b).textTheme.apply(
            bodyColor: dark ? Colors.white : const Color(0xFF0B1B4D),
            displayColor: dark ? Colors.white : const Color(0xFF0B1B4D),
          ),
      appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent, elevation: 0, centerTitle: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (_, __) => MaterialApp(
        title: kAppName,
        debugShowCheckedModeBanner: false,
        themeMode: model.themeMode,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: BrowserPage(model: model),
      ),
    );
  }
}

bool _isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

/// Deep navy gradient (dark) / soft sky gradient (light) background.
class GradientBg extends StatelessWidget {
  const GradientBg({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [kNavy, kNavy2, Color(0xFF071336)]
              : const [Color(0xFFEAF4FF), Color(0xFFCFE8FF), Color(0xFFEAF4FF)],
        ),
      ),
      child: child,
    );
  }
}

/// Frosted-glass card with a soft sky-blue glow.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = 20,
    this.onTap,
    this.glow = true,
  });
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final VoidCallback? onTap;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: glow
            ? [BoxShadow(color: kSky.withOpacity(dark ? .18 : .12), blurRadius: 18)]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Material(
            color: dark
                ? Colors.white.withOpacity(.07)
                : Colors.white.withOpacity(.65),
            child: InkWell(
              onTap: onTap,
              child: Container(
                padding: padding,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(color: kSky.withOpacity(.35)),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
// ============================================================================
// 4. BROWSER PAGE
// ============================================================================
class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key, required this.model});
  final BrowserModel model;

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  final _urlCtrl = TextEditingController();
  final _focus = FocusNode();
  BrowserModel get m => widget.model;

  @override
  void initState() {
    super.initState();
    m.addListener(_syncUrl);
  }

  void _syncUrl() {
    if (!_focus.hasFocus) {
      _urlCtrl.text = m.tab.url ?? '';
    }
  }

  @override
  void dispose() {
    m.removeListener(_syncUrl);
    _urlCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String v) {
    _focus.unfocus();
    m.navigate(v);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: m,
      builder: (context, _) {
        final t = m.tab;
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) m.goBack();
          },
          child: Scaffold(
            body: GradientBg(
              child: SafeArea(
                child: Column(
                  children: [
                    _topBar(t),
                    SizedBox(
                      height: 3,
                      child: t.loading && !m.splitActive
                          ? LinearProgressIndicator(
                              value: t.progress == 0 ? null : t.progress,
                              backgroundColor: Colors.transparent,
                              color: kSky,
                            )
                          : null,
                    ),
                    Expanded(
                      child: m.splitActive
                          ? SplitView(model: m)
                          : Stack(
                              children: [
                                IndexedStack(
                                  index: m.current,
                                  children: [
                                    for (final tab in m.tabs)
                                      tab.isHome
                                          ? HomeDashboard(
                                              key: ValueKey('home${tab.id}'),
                                              model: m)
                                          : BrowserWebView(
                                              key: ValueKey('web${tab.id}'),
                                              tab: tab,
                                              model: m),
                                  ],
                                ),
                                Positioned(
                                  right: 16,
                                  bottom: 16,
                                  child: _aiFab(),
                                ),
                              ],
                            ),
                    ),
                    _bottomBar(t),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _aiFab() => Container(
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
          BoxShadow(color: kSky.withOpacity(.6), blurRadius: 22)
        ]),
        child: FloatingActionButton(
          heroTag: 'ai',
          backgroundColor: kSky,
          foregroundColor: kNavy,
          onPressed: () => showAiPanel(context, m),
          child: const Icon(Icons.auto_awesome),
        ),
      );

  // ---- Top bar: engine switcher + address field + split button ------------
  Widget _topBar(BrowserTab t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        radius: 28,
        child: Row(
          children: [
            PopupMenuButton<SearchEngine>(
              tooltip: 'Search engine',
              initialValue: m.engine,
              onSelected: m.setEngine,
              itemBuilder: (_) => [
                for (final e in SearchEngine.values)
                  PopupMenuItem(value: e, child: Text(e.label)),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.search, color: kSky, size: 20),
                  Text(m.engine.label.substring(0, 1),
                      style: const TextStyle(
                          color: kSky, fontWeight: FontWeight.bold)),
                  const Icon(Icons.arrow_drop_down, size: 18),
                ]),
              ),
            ),
            Expanded(
              child: TextField(
                controller: _urlCtrl,
                focusNode: _focus,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                onSubmitted: _submit,
                onTap: () => _urlCtrl.selection = TextSelection(
                    baseOffset: 0, extentOffset: _urlCtrl.text.length),
                decoration: InputDecoration(
                  hintText: 'Search with ${m.engine.label} or enter URL',
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
                        if (m.adBlock)
              const Tooltip(
                  message: 'Ad & tracker blocker on',
                  child: Icon(Icons.shield, color: kSky, size: 20)),
            IconButton(
              tooltip: 'Split-screen AI',
              icon: Icon(Icons.vertical_split_rounded,
                  color: m.splitActive ? kSky : null),
              onPressed: () {
                if (m.splitActive) {
                  m.splitActive = false;
                  m.refresh();
                } else {
                  m.openSplit();
                }
              },
            ),
          ],
        ),
      ),
    );
  }


  // ---- Bottom toolbar -----------------------------------------------------
  Widget _bottomBar(BrowserTab t) {
    Widget btn(IconData i, String tip, VoidCallback? f, {Widget? badge}) =>
        IconButton(
          tooltip: tip,
          icon: badge ?? Icon(i),
          onPressed: f,
          color: kSky,
          disabledColor: Colors.grey.withOpacity(.4),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
      child: GlassCard(
        radius: 26,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            btn(Icons.arrow_back_rounded, 'Back', m.goBack),
            btn(Icons.arrow_forward_rounded, 'Forward',
                t.canForward ? m.goForward : null),
            btn(t.loading ? Icons.close_rounded : Icons.refresh_rounded,
                'Reload', () {
              if (t.loading) {
                t.controller?.stopLoading();
              } else {
                m.reload();
              }
            }),
            btn(Icons.home_rounded, 'Home', m.goHome),
            btn(
              Icons.tab,
              'Tabs',
              () => showTabManager(context, m),
              badge: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: kSky, width: 1.6),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text('${m.tabs.length}',
                    style: const TextStyle(
                        color: kSky,
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
              ),
            ),
            btn(Icons.settings_rounded, 'Settings', () {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => SettingsPage(model: m)));
            }),
          ],
        ),
      ),
    );
  }
}
/// A single tab's webview.
class BrowserWebView extends StatelessWidget {
  const BrowserWebView({super.key, required this.tab, required this.model});
  final BrowserTab tab;
  final BrowserModel model;

  Future<void> _updateNav(InAppWebViewController c) async {
    tab.canBack = await c.canGoBack();
    tab.canForward = await c.canGoForward();
    model.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(tab.url!)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        useShouldOverrideUrlLoading: true,
        allowsInlineMediaPlayback: true,
        mediaPlaybackRequiresUserGesture: false,
        supportZoom: true,
        incognito: tab.isIncognito,
        contentBlockers: model.blockers(),
        // A modern mobile UA keeps AI sites happy.
        userAgent:
            'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36 MeatlaBrowser/$kVersion',
      ),
      onWebViewCreated: (c) => tab.controller = c,
      shouldOverrideUrlLoading: (c, action) async {
        final scheme = action.request.url?.scheme ?? '';
        if (!['http', 'https', 'about', 'file', 'data', 'blob']
            .contains(scheme)) {
          return NavigationActionPolicy.CANCEL; // block external app schemes
        }
        return NavigationActionPolicy.ALLOW;
      },
      onLoadStart: (c, url) {
        tab.loading = true;
        tab.url = url?.toString() ?? tab.url;
        model.refresh();
      },
      onProgressChanged: (c, p) {
        tab.progress = p / 100;
        tab.loading = p < 100;
        model.refresh();
      },
      onLoadStop: (c, url) async {
        tab.loading = false;
        tab.url = url?.toString() ?? tab.url;
        await _updateNav(c);
      },
      onUpdateVisitedHistory: (c, url, _) async {
        tab.url = url?.toString() ?? tab.url;
        await _updateNav(c);
      },
      onTitleChanged: (c, title) {
        tab.title = (title == null || title.isEmpty) ? tab.title : title;
        model.refresh();
      },
      onCreateWindow: (c, req) async {
        final u = req.request.url?.toString();
        if (u != null) model.newTab(url: u, incognito: tab.isIncognito);
        return true;
      },
    );
  }
}

// ---- Home: AI quick-access dashboard ---------------------------------------
class HomeDashboard extends StatelessWidget {
  const HomeDashboard({super.key, required this.model});
  final BrowserModel model;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final cols = w > 700 ? 4 : (w > 420 ? 3 : 2);
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const SizedBox(height: 10),
        Center(
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: [kSky, Color(0xFF2563EB)]),
              boxShadow: [BoxShadow(color: kSky.withOpacity(.6), blurRadius: 30)],
            ),
            child: ClipOval(
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Image.asset(
                  'copilot_image_1792323887881.png',
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.public, size: 46, color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Center(
          child: Text(kAppName,
              style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text('Smart AI-Powered Browser',
              style: TextStyle(color: kSky.withOpacity(.9), letterSpacing: 2)),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => model.newTab(),
            icon: const Icon(Icons.add_rounded),
            label: const Text('New Tab'),
            style: FilledButton.styleFrom(
              backgroundColor: kSky,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text('AI Quick Access',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.15,
          children: [
            for (final s in kAiSites)
              GlassCard(
                onTap: () => model.navigate(s.url),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: s.color.withOpacity(.2),
                      child: Icon(s.icon, color: s.color, size: 26),
                    ),
                    const SizedBox(height: 10),
                    Text(s.name,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            GlassCard(
              onTap: () => model.navigate(
                  'https://toolforge1.github.io/csv-json-tools/'),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: const Color(0xFF38BDF8).withOpacity(.2),
                    child: const Icon(Icons.code_rounded,
                        color: Color(0xFF38BDF8), size: 26),
                  ),
                  const SizedBox(height: 10),
                  const Text('Developer Tool',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        GlassCard(
          onTap: model.openSplit,
          child: const Row(
            children: [
              Icon(Icons.vertical_split_rounded, color: kSky, size: 30),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Split-Screen AI Compare',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    Text('Open two AI tools side-by-side',
                        style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GlassCard(
          child: Row(
            children: [
              const Icon(Icons.shield_rounded, color: kSky, size: 30),
              const SizedBox(width: 14),
              const Expanded(
                child: Text('Ad & Tracker Blocker',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              Switch(
                value: model.adBlock,
                activeColor: kSky,
                onChanged: model.setAdBlock,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
// ============================================================================
// 5. SPLIT-SCREEN MULTI-AI VIEW
// ============================================================================
class SplitView extends StatefulWidget {
  const SplitView({super.key, required this.model});
  final BrowserModel model;

  @override
  State<SplitView> createState() => _SplitViewState();
}

class _SplitViewState extends State<SplitView> {
  final _promptCtrl = TextEditingController();
  InAppWebViewController? _left, _right;
  BrowserModel get m => widget.model;

  /// Sends one prompt to both panes. Sites without URL-prompt support get the
  /// prompt on the clipboard instead - just paste it into the chat box.
  void _sendToBoth() {
    final q = _promptCtrl.text.trim();
    if (q.isEmpty) return;
    Clipboard.setData(ClipboardData(text: q));
    var needsPaste = false;
    void go(AiSite s, InAppWebViewController? c) {
      if (c == null) return;
      if (s.queryUrl != null) {
        c.loadUrl(
            urlRequest:
                URLRequest(url: WebUri(s.queryUrl! + Uri.encodeQueryComponent(q))));
      } else {
        needsPaste = true;
      }
    }

    go(m.splitLeft, _left);
    go(m.splitRight, _right);
    if (needsPaste) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Prompt copied - paste it into the other AI.')));
    }
  }

  Widget _pane(bool isLeft) {
    final site = isLeft ? m.splitLeft : m.splitRight;
    return GlassCard(
      padding: EdgeInsets.zero,
      radius: 16,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: DropdownButton<AiSite>(
              value: site,
              isExpanded: true,
              underline: const SizedBox(),
              dropdownColor: kNavy2,
              items: [
                for (final s in kAiSites)
                  DropdownMenuItem(
                    value: s,
                    child: Row(children: [
                      Icon(s.icon, color: s.color, size: 18),
                      const SizedBox(width: 8),
                      Text(s.name),
                    ]),
                  ),
              ],
              onChanged: (s) {
                if (s == null) return;
                isLeft ? m.splitLeft = s : m.splitRight = s;
                m.refresh();
              },
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(16)),
              child: InAppWebView(
                key: ValueKey('${isLeft ? 'L' : 'R'}${site.name}'),
                initialUrlRequest: URLRequest(url: WebUri(site.url)),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  contentBlockers: m.blockers(),
                ),
                onWebViewCreated: (c) => isLeft ? _left = c : _right = c,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _promptCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(builder: (context, box) {
              // Wide screens: side-by-side. Narrow phones: stacked.
              final wide = box.maxWidth > 600;
              final children = [
                Expanded(child: _pane(true)),
                SizedBox(width: wide ? 10 : 0, height: wide ? 0 : 10),
                Expanded(child: _pane(false)),
              ];
              return wide ? Row(children: children) : Column(children: children);
            }),
          ),
          const SizedBox(height: 8),
          GlassCard(
            radius: 24,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _promptCtrl,
                    onSubmitted: (_) => _sendToBoth(),
                    decoration: const InputDecoration(
                        hintText: 'Ask both AIs the same question…',
                        border: InputBorder.none),
                  ),
                ),
                IconButton(
                    icon: const Icon(Icons.send_rounded, color: kSky),
                    onPressed: _sendToBoth),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
// ============================================================================
// 6a. SMART AI PANEL (Summarize / Translate / Chat)
// ============================================================================
void showAiPanel(BuildContext context, BrowserModel m) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        Future<void> summarize() async {
          Navigator.pop(ctx);
          final c = m.tab.controller;
          if (c == null || m.tab.isHome) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Open a web page first.')));
            return;
          }
          final raw = await c.evaluateJavascript(
              source: 'document.body.innerText.substring(0, 6000)');
          final prompt =
              'Summarize this page in clear bullet points.\nURL: ${m.tab.url}\n\n$raw';
          await Clipboard.setData(ClipboardData(text: prompt));
          final ai = m.panelAi;
          if (ai.queryUrl != null) {
            final short =
                'Summarize this page in bullet points: ${m.tab.url}';
            m.newTab(url: ai.queryUrl! + Uri.encodeQueryComponent(short));
          } else {
            m.newTab(url: ai.url);
          }
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Page text copied - paste it into the chat.')));
          }
        }

        void translate(String lang) {
          Navigator.pop(ctx);
          final u = m.tab.url;
          if (u == null) return;
          m.navigate(
              'https://translate.google.com/translate?sl=auto&tl=$lang&u=${Uri.encodeComponent(u)}');
        }

        void chat() {
          Navigator.pop(ctx);
          m.newTab(url: m.panelAi.url);
        }

        return Padding(
          padding: const EdgeInsets.all(12),
          child: GlassCard(
            radius: 28,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.auto_awesome, color: kSky),
                  SizedBox(width: 8),
                  Text('Meatla AI Assistant',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final s in kAiSites)
                      ChoiceChip(
                        label: Text(s.name),
                        selected: m.panelAi == s,
                        selectedColor: kSky.withOpacity(.35),
                        onSelected: (_) {
                          m.panelAi = s;
                          setSheet(() {});
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _panelTile(Icons.summarize_rounded, 'Summarize page',
                    'Send this page to ${m.panelAi.name}', summarize),
                _panelTile(Icons.chat_rounded, 'Chat',
                    'Open ${m.panelAi.name} in a new tab', chat),
                const SizedBox(height: 6),
                const Text('Translate page to:',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final e in const {
                      'English': 'en',
                      'اردو': 'ur',
                      'العربية': 'ar',
                      'हिन्दी': 'hi',
                      'Español': 'es',
                    }.entries)
                      ActionChip(
                          label: Text(e.key),
                          onPressed: () => translate(e.value)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

Widget _panelTile(IconData i, String t, String sub, VoidCallback f) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
          backgroundColor: kSky.withOpacity(.2),
          child: Icon(i, color: kSky)),
      title: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(sub),
      onTap: f,
    );

// ============================================================================
// 6b. TAB MANAGER
// ============================================================================
void showTabManager(BuildContext context, BrowserModel m) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => ListenableBuilder(
      listenable: m,
      builder: (ctx, _) => Padding(
        padding: const EdgeInsets.all(12),
        child: GlassCard(
          radius: 28,
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * .6,
            child: Column(
              children: [
                Row(children: [
                  Expanded(
                    child: Text('${m.tabs.length} Tabs',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    tooltip: 'Close tab manager',
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ]),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          m.newTab();
                          Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('New Tab'),
                        style: FilledButton.styleFrom(
                          backgroundColor: kSky,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          m.newTab(incognito: true);
                          Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.visibility_off_rounded),
                        label: const Text('Incognito'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kSky,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 1.6),
                    itemCount: m.tabs.length,
                    itemBuilder: (_, i) {
                      final t = m.tabs[i];
                      final selected = i == m.current;
                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: selected ? kSky : Colors.white24,
                              width: selected ? 2 : 1),
                          color: Colors.white.withOpacity(.05),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            m.selectTab(i);
                            Navigator.pop(ctx);
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Icon(
                                    t.isIncognito
                                        ? Icons.visibility_off_rounded
                                        : (t.isHome ? Icons.home_rounded : Icons.language_rounded),
                                    size: 17,
                                    color: t.isIncognito ? Colors.deepPurpleAccent : kSky,
                                  ),
                                  const SizedBox(width: 5),
                                  if (t.isIncognito)
                                    const Expanded(
                                      child: Text('INCOGNITO',
                                        maxLines: 1,
                                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.deepPurpleAccent),
                                      ),
                                    )
                                  else
                                    const Spacer(),
                                  Material(
                                    color: Colors.red.withOpacity(.15),
                                    shape: const CircleBorder(),
                                    child: IconButton(
                                      tooltip: 'Close this tab',
                                      visualDensity: VisualDensity.compact,
                                      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                                      padding: EdgeInsets.zero,
                                      onPressed: () => m.closeTab(i),
                                      icon: const Icon(Icons.close_rounded, size: 18, color: Colors.redAccent),
                                    ),
                                  ),
                                ]),
                                const Spacer(),
                                Text(t.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                Text(t.isIncognito ? 'Private tab • history not saved' : (t.url ?? 'meatla://home'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11)),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
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
// ============================================================================
// 6c. SETTINGS & ABOUT
// ============================================================================
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.model});
  final BrowserModel model;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(title: const Text('Settings')),
        body: GradientBg(
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                GlassCard(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeColor: kSky,
                    secondary: const Icon(Icons.shield_rounded, color: kSky),
                    title: const Text('Block ads & trackers'),
                    subtitle: const Text('Faster pages, less tracking'),
                    value: model.adBlock,
                    onChanged: model.setAdBlock,
                  ),
                ),
                const SizedBox(height: 12),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Default search engine',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      SegmentedButton<SearchEngine>(
                        segments: [
                          for (final e in SearchEngine.values)
                            ButtonSegment(value: e, label: Text(e.label)),
                        ],
                        selected: {model.engine},
                        onSelectionChanged: (s) => model.setEngine(s.first),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Appearance',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                              value: ThemeMode.dark,
                              icon: Icon(Icons.dark_mode),
                              label: Text('Dark')),
                          ButtonSegment(
                              value: ThemeMode.light,
                              icon: Icon(Icons.light_mode),
                              label: Text('Light')),
                          ButtonSegment(
                              value: ThemeMode.system,
                              icon: Icon(Icons.phone_android),
                              label: Text('Auto')),
                        ],
                        selected: {model.themeMode},
                        onSelectionChanged: (s) => model.setTheme(s.first),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                GlassCard(
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const AboutPage())),
                  child: const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.info_rounded, color: kSky),
                    title: Text('About Meatla Browser'),
                    trailing: Icon(Icons.chevron_right),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    Widget row(IconData i, String label, String value, {VoidCallback? onTap}) =>
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(i, color: kSky),
          title: Text(label, style: const TextStyle(fontSize: 12)),
          subtitle: Text(value,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          onTap: onTap,
        );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: const Text('About Meatla Browser')),
      body: GradientBg(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              const SizedBox(height: 20),
              Center(
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient:
                        const LinearGradient(colors: [kSky, Color(0xFF2563EB)]),
                    boxShadow: [
                      BoxShadow(color: kSky.withOpacity(.6), blurRadius: 34)
                    ],
                  ),
                  child:
                      const Icon(Icons.public, size: 56, color: Colors.white),
                ),
              ),
              const SizedBox(height: 16),
              const Center(
                child: Text(kAppName,
                    style:
                        TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 6),
              const Center(
                child: Text(kTagline,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: kSky)),
              ),
              const SizedBox(height: 26),
              GlassCard(
                child: Column(
                  children: [
                    row(Icons.person_rounded, 'Developer', kDeveloper),
                    row(Icons.email_rounded, 'Contact Email', kEmail,
                        onTap: () {
                      Clipboard.setData(const ClipboardData(text: kEmail));
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Email copied')));
                    }),
                    row(Icons.verified_rounded, 'App Version', kVersion),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
