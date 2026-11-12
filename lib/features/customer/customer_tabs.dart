import '../../core/base/shell_controller.dart';

/// Tab indices of the customer shell (shared by every customer screen that needs to jump to a tab).
class CustomerTabs {
  const CustomerTabs._();

  static const int home = 0;
  static const int search = 1;
  static const int orders = 2;
  static const int profile = 3;
  static const int count = 4;

  static void go(int tab) => Nav.toTab(ShellTag.customer, tab);
}
