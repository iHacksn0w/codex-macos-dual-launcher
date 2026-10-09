ObjC.import("Foundation");
var app = Application.currentApplication();
app.includeStandardAdditions = true;
function q(s) { return "'" + s.split("'").join("'\"'\"'") + "'"; }
function run() {
  var home = ObjC.unwrap($.NSHomeDirectory());
  var root = home + "/.codex-switcher";
  try {
    var out = app.doShellScript("/bin/zsh " + q(root + "/scripts/applet-dispatch.command") + " " + q("go") + " " + q(root));
    if (out === "CODEX_SWITCHER_SELFTEST_OK") return;
    app.displayDialog(out || "Codex GO 切换脚本已结束。", {buttons:["好"], defaultButton:"好"});
  } catch (e) {
    app.displayDialog("Codex GO 启动失败：" + e, {buttons:["好"], defaultButton:"好"});
  }
}
