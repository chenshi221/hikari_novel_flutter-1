import 'package:flutter/material.dart';

import '../models/common/wenku8_node.dart';

/// 节点选择菜单项，当前选中的节点高亮显示
List<PopupMenuItem<Wenku8Node>> buildWenku8NodeMenuItems(BuildContext context, Wenku8Node current) {
  final primaryColor = Theme.of(context).colorScheme.primary;
  return Wenku8Node.values
      .map(
        (n) => PopupMenuItem<Wenku8Node>(
          value: n,
          child: Text(
            n.node,
            style: n == current ? TextStyle(color: primaryColor, fontWeight: FontWeight.bold) : null,
          ),
        ),
      )
      .toList();
}
