#!/bin/bash

# ========== DEBUG / ERROR LOG ==========
set -Eeuo pipefail

log() { printf "✅ %s\n" "$*" >&2; }
warn() { printf "⚠️  %s\n" "$*" >&2; }
die() { printf "❌ %s\n" "$*" >&2; exit 1; }

on_err() {
  local exit_code=$?
  echo "========================================" >&2
  echo "❌ SCRIPT FAILED" >&2
  echo "Exit code : $exit_code" >&2
  echo "Line      : ${BASH_LINENO[0]}" >&2
  echo "Command   : ${BASH_COMMAND}" >&2
  echo "PWD       : $(pwd)" >&2
  echo "User      : $(id -un) (uid=$(id -u))" >&2
  echo "Shell     : $SHELL" >&2
  echo "========================================" >&2
  exit $exit_code
}
trap on_err ERR

# show each command (để thấy nó chết ở đâu)
set -x

# ========== PATH DETECT ==========
PREFERRED="/home/ide-dev/material-components-flutter-codelabs/mdc_100_series/lib"
BASE="$PREFERRED"

if [[ ! -d "$BASE" ]]; then
  warn "Not found preferred path: $PREFERRED"
  warn "Auto searching mdc_100_series/lib from current directory..."
  FOUND="$(find "$(pwd)" -maxdepth 8 -type d -path "*/mdc_100_series/lib" 2>/dev/null | head -n 1 || true)"
  [[ -n "${FOUND:-}" ]] || die "Cannot find folder 'mdc_100_series/lib' from $(pwd). Hãy cd vào root project rồi chạy lại."
  BASE="$FOUND"
fi

HOME_FILE="$BASE/home.dart"
LOGIN_FILE="$BASE/login.dart"

# ========== VALIDATE ==========
[[ -d "$BASE" ]] || die "BASE folder does not exist: $BASE"

# Permission check
if [[ ! -w "$BASE" ]]; then
  ls -ld "$BASE" >&2 || true
  die "No write permission on: $BASE (thử chạy: sudo bash $0)"
fi

# show target files
log "Target BASE      : $BASE"
log "Target home.dart : $HOME_FILE"
log "Target login.dart: $LOGIN_FILE"

# Backup
ts="$(date +%Y%m%d_%H%M%S)"
[[ -f "$HOME_FILE" ]] && cp -f "$HOME_FILE" "$HOME_FILE.bak.$ts"
[[ -f "$LOGIN_FILE" ]] && cp -f "$LOGIN_FILE" "$LOGIN_FILE.bak.$ts"

# ========== WRITE home.dart ==========
cat > "$HOME_FILE" <<'DART'
// Copyright 2018-present the Flutter authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'model/products_repository.dart';
import 'model/product.dart';

class HomePage extends StatelessWidget {
  const HomePage({Key? key}) : super(key: key);

  List<Card> _buildGridCards(BuildContext context) {
    final List<Product> products =
        ProductsRepository.loadProducts(Category.all);

    if (products.isEmpty) {
      return const <Card>[];
    }

    final ThemeData theme = Theme.of(context);
    final NumberFormat formatter = NumberFormat.simpleCurrency(
      locale: Localizations.localeOf(context).toString(),
    );

    return products.map((product) {
      return Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AspectRatio(
              aspectRatio: 18 / 11,
              child: Image.asset(
                product.assetName,
                package: product.assetPackage,
                fit: BoxFit.fitWidth,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 8.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      product.name,
                      style: theme.textTheme.headline6,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8.0),
                    Text(
                      formatter.format(product.price),
                      style: theme.textTheme.subtitle2,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu, semanticLabel: 'menu'),
          onPressed: () {},
        ),
        title: const Text('SHRINE'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.search, semanticLabel: 'search'),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.tune, semanticLabel: 'filter'),
            onPressed: () {},
          ),
        ],
      ),
      body: GridView.count(
        crossAxisCount: 2,
        padding: const EdgeInsets.all(16.0),
        childAspectRatio: 8.0 / 9.0,
        children: _buildGridCards(context),
      ),
    );
  }
}
DART

# ========== WRITE login.dart ==========
cat > "$LOGIN_FILE" <<'DART'
// Copyright 2018-present the Flutter authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'package:flutter/material.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          children: <Widget>[
            const SizedBox(height: 80.0),
            Column(
              children: <Widget>[
                Image.asset('assets/diamond.png'),
                const SizedBox(height: 16.0),
                const Text('SHRINE'),
              ],
            ),
            const SizedBox(height: 120.0),

            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                filled: true,
                labelText: 'Username',
              ),
            ),
            const SizedBox(height: 12.0),

            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                filled: true,
                labelText: 'Password',
              ),
              obscureText: true,
            ),
            const SizedBox(height: 12.0),

            OverflowBar(
              alignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  child: const Text('CANCEL'),
                  onPressed: () {
                    _usernameController.clear();
                    _passwordController.clear();
                  },
                ),
                ElevatedButton(
                  child: const Text('NEXT'),
                  onPressed: () {
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
DART

# ========== VERIFY ==========
[[ -s "$HOME_FILE" ]] || die "home.dart written but empty: $HOME_FILE"
[[ -s "$LOGIN_FILE" ]] || die "login.dart written but empty: $LOGIN_FILE"

log "Done. Backups (if existed):"
log "  $HOME_FILE.bak.$ts"
log "  $LOGIN_FILE.bak.$ts"

# turn off xtrace
set +x
echo "🎉 SUCCESS"