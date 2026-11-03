#!/usr/bin/env bash
# Validação estática do resource aero_pilot (executa fora do FiveM).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
FAILED=0

echo "===== 1/4 Sintaxe Lua (luaparse) ====="
if ! node -e "require('/tmp/aero_luavalid/node_modules/luaparse')" >/dev/null 2>&1; then
    echo "Instalando luaparse (somente para validação, fora do resource)..."
    npm install --prefix /tmp/aero_luavalid --no-audit --no-fund luaparse@0.3.1 >/dev/null 2>&1
fi
LUAPARSE_PATH=/tmp/aero_luavalid/node_modules/luaparse node tests/lua_syntax_check.js || FAILED=1

echo "===== 2/4 Sintaxe JavaScript ====="
for f in html/script.js html/missions.js tests/lua_syntax_check.js; do
    if node --check "$f" >/dev/null 2>&1; then echo " [OK]   $f"; else echo " [FALHA] $f"; FAILED=1; fi
done

echo "===== 3/4 Referências NUI / JSON / manifest ====="
python3 tests/check_refs.py || FAILED=1

echo "===== 4/4 Auto-teste lógico (somente no servidor FiveM) ====="
echo " [INFO] Rode no console do servidor: aero_missions_selftest"
echo " [INFO] Cenários in-game: tests/TESTES.md"

if [ "$FAILED" -eq 0 ]; then
    echo "===== VALIDAÇÃO ESTÁTICA: OK ====="
else
    echo "===== VALIDAÇÃO ESTÁTICA: FALHAS ENCONTRADAS ====="
fi
exit "$FAILED"
