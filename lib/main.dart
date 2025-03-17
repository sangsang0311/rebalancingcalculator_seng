import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

void main() {
  // Flutter UI를 정상적으로 실행합니다.
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '자산 리밸런싱',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: '-apple-system, BlinkMacSystemFont, Segoe UI, Roboto, sans-serif',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF007BFF),
          primary: const Color(0xFF007BFF),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F4F9),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: const Color(0xFF007BFF),
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 10),
            textStyle: const TextStyle(fontSize: 16),
          ),
        ),
      ),
      home: const MyHomePage(title: '자산 리밸런싱'),
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
  bool isWebViewEnabled = !kIsWeb; // 웹에서는 WebView 대신 Flutter UI 사용

  @override
  void initState() {
    super.initState();
    
    // 모바일에서만 WebViewController 초기화
    if (isWebViewEnabled) {
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
    return Scaffold(
      // 앱바 완전 제거
      body: SafeArea(
        child: isWebViewEnabled
            ? Stack(
                children: [
                  WebViewWidget(controller: controller!),
                  // WebView에서 Flutter UI로 전환하는 작은 플로팅 버튼
                  Positioned(
                    bottom: 20,
                    right: 20,
                    child: FloatingActionButton.small(
                      onPressed: () {
                        setState(() {
                          isWebViewEnabled = false;
                        });
                      },
                      child: const Icon(Icons.flutter_dash, size: 20),
                      tooltip: 'Flutter UI로 전환',
                    ),
                  ),
                ],
              )
            : const RebalancingCalculator(),
      ),
    );
  }
}

class RebalancingCalculator extends StatefulWidget {
  const RebalancingCalculator({super.key});

  @override
  State<RebalancingCalculator> createState() => _RebalancingCalculatorState();
}

class _RebalancingCalculatorState extends State<RebalancingCalculator> {
  final currencyFormatter = NumberFormat.currency(locale: 'ko_KR', symbol: '', decimalDigits: 0);
  final cashController = TextEditingController();
  
  // 항상 5개의 자산을 유지 (UI에 표시할 개수와는 별도)
  static const int maxAssetCount = 5;
  int displayAssetCount = 1; // UI에 표시할 자산 개수
  
  // 항상 5개의 컨트롤러와 데이터를 유지
  late List<TextEditingController> allAssetNameControllers;
  late List<TextEditingController> allAssetValueControllers;
  late List<int> allAssetTargetRatios;
  
  double totalAmount = 0;
  List<Map<String, dynamic>> adjustmentResults = [];
  Map<String, Map<String, dynamic>> finalResults = {};
  bool showResults = false;
  
  @override
  void initState() {
    super.initState();
    // 항상 5개의 컨트롤러 생성
    allAssetNameControllers = List.generate(maxAssetCount, (_) => TextEditingController());
    allAssetValueControllers = List.generate(maxAssetCount, (_) => TextEditingController());
    allAssetTargetRatios = List.filled(maxAssetCount, 0);
    
    loadState();
  }
  
  @override
  void dispose() {
    cashController.dispose();
    for (var controller in allAssetNameControllers) {
      controller.dispose();
    }
    for (var controller in allAssetValueControllers) {
      controller.dispose();
    }
    super.dispose();
  }
  
  // 앱 상태 저장
  Future<void> saveState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 모든 자산 데이터 수집
      final allNames = allAssetNameControllers.map((c) => c.text).toList();
      final allValues = allAssetValueControllers.map((c) => c.text).toList();
      final allRatios = allAssetTargetRatios.toList();
      
      // 상태 저장
      final state = {
        'cash_value': cashController.text,
        'display_asset_count': displayAssetCount,
        'all_asset_names': allNames,
        'all_asset_values': allValues,
        'all_asset_ratios': allRatios,
      };
      await prefs.setString('rebalancing_state', jsonEncode(state));
    } catch (e) {
      debugPrint('상태 저장 오류: $e');
    }
  }
  
  // 앱 상태 로드
  Future<void> loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stateJson = prefs.getString('rebalancing_state');
      if (stateJson != null) {
        final state = jsonDecode(stateJson);
        setState(() {
          cashController.text = state['cash_value'] ?? '';
          displayAssetCount = state['display_asset_count'] ?? 1;
          
          // 저장된 모든 자산 데이터 로드
          final savedNames = List<String>.from(state['all_asset_names'] ?? []);
          final savedValues = List<String>.from(state['all_asset_values'] ?? []);
          final savedRatios = List<int>.from(state['all_asset_ratios'] ?? []);
          
          // 저장된 데이터를 컨트롤러에 설정
          for (int i = 0; i < maxAssetCount; i++) {
            if (i < savedNames.length) {
              allAssetNameControllers[i].text = savedNames[i];
            }
            
            if (i < savedValues.length) {
              allAssetValueControllers[i].text = savedValues[i];
            }
            
            if (i < savedRatios.length) {
              allAssetTargetRatios[i] = savedRatios[i];
            }
          }
        });
        
        updateTotalAmount();
      }
    } catch (e) {
      debugPrint('상태 로드 오류: $e');
    }
  }
  
  // 자산 개수 업데이트 (UI에 표시할 개수만 변경)
  void updateAssetCount(int newCount) {
    if (newCount < 1 || newCount > maxAssetCount) return;
    
    setState(() {
      displayAssetCount = newCount;
    });
    
    saveState();
    updateTotalAmount();
  }
  
  void updateTotalAmount() {
    double cash = double.tryParse(cashController.text.replaceAll(',', '')) ?? 0;
    double assetsSum = 0;
    
    // 현재 표시된 자산만 총액에 포함
    for (int i = 0; i < displayAssetCount; i++) {
      assetsSum += double.tryParse(allAssetValueControllers[i].text.replaceAll(',', '')) ?? 0;
    }
    
    setState(() {
      totalAmount = cash + assetsSum;
      showResults = false;
    });
  }
  
  String formatCurrency(double value) {
    return currencyFormatter.format(value);
  }
  
  void formatNumberWithCommas(TextEditingController controller) {
    String value = controller.text.replaceAll(',', '');
    double? number = double.tryParse(value);
    if (number != null) {
      if (number > 999999999999) {
        number = 999999999999;
      }
      controller.text = formatCurrency(number);
      controller.selection = TextSelection.fromPosition(
        TextPosition(offset: controller.text.length)
      );
    }
    updateTotalAmount();
    saveState();
  }
  
  double getCurrentRatio(double value) {
    if (totalAmount == 0) return 0;
    return (value / totalAmount) * 100;
  }
  
  int getCashTargetRatio() {
    // 현재 표시된 자산의 목표 비율만 합산
    int sum = 0;
    for (int i = 0; i < displayAssetCount; i++) {
      sum += allAssetTargetRatios[i];
    }
    return max(0, 100 - sum);
  }
  
  void updateRatios() {
    setState(() {
      // 현재 표시된 자산의 목표 비율만 고려
      int totalSelected = 0;
      for (int i = 0; i < displayAssetCount; i++) {
        totalSelected += allAssetTargetRatios[i];
      }
      
      // 드롭다운에 표시할 수 있는 값 제한
      for (int i = 0; i < displayAssetCount; i++) {
        int currentValue = allAssetTargetRatios[i];
        int otherTotal = totalSelected - currentValue;
        int maxPossible = 100 - otherTotal;
        
        if (currentValue > maxPossible) {
          allAssetTargetRatios[i] = maxPossible;
        }
      }
    });
    saveState();
  }
  
  void clearCashValue() {
    setState(() {
      cashController.clear();
      updateTotalAmount();
    });
    saveState();
  }
  
  void clearAssetName(int index) {
    setState(() {
      allAssetNameControllers[index].clear();
    });
    saveState();
  }
  
  void clearAssetValue(int index) {
    setState(() {
      allAssetValueControllers[index].clear();
      updateTotalAmount();
    });
    saveState();
  }
  
  void calculateRebalancing() {
    if (totalAmount <= 0) {
      setState(() {
        adjustmentResults = [];
        finalResults = {};
        showResults = true;
      });
      return;
    }
    
    int totalSelectedRatio = 0;
    Map<String, double> currentAllocations = {};
    Map<String, int> targetAllocations = {};
    
    bool hasInput = cashController.text.isNotEmpty;
    
    // 현재 표시된 자산만 계산에 포함
    for (int i = 0; i < displayAssetCount; i++) {
      String assetName = allAssetNameControllers[i].text.trim();
      String assetValueText = allAssetValueControllers[i].text.replaceAll(',', '');
      int assetRatio = allAssetTargetRatios[i];
      
      if (assetName.isNotEmpty || assetValueText.isNotEmpty || assetRatio > 0) {
        hasInput = true;
      }
      
      if (assetName.isEmpty && assetValueText.isEmpty && assetRatio == 0) continue;
      
      String name = assetName.isEmpty ? '자산${i+1}' : assetName;
      double value = double.tryParse(assetValueText) ?? 0;
      
      totalSelectedRatio += assetRatio;
      currentAllocations[name] = value;
      targetAllocations[name] = assetRatio;
    }
    
    List<Map<String, dynamic>> results = [];
    Map<String, Map<String, dynamic>> finals = {};
    bool hasAdjustment = false;
    
    if (!hasInput) {
      setState(() {
        adjustmentResults = [];
        finalResults = {};
        showResults = true;
      });
      return;
    }
    
    if (totalSelectedRatio > 100) {
      setState(() {
        adjustmentResults = [{'text': '총 비중이 100%를 초과할 수 없습니다.', 'color': Colors.red}];
        finalResults = {};
        showResults = true;
      });
      return;
    }
    
    targetAllocations.forEach((asset, targetRatio) {
      final targetValue = (totalAmount * targetRatio) / 100;
      final currentValue = currentAllocations[asset] ?? 0;
      Map<String, dynamic> result = {};
      
      if (currentValue > targetValue) {
        result = {
          'text': '$asset : ${formatCurrency(currentValue - targetValue)}원 만큼 파세요(매도)',
          'color': const Color(0xFF0D6EFD), // 파란색 (매도)
          'asset': asset
        };
        hasAdjustment = true;
      } else if (currentValue < targetValue) {
        result = {
          'text': '$asset : ${formatCurrency(targetValue - currentValue)}원 만큼 사세요(매수)',
          'color': const Color(0xFFDC3545), // 빨간색 (매수)
          'asset': asset
        };
        hasAdjustment = true;
      } else {
        result = {
          'text': '$asset: 리밸런싱 필요 없음',
          'color': const Color(0xFF198754), // 녹색
          'asset': asset
        };
      }
      
      results.add(result);
      
      // 리밸런싱 후 현황 계산
      final finalAssetValue = (totalAmount * targetRatio) / 100;
      finals[asset] = {
        'value': finalAssetValue,
        'ratio': targetRatio
      };
    });
    
    if (!hasAdjustment) {
      setState(() {
        adjustmentResults = [{'text': '리밸런싱이 필요하지 않습니다.', 'color': const Color(0xFF198754)}];
        finalResults = {};
        showResults = true;
      });
      return;
    }
    
    // 현금 최종 결과 추가
    final cashRatio = 100 - totalSelectedRatio;
    final finalCash = (totalAmount * cashRatio) / 100;
    finals['보유 KRW'] = {
      'value': finalCash,
      'ratio': cashRatio
    };
    
    setState(() {
      adjustmentResults = results;
      finalResults = finals;
      showResults = true;
    });
  }
  
  void resetAll() {
    setState(() {
      cashController.clear();
      
      // 모든 자산 컨트롤러 초기화
      for (var controller in allAssetNameControllers) {
        controller.clear();
      }
      for (var controller in allAssetValueControllers) {
        controller.clear();
      }
      
      // 목표 비율 초기화
      allAssetTargetRatios = List.filled(maxAssetCount, 0);
      
      // 결과 초기화
      adjustmentResults = [];
      finalResults = {};
      showResults = false;
      totalAmount = 0;
    });
    
    // 상태 저장 (초기화된 상태가 저장됨)
    saveState();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.width < 600;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Container(
              constraints: const BoxConstraints(maxWidth: 510),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1), 
                    blurRadius: 8, 
                    offset: const Offset(0, 4)
                  ),
                ],
              ),
              padding: EdgeInsets.all(isSmallScreen ? 10 : 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 타이틀
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16.0),
                    child: Text(
                      '리밸런싱 계산기',
                      style: TextStyle(
                        fontSize: 24, 
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  
                  // 자산 개수 선택
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 15.0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('자산 개수 선택:'),
                          const SizedBox(width: 8),
                          DropdownButton<int>(
                            value: displayAssetCount,
                            items: List.generate(5, (i) => i + 1)
                                .map((i) => DropdownMenuItem<int>(
                                      value: i,
                                      child: Text('$i'),
                                    ))
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                updateAssetCount(value);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // 헤더 (자산 헤더)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10.0),
                    child: Row(
                      children: [
                        _buildHeaderCell('자산명', flex: isSmallScreen ? 100 : 125),
                        _buildHeaderCell('평가 금액', flex: isSmallScreen ? 140 : 165),
                        _buildHeaderCell('현재 비중', flex: isSmallScreen ? 70 : 85),
                        _buildHeaderCell('목표 비중', flex: isSmallScreen ? 70 : 85),
                      ],
                    ),
                  ),
                  
                  // 자산 목록
                  ...List.generate(displayAssetCount, (index) {
                    double currentValue = double.tryParse(allAssetValueControllers[index].text.replaceAll(',', '')) ?? 0;
                    double currentRatio = getCurrentRatio(currentValue);
                    
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10.0),
                      child: Row(
                        children: [
                          // 자산명
                          Flexible(
                            flex: isSmallScreen ? 100 : 125,
                            child: _buildClearableTextField(
                              controller: allAssetNameControllers[index],
                              onChanged: (value) {
                                // 8글자 제한 적용
                                if (value.length > 8) {
                                  allAssetNameControllers[index].text = value.substring(0, 8);
                                  allAssetNameControllers[index].selection = TextSelection.fromPosition(
                                    TextPosition(offset: 8)
                                  );
                                } else {
                                  setState(() {
                                    // 자산 이름 목록 업데이트
                                    // 항상 5개의 자산을 유지하기 위해 추가된 부분
                                    // 이 부분은 실제 구현에 따라 다를 수 있습니다.
                                  });
                                }
                                saveState();
                              },
                              onClear: () => clearAssetName(index),
                              keyboardType: TextInputType.text,
                              maxLength: 8, // 8글자 제한 추가
                            ),
                          ),
                          const SizedBox(width: 5),
                          
                          // 평가 금액
                          Flexible(
                            flex: isSmallScreen ? 140 : 165,
                            child: _buildClearableTextField(
                              controller: allAssetValueControllers[index],
                              onChanged: (_) => formatNumberWithCommas(allAssetValueControllers[index]),
                              onClear: () => clearAssetValue(index),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 5),
                          
                          // 현재 비중
                          Flexible(
                            flex: isSmallScreen ? 70 : 85,
                            child: _buildDisabledTextField('${currentRatio.toStringAsFixed(1)}%'),
                          ),
                          const SizedBox(width: 5),
                          
                          // 목표 비중
                          Flexible(
                            flex: isSmallScreen ? 70 : 85,
                            child: Container(
                              height: 30,
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade400),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<int>(
                                  value: allAssetTargetRatios[index],
                                  isExpanded: true,
                                  alignment: Alignment.center,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black,
                                  ),
                                  icon: const Icon(Icons.arrow_drop_down, size: 16),
                                  items: List.generate(101, (i) => i)
                                      .map((i) => DropdownMenuItem<int>(
                                            value: i,
                                            alignment: Alignment.center,
                                            child: Text('$i%'),
                                          ))
                                      .toList(),
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() {
                                        allAssetTargetRatios[index] = value;
                                        updateRatios();
                                      });
                                    }
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  
                  // 현금 입력 행
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10.0),
                    child: Row(
                      children: [
                        // 자산명
                        Flexible(
                          flex: isSmallScreen ? 100 : 125,
                          child: _buildDisabledTextField('보유 KRW'),
                        ),
                        const SizedBox(width: 5),
                        
                        // 평가 금액
                        Flexible(
                          flex: isSmallScreen ? 140 : 165,
                          child: _buildClearableTextField(
                            controller: cashController,
                            onChanged: (_) => formatNumberWithCommas(cashController),
                            onClear: clearCashValue,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 5),
                        
                        // 현재 비중
                        Flexible(
                          flex: isSmallScreen ? 70 : 85,
                          child: _buildDisabledTextField(
                            '${getCurrentRatio(double.tryParse(cashController.text.replaceAll(',', '')) ?? 0).toStringAsFixed(1)}%'
                          ),
                        ),
                        const SizedBox(width: 5),
                        
                        // 목표 비중
                        Flexible(
                          flex: isSmallScreen ? 70 : 85,
                          child: _buildDisabledTextField('${getCashTargetRatio()}%'),
                        ),
                      ],
                    ),
                  ),
                  
                  // 총 금액 표시
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10.0),
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                        children: [
                          const TextSpan(text: '총 금액 : '),
                          TextSpan(text: '${formatCurrency(totalAmount)} 원'),
                        ],
                      ),
                    ),
                  ),
                  
                  // 초기화 버튼
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: resetAll,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6c757d),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(5),
                        ),
                        elevation: 0,
                      ),
                      child: const Text('초기화', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  
                  const SizedBox(height: 10),
                  
                  // 계산 버튼
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: calculateRebalancing,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF007BFF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(5),
                        ),
                        elevation: 0,
                      ),
                      child: const Text('계산', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  
                  // 결과 표시 영역
                  if (showResults) ...[
                    const SizedBox(height: 20),
                    
                    // 결과 표시
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F9FA),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (adjustmentResults.isEmpty)
                            const Center(
                              child: Text(
                                '리밸런싱이 필요하지 않습니다.',
                                style: TextStyle(
                                  color: Color(0xFF198754),
                                  fontWeight: FontWeight.bold
                                ),
                              ),
                            )
                          else
                            ...adjustmentResults.map((result) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.0),
                              child: Text(
                                result['text'],
                                style: TextStyle(
                                  color: result['color'],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )).toList(),
                          
                          if (finalResults.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10.0),
                              child: Divider(color: Colors.grey.shade300, height: 1),
                            ),
                            
                            // 리밸런싱 후 현황 제목
                            const Align(
                              alignment: Alignment.center,
                              child: Padding(
                                padding: EdgeInsets.only(bottom: 8.0),
                                child: Text(
                                  '리밸런싱 후 현황',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 17,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ),
                            
                            // 리밸런싱 후 각 자산 현황
                            ...finalResults.entries.map((entry) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.0),
                              child: Text(
                                '${entry.key} : ${formatCurrency(entry.value['value'])}원 (${entry.value['ratio']}%)',
                                style: const TextStyle(
                                  fontWeight: FontWeight.normal,
                                  color: Colors.black,
                                ),
                              ),
                            )).toList(),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildHeaderCell(String text, {required int flex}) {
    return Flexible(
      flex: flex,
      child: Container(
        height: 30,
        alignment: Alignment.center,
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
  
  Widget _buildClearableTextField({
    required TextEditingController controller,
    required Function(String) onChanged,
    required Function() onClear,
    TextInputType keyboardType = TextInputType.text,
    int? maxLength,
  }) {
    return Container(
      height: 30,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Stack(
        alignment: Alignment.centerRight,
        children: [
          TextField(
            controller: controller,
            style: const TextStyle(fontSize: 12),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.only(left: 8, right: 24, top: 8, bottom: 8),
              border: InputBorder.none,
              isDense: true,
            ),
            keyboardType: keyboardType,
            onChanged: onChanged,
            maxLength: maxLength,
            buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
          ),
          Material(
            color: Colors.transparent,
            child: SizedBox(
              width: 24,
              height: 30,
              child: InkWell(
                borderRadius: BorderRadius.circular(15),
                child: const Icon(Icons.clear, size: 16, color: Colors.grey),
                onTap: onClear,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDisabledTextField(String text) {
    return Container(
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(5),
        color: const Color(0xFFF8F9FA),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12),
        textAlign: TextAlign.center,
      ),
    );
  }
}