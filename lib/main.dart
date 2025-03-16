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
      title: '리밸런싱 계산기',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF007BFF),
          primary: const Color(0xFF007BFF),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.grey.shade50,
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: const Color(0xFF007BFF),
          ),
        ),
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
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.width < 600;

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
  
  int assetCount = 1;
  List<String> assetNames = [''];
  List<TextEditingController> assetNameControllers = [TextEditingController()];
  List<TextEditingController> assetValueControllers = [TextEditingController()];
  List<int> assetTargetRatios = [0];
  
  double totalAmount = 0;
  List<Map<String, dynamic>> adjustmentResults = [];
  Map<String, Map<String, dynamic>> finalResults = {};
  bool showResults = false;
  
  @override
  void initState() {
    super.initState();
    loadState();
  }
  
  @override
  void dispose() {
    cashController.dispose();
    for (var controller in assetValueControllers) {
      controller.dispose();
    }
    for (var controller in assetNameControllers) {
      controller.dispose();
    }
    super.dispose();
  }
  
  // 앱 상태 저장
  Future<void> saveState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 모든 자산명, 값, 비율 수집 (현재 설정된 개수에 상관없이)
      final allAssetNames = assetNameControllers.map((c) => c.text).toList();
      final allAssetValues = assetValueControllers.map((c) => c.text).toList();
      final allAssetRatios = assetTargetRatios;
      
      final state = {
        'cash_value': cashController.text,
        'asset_count': assetCount,
        'asset_names': allAssetNames,
        'asset_values': allAssetValues,
        'asset_ratios': allAssetRatios,
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
          assetCount = state['asset_count'] ?? 1;
          
          // 리스트 데이터 로드
          final loadedNames = List<String>.from(state['asset_names'] ?? []);
          final loadedValues = List<String>.from(state['asset_values'] ?? []);
          final loadedRatios = List<int>.from(state['asset_ratios'] ?? []);
          
          // 데이터 적용
          assetNames = loadedNames.isEmpty ? List.filled(assetCount, '') : loadedNames;
          
          // 컨트롤러 재설정
          for (var controller in assetNameControllers) {
            controller.dispose();
          }
          for (var controller in assetValueControllers) {
            controller.dispose();
          }
          
          assetNameControllers = List.generate(
            assetCount, 
            (i) => TextEditingController(
              text: i < loadedNames.length ? loadedNames[i] : ''
            )
          );
          
          assetValueControllers = List.generate(
            assetCount, 
            (i) => TextEditingController(
              text: i < loadedValues.length ? loadedValues[i] : ''
            )
          );
          
          assetTargetRatios = loadedRatios.isEmpty ? 
            List.filled(assetCount, 0) : 
            (loadedRatios.length >= assetCount ? 
              loadedRatios.sublist(0, assetCount) : 
              [...loadedRatios, ...List.filled(assetCount - loadedRatios.length, 0)]);
        });
        
        updateTotalAmount();
      }
    } catch (e) {
      debugPrint('상태 로드 오류: $e');
    }
  }
  
  void updateAssetCount(int count) {
    setState(() {
      // 기존 값 임시 저장
      List<String> tempNames = List.from(assetNames);
      List<String> tempValues = assetValueControllers.map((c) => c.text).toList();
      List<int> tempRatios = List.from(assetTargetRatios);
      
      // 컨트롤러 정리
      for (var controller in assetNameControllers) {
        controller.dispose();
      }
      for (var controller in assetValueControllers) {
        controller.dispose();
      }
      
      // 새 값 설정
      assetCount = count;
      
      // 리스트 크기 조정하면서 기존 값 유지
      assetNames = List.generate(count, (i) => i < tempNames.length ? tempNames[i] : '');
      
      assetNameControllers = List.generate(count, 
        (i) => TextEditingController(text: i < tempNames.length ? tempNames[i] : '')
      );
      
      assetValueControllers = List.generate(count, 
        (i) => TextEditingController(text: i < tempValues.length ? tempValues[i] : '')
      );
      
      assetTargetRatios = List.generate(count, 
        (i) => i < tempRatios.length ? tempRatios[i] : 0
      );
      
      updateTotalAmount();
      saveState();
    });
  }
  
  void updateTotalAmount() {
    double cash = double.tryParse(cashController.text.replaceAll(',', '')) ?? 0;
    double assetsSum = 0;
    
    for (var controller in assetValueControllers) {
      assetsSum += double.tryParse(controller.text.replaceAll(',', '')) ?? 0;
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
    int sum = assetTargetRatios.fold(0, (sum, ratio) => sum + ratio);
    return max(0, 100 - sum);
  }
  
  void updateRatios() {
    setState(() {
      int totalSelected = assetTargetRatios.fold(0, (sum, ratio) => sum + ratio);
      
      // 드롭다운에 표시할 수 있는 값 제한
      for (int i = 0; i < assetCount; i++) {
        int currentValue = assetTargetRatios[i];
        int otherTotal = totalSelected - currentValue;
        int maxPossible = 100 - otherTotal;
        
        if (currentValue > maxPossible) {
          assetTargetRatios[i] = maxPossible;
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
      assetNameControllers[index].clear();
      assetNames[index] = '';
    });
    saveState();
  }
  
  void clearAssetValue(int index) {
    setState(() {
      assetValueControllers[index].clear();
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
    
    for (int i = 0; i < assetCount; i++) {
      String assetName = assetNameControllers[i].text.trim();
      String assetValueText = assetValueControllers[i].text.replaceAll(',', '');
      int assetRatio = assetTargetRatios[i];
      
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
          'color': const Color(0xFF0D6EFD),
          'asset': asset
        };
        hasAdjustment = true;
      } else if (currentValue < targetValue) {
        result = {
          'text': '$asset : ${formatCurrency(targetValue - currentValue)}원 만큼 사세요(매수)',
          'color': const Color(0xFFDC3545),
          'asset': asset
        };
        hasAdjustment = true;
      } else {
        result = {
          'text': '$asset: 리밸런싱 필요 없음',
          'color': const Color(0xFF198754),
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
      for (var controller in assetValueControllers) {
        controller.clear();
      }
      for (var controller in assetNameControllers) {
        controller.clear();
      }
      assetNames = List.filled(assetCount, '');
      assetTargetRatios = List.filled(assetCount, 0);
      adjustmentResults = [];
      finalResults = {};
      showResults = false;
      updateTotalAmount();
    });
    saveState();
  }
  
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size; // 변수 복원
    final isSmallScreen = size.width < 600; // 변수 복원
    
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: SingleChildScrollView(
        child: Column(
          children: [
            // 제목 추가
            const Padding(
              padding: EdgeInsets.only(top: 16.0, bottom: 16.0),
              child: Text(
                '리밸런싱 계산기',
                style: TextStyle(
                  fontSize: 24, 
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF007BFF),
                ),
              ),
            ),
            Center(
              child: Container(
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
                              value: assetCount,
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
                    
                    // 헤더
                    Row(
                      children: [
                        _buildHeaderCell('자산명', flex: isSmallScreen ? 100 : 125),
                        _buildHeaderCell('평가 금액', flex: isSmallScreen ? 140 : 165),
                        _buildHeaderCell('현재 비중', flex: isSmallScreen ? 70 : 85),
                        _buildHeaderCell('목표 비중', flex: isSmallScreen ? 70 : 85),
                      ],
                    ),
                    
                    // 자산 목록
                    ...List.generate(assetCount, (index) {
                      double currentValue = double.tryParse(assetValueControllers[index].text.replaceAll(',', '')) ?? 0;
                      double currentRatio = getCurrentRatio(currentValue);
                      
                      return Padding(
                        padding: const EdgeInsets.only(top: 10.0),
                        child: Row(
                          children: [
                            // 자산명
                            Flexible(
                              flex: isSmallScreen ? 100 : 125,
                              child: _buildClearableTextField(
                                controller: assetNameControllers[index],
                                onChanged: (value) {
                                  setState(() {
                                    assetNames[index] = value;
                                  });
                                  saveState();
                                },
                                onClear: () => clearAssetName(index),
                                keyboardType: TextInputType.text,
                              ),
                            ),
                            const SizedBox(width: 5),
                            
                            // 평가 금액
                            Flexible(
                              flex: isSmallScreen ? 140 : 165,
                              child: _buildClearableTextField(
                                controller: assetValueControllers[index],
                                onChanged: (_) => formatNumberWithCommas(assetValueControllers[index]),
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
                                    value: assetTargetRatios[index],
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
                                          assetTargetRatios[index] = value;
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
                      padding: const EdgeInsets.only(top: 10.0),
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
                    
                    // 총 금액
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10.0),
                      child: Text(
                        '총 금액 : ${formatCurrency(totalAmount)} 원',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    
                    // 버튼들
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
                      
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (adjustmentResults.isEmpty)
                              Center(
                                child: Text(
                                  '리밸런싱이 필요하지 않습니다.',
                                  style: TextStyle(
                                    color: Colors.green[700],
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
                              
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: Text(
                                    '리밸런싱 후 현황',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 17,
                                      color: Colors.grey[800],
                                    ),
                                  ),
                                ),
                              ),
                              
                              ...finalResults.entries.map((entry) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2.0),
                                child: Text(
                                  '${entry.key} : ${formatCurrency(entry.value['value'])}원 (${entry.value['ratio']}%)',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.normal,
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
        color: Colors.grey.shade100,
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12),
        textAlign: TextAlign.center,
      ),
    );
  }
}