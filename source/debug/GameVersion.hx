package debug;

class GameVersion {
  public static macro function getGitCommitHash():haxe.macro.Expr.ExprOf<String> {
    #if !display
    var process = new sys.io.Process('git', ['rev-parse', '--short=7', 'HEAD']); // 获取前7位哈希
    if (process.exitCode() != 0) {
      var message = process.stderr.readAll().toString();
      var pos = haxe.macro.Context.currentPos();
      haxe.macro.Context.error("Cannot execute `git rev-parse --short=7 HEAD`. " + message, pos);
    }
    
    var commitHash:String = process.stdout.readLine();
    return macro $v{commitHash};
    #else 
    var commitHash:String = "";
    return macro $v{commitHash};
    #end
  }

  public static macro function getGitCommitCount():haxe.macro.Expr.ExprOf<String> {
    #if !display
    var process = new sys.io.Process('git', ['rev-list', '--count', 'HEAD']); // 获取提交次数
    if (process.exitCode() != 0) {
      var message = process.stderr.readAll().toString();
      var pos = haxe.macro.Context.currentPos();
      haxe.macro.Context.error("Cannot execute `git rev-list --count HEAD`. " + message, pos);
    }

    var commitCount:String = process.stdout.readLine();
    return macro $v{commitCount};
    #else
    var commitCount:String = "";
    return macro $v{commitCount};
    #end
  }

  public static macro function getBuildTime():haxe.macro.Expr.ExprOf<String> {
    var now = Date.now();
    var year = now.getFullYear();
    var month = StringTools.lpad(Std.string(now.getMonth() + 1), "0", 2);
    var day = StringTools.lpad(Std.string(now.getDate()), "0", 2);
    var hours = StringTools.lpad(Std.string(now.getHours()), "0", 2);
    var minutes = StringTools.lpad(Std.string(now.getMinutes()), "0", 2);
    var buildTime = '$year-$month-$day $hours:$minutes';
    return macro $v{buildTime};
  }
}