/* Validador de sintaxe Lua para o resource (sem runtime FiveM).
   FiveM aceita literais de hash com backticks (`lazer`); eles são
   normalizados para strings antes do parse, apenas para validação. */
const fs = require('fs');
const path = require('path');
const luaparse = require(process.env.LUAPARSE_PATH || 'luaparse');

const root = path.resolve(__dirname, '..');
const files = [];
function walk(dir) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        if (['node_modules', '.git'].includes(entry.name)) continue;
        const p = path.join(dir, entry.name);
        if (entry.isDirectory()) walk(p);
        else if (entry.name.endsWith('.lua')) files.push(p);
    }
}
walk(root);
files.sort();

let failed = 0;
for (const file of files) {
    let src = fs.readFileSync(file, 'utf8');
    // normaliza compile-time hash literals do Cfx
    src = src.replace(/`([A-Za-z0-9_]+)`/g, (_, name) => `("__HASH__${name}")`);
    try {
        luaparse.parse(src, { luaVersion: '5.3', comments: false, locations: true });
        console.log(' [OK]   ' + path.relative(root, file));
    } catch (err) {
        failed++;
        console.log(' [FALHA] ' + path.relative(root, file) + ' :: ' + err.message);
    }
}
console.log(` LUA: ${files.length - failed} OK / ${failed} FALHAS / ${files.length} arquivos`);
process.exit(failed === 0 ? 0 : 1);
