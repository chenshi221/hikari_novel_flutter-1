import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hikari_novel_flutter/pages/welcome/controller.dart';
import 'package:hikari_novel_flutter/router/route_path.dart';
import 'package:hikari_novel_flutter/widgets/state_page.dart';
import '../../models/common/wenku8_node.dart';
import '../../widgets/wenku8_node_menu.dart';

class WelcomePage extends StatelessWidget {
  WelcomePage({super.key});

  final controller = Get.put(WelcomeController());

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LogoPage(),
            const SizedBox(height: 20),
            Text("welcome_to_use_app".tr, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text("welcome_tip".tr, style: TextStyle(fontSize: 14)),
            const SizedBox(height: 20),
            FilledButton.icon(onPressed: () => Get.toNamed(RoutePath.login), label: Text("go_to_login".tr), icon: const Icon(Icons.login)),
            const SizedBox(height: 40),
            PopupMenuButton<Wenku8Node>(
              onSelected: (Wenku8Node value) => controller.changeWenku8Node(value),
              itemBuilder: (BuildContext context) => buildWenku8NodeMenuItems(context, controller.wenku8Node.value),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lan_outlined, size: 16, color: primaryColor),
                  SizedBox(width: 8),
                  //显示当前节点，切换后立即刷新，方便确认是否切换成功
                  Obx(() => Text("${"node".tr}: ${controller.wenku8Node.value.node}", style: TextStyle(color: primaryColor))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
