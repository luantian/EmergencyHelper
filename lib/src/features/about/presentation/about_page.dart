import 'package:flutter/material.dart';
import 'package:emergency_helper/src/core/constants/app_constants.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('项目说明')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            AppConstants.appName,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text('这是一个应急辅助项目基础骨架，当前重点是建立清晰结构，方便多人协作、快速扩展。'),
          const SizedBox(height: 16),
          const Text('建议协作规范'),
          const SizedBox(height: 6),
          const Text('1. 按 feature 划分业务代码，跨模块能力放到 core/shared。'),
          const Text('2. 控制器只处理状态，不在页面中写业务逻辑。'),
          const Text('3. 每个新模块至少补一个 widget test 或单元测试。'),
        ],
      ),
    );
  }
}
