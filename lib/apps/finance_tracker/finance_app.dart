import 'package:flutter/material.dart';

import '../../suite/sub_app.dart';
import 'ui/home/finance_home_page.dart';

const financeSubApp = SubApp(
  id: 'finance',
  title: 'Finanzen',
  icon: Icons.account_balance_wallet,
  accent: Colors.red,
  builder: _build,
);

Widget _build(BuildContext context) => const FinanceHomePage();
