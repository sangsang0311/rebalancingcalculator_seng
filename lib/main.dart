import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:math';

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
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(
          widget.title,
          style: TextStyle(fontSize: isSmallScreen ? 18 : 24),
        ),
        actions: [
          if (isWebViewEnabled)
            IconButton(
              icon: const Icon(Icons.flutter_dash),
              onPressed: () {
                setState(() {
                  isWebViewEnabled = false;
                });
              },
              tooltip: 'Flutter UI로 전환',
            )
          else
            IconButton(
              icon: const Icon(Icons.web),
              onPressed: () {
                if (!kIsWeb) {
                  setState(() {
                    isWebViewEnabled = true;
                  });
                }
              },
              tooltip: kIsWeb ? '웹에서는 WebView를 사용할 수 없습니다' : 'WebView로 전환',
            ),
        ],
      ),
      body: SafeArea(
        child: isWebViewEnabled
            ? WebViewWidget(controller: controller!)
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
  String adjustmentText = '';
  bool showResults = false;
  
  @override
  void initState() {
    super.initState();
    updateTotalAmount();
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
  
  void updateAssetCount(int count) {
    setState(() {
      assetCount = count;
      
      // 리스트 크기 조정
      if (assetNames.length < count) {
        assetNames.addAll(List.filled(count - assetNames.length, ''));
      } else {
        assetNames = assetNames.sublist(0, count);
      }
      
      if (assetNameControllers.length < count) {
        assetNameControllers.addAll(
          List.generate(count - assetNameControllers.length, (_) {
            final controller = TextEditingController();
            return controller;
          })
        );
      } else {
        for (int i = count; i < assetNameControllers.length; i++) {
          assetNameControllers[i].dispose();
        }
        assetNameControllers = assetNameControllers.sublist(0, count);
      }
      
      if (assetValueControllers.length < count) {
        assetValueControllers.addAll(
          List.generate(count - assetValueControllers.length, (_) => TextEditingController())
        );
      } else {
        for (int i = count; i < assetValueControllers.length; i++) {
          assetValueControllers[i].dispose();
        }
        assetValueControllers = assetValueControllers.sublist(0, count);
      }
      
      // 각 컨트롤러의 텍스트 값 설정
      for (int i = 0; i < count; i++) {
        if (i < assetNames.length && assetNames[i].isNotEmpty) {
          assetNameControllers[i].text = assetNames[i];
        }
      }
      
      if (assetTargetRatios.length < count) {
        assetTargetRatios.addAll(List.filled(count - assetTargetRatios.length, 0));
      } else {
        assetTargetRatios = assetTargetRatios.sublist(0, count);
      }
      
      updateTotalAmount();
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
    });
  }
  
  String formatCurrency(double value) {
    return currencyFormatter.format(value);
  }
  
  void formatNumberWithCommas(TextEditingController controller) {
    String value = controller.text.replaceAll(',', '');
    double? number = double.tryParse(value);
    if (number != null) {
      controller.text = formatCurrency(number);
      controller.selection = TextSelection.fromPosition(
        TextPosition(offset: controller.text.length)
      );
    }
    updateTotalAmount();
  }
  
  double getCurrentRatio(double value) {
    if (totalAmount == 0) return 0;
    return (value / totalAmount) * 100;
  }
  
  int getCashTargetRatio() {
    int sum = assetTargetRatios.fold(0, (sum, ratio) => sum + ratio);
    return max(0, 100 - sum);
  }
  
  void calculateRebalancing() {
    if (totalAmount <= 0) {
      setState(() {
        adjustmentText = '총 금액이 0원 이상이어야 합니다.';
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
    
    if (!hasInput) {
      setState(() {
        adjustmentText = '리밸런싱이 필요하지 않습니다.';
        showResults = true;
      });
      return;
    }
    
    if (totalSelectedRatio > 100) {
      setState(() {
        adjustmentText = '총 비중이 100%를 초과할 수 없습니다.';
        showResults = true;
      });
      return;
    }
    
    StringBuffer buffer = StringBuffer();
    bool hasAdjustment = false;
    
    targetAllocations.forEach((asset, targetRatio) {
      final targetValue = (totalAmount * targetRatio) / 100;
      final currentValue = currentAllocations[asset] ?? 0;
      
      if (currentValue > targetValue) {
        buffer.writeln('$asset: ${formatCurrency(currentValue - targetValue)}원 만큼 파세요(매도)');
        hasAdjustment = true;
      } else if (currentValue < targetValue) {
        buffer.writeln('$asset: ${formatCurrency(targetValue - currentValue)}원 만큼 사세요(매수)');
        hasAdjustment = true;
      } else {
        buffer.writeln('$asset: 리밸런싱 필요 없음');
      }
    });
    
    if (!hasAdjustment) {
      setState(() {
        adjustmentText = '리밸런싱이 필요하지 않습니다.';
        showResults = true;
      });
      return;
    }
    
    buffer.writeln('\n리밸런싱 후 현황');
    buffer.writeln('-------------------');
    
    targetAllocations.forEach((asset, targetRatio) {
      final finalAssetValue = (totalAmount * targetRatio) / 100;
      buffer.writeln('$asset: ${formatCurrency(finalAssetValue)}원 ($targetRatio%)');
    });
    
    final cashRatio = 100 - totalSelectedRatio;
    final finalCash = (totalAmount * cashRatio) / 100;
    buffer.writeln('보유 KRW: ${formatCurrency(finalCash)}원 ($cashRatio%)');
    
    setState(() {
      adjustmentText = buffer.toString();
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
      adjustmentText = '';
      showResults = false;
      updateTotalAmount();
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 자산 개수 선택
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('자산 개수 선택:'),
                const SizedBox(width: 10),
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
            
            const SizedBox(height: 16),
            
            // 헤더
            Row(
              children: [
                Expanded(flex: 3, child: Text('자산명', style: Theme.of(context).textTheme.titleSmall)),
                Expanded(flex: 3, child: Text('평가 금액', style: Theme.of(context).textTheme.titleSmall)),
                Expanded(flex: 2, child: Text('현재 비중', style: Theme.of(context).textTheme.titleSmall)),
                Expanded(flex: 2, child: Text('목표 비중', style: Theme.of(context).textTheme.titleSmall)),
              ],
            ),
            
            const Divider(),
            
            // 자산 목록
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: assetCount,
              itemBuilder: (context, index) {
                double currentValue = double.tryParse(assetValueControllers[index].text.replaceAll(',', '')) ?? 0;
                double currentRatio = getCurrentRatio(currentValue);
                
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    children: [
                      // 자산명
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: assetNameControllers[index],
                          decoration: const InputDecoration(
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) {
                            setState(() {
                              assetNames[index] = value;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      
                      // 평가 금액
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: assetValueControllers[index],
                          decoration: const InputDecoration(
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => formatNumberWithCommas(assetValueControllers[index]),
                        ),
                      ),
                      const SizedBox(width: 8),
                      
                      // 현재 비중
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade400),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${currentRatio.toStringAsFixed(1)}%',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      
                      // 목표 비중
                      Expanded(
                        flex: 2,
                        child: DropdownButton<int>(
                          value: assetTargetRatios[index],
                          isExpanded: true,
                          underline: Container(
                            height: 1,
                            color: Colors.grey.shade400,
                          ),
                          items: List.generate(101, (i) => i)
                              .map((i) => DropdownMenuItem<int>(
                                    value: i,
                                    child: Text('$i%'),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                assetTargetRatios[index] = value;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            
            const Divider(),
            
            // 현금 입력
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                children: [
                  // 자산명
                  Expanded(
                    flex: 3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '보유 KRW',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  
                  // 평가 금액
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: cashController,
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => formatNumberWithCommas(cashController),
                    ),
                  ),
                  const SizedBox(width: 8),
                  
                  // 현재 비중
                  Expanded(
                    flex: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${getCurrentRatio(double.tryParse(cashController.text.replaceAll(',', '')) ?? 0).toStringAsFixed(1)}%',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  
                  // 목표 비중
                  Expanded(
                    flex: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${getCashTargetRatio()}%',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 총 금액
            Text(
              '총 금액: ${formatCurrency(totalAmount)} 원',
              style: const TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 16),
            
            // 버튼
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: resetAll,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.shade600,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('초기화'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: calculateRebalancing,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('계산'),
                  ),
                ),
              ],
            ),
            
            // 결과
            if (showResults) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  adjustmentText,
                  style: const TextStyle(height: 1.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}