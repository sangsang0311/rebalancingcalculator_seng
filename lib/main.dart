import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  // Flutter UI를 정상적으로 실행합니다.
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '리밸런싱 계산기',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: '리밸런싱 계산기'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late final WebViewController? controller;

  @override
  void initState() {
    super.initState();
    
    // 웹 버전에서는 WebViewController를 사용하지 않음
    if (!kIsWeb) {
      // 모바일에서만 WebViewController 초기화
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..loadFlutterAsset('assets/index.html')
        ..setBackgroundColor(Colors.transparent)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (String url) {
              controller?.runJavaScript('''
                document.querySelector('meta[name="viewport"]').setAttribute(
                  'content',
                  'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no'
                );
              ''');
            },
          ),
        );
    } else {
      controller = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.width < 600;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(
          widget.title,
          style: TextStyle(fontSize: isSmallScreen ? 18 : 24),
        ),
      ),
      body: SafeArea(
        child: kIsWeb 
            ? WebVersionContent() // 웹 버전에서는 일반 Flutter 위젯 사용
            : WebViewWidget(controller: controller!), // 모바일에서는 WebView 사용
      ),
    );
  }
}

// 웹 버전에서 표시할 콘텐츠 위젯
class WebVersionContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(
              Icons.calculate_outlined,
              size: 80,
              color: Color(0xFF6200EE),
            ),
            const SizedBox(height: 20),
            Text(
              '리밸런싱 계산기',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: const Color(0xFF6200EE),
                fontWeight: FontWeight.bold
              ),
            ),
            const SizedBox(height: 40),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text(
                    '현재 웹 버전에서 계산기 기능을 준비 중입니다',
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '모바일 앱에서 더 나은 경험을 제공해 드립니다.\n개발자에게 문의하시거나 잠시 후 다시 시도해 주세요.',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
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