const fs = require('fs');
const F = 'D:/Arin/Repo/quickcenter.koplugin/main.lua';
let t = fs.readFileSync(F, 'utf8').replace(/\r\n/g, '\n');
function rep(old, next, expect) {
  const n = t.split(old).length - 1;
  if (n !== expect) { console.error('MISMATCH', expect, 'got', n, '>>>', JSON.stringify(old.slice(0, 70))); process.exit(1); }
  t = t.split(old).join(next);
}
rep('    local current_view = cfg.view or "common"\n',
    '    local current_view = cfg.view or "common"\n    local view_user_set = false -- 用户手动改过“界面”后，不再被动作类型默认值覆盖\n', 1);
rep('                showViewPickerDialog(current_view, function(v)\n                    current_view = v\n',
    '                showViewPickerDialog(current_view, function(v)\n                    current_view = v\n                    view_user_set = true\n', 1);
rep('                            current_view = "filemanager"\n',
    '                            if not view_user_set then current_view = "filemanager" end\n', 2);
rep('                                            current_view = "common"\n',
    '                                            if not view_user_set then current_view = "common" end\n', 1);
rep('                                        current_view = "common"\n',
    '                                        if not view_user_set then current_view = "common" end\n', 1);
rep('                                                    current_view = "common"\n',
    '                                                    if not view_user_set then current_view = "common" end\n', 1);
rep('                        current_view = view\n',
    '                        if not view_user_set then current_view = view end\n', 1);
fs.writeFileSync(F, t + '\n');
console.log('view override guard applied');
