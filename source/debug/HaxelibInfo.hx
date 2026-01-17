package debug;

import haxe.macro.Context;
import haxe.macro.Expr;
import sys.io.File;
import sys.io.Process;
import sys.FileSystem;
import haxe.xml.Access;
import StringTools;
import Sys;

class HaxelibInfo {
	public static macro function getHaxelibInfo():ExprOf<String> {
		#if !display
		try {
			// 获取项目根目录（当前工作目录）
			var cwd = Sys.getCwd();
			// 移除末尾的路径分隔符（如果有）
			if (StringTools.endsWith(cwd, "/") || StringTools.endsWith(cwd, "\\")) {
				cwd = cwd.substring(0, cwd.length - 1);
			}
			var projectPath = cwd + "/Project.xml";
			if (!FileSystem.exists(projectPath)) {
				// 尝试在父目录中查找
				projectPath = cwd + "/../Project.xml";
				if (!FileSystem.exists(projectPath)) {
					Context.error("Project.xml not found in " + cwd, Context.currentPos());
				}
			}
			var xmlContent = File.getContent(projectPath);
			var xml = Xml.parse(xmlContent);
			var access = new Access(xml.firstElement());
			
			// 收集所有 haxelib 名称
			var libNames = [];
			for (el in access.nodes.haxelib) {
				var name = el.att.name;
				libNames.push(name);
			}
			
			// 执行 haxelib list 命令获取全局库版本
			var process = new Process("haxelib", ["list"]);
			var exitCode = process.exitCode();
			var output = process.stdout.readAll().toString();
			var error = process.stderr.readAll().toString();
			process.close();
			if (exitCode != 0) {
				Context.warning("haxelib list failed: " + error, Context.currentPos());
			}
			
			// 记录原始输出用于调试（只记录前500个字符）
			var debugOutput = output.length > 500 ? output.substring(0, 500) + "..." : output;
			Context.info("haxelib list output (first 500 chars):\n" + debugOutput, Context.currentPos());
			
			// 解析输出：每行格式 "libname: version"
			var libInfoMap = new Map<String, String>();
			var allLines = output.split("\n");
			
			Context.info("Parsing haxelib list output (" + allLines.length + " lines)", Context.currentPos());
			
			for (i in 0...allLines.length) {
				var rawLine = allLines[i];
				var trimmed = StringTools.trim(rawLine);
				if (trimmed.length == 0) continue;
				
				// 检查是否是缩进的行（版本列表）- 以空格或制表符开头
				if (rawLine.length > 0 && (rawLine.charCodeAt(0) == 32 || rawLine.charCodeAt(0) == 9)) {
					// 缩进行：这是前一个库的另一个版本，跳过
					continue;
				}
				
				// 新库行，格式 "libname: version"
				var colonIndex = rawLine.indexOf(":");
				if (colonIndex == -1) continue;
				
				var lib = StringTools.trim(rawLine.substring(0, colonIndex));
				var versionPart = "";
				
				// 提取版本信息：冒号后的部分
				var afterColon = rawLine.substring(colonIndex + 1);
				var firstLine = afterColon;
				
				// 如果有换行符，取第一行
				var newlineIndex = firstLine.indexOf("\n");
				if (newlineIndex != -1) {
					firstLine = firstLine.substring(0, newlineIndex);
				}
				
				firstLine = StringTools.trim(firstLine);
				// 移除可能的回车符
				firstLine = StringTools.replace(firstLine, "\r", "");
				
				if (firstLine.length > 0) {
					// 查找第一个方括号对
					var openBracket = firstLine.indexOf("[");
					var closeBracket = firstLine.indexOf("]");
					if (openBracket != -1 && closeBracket != -1 && closeBracket > openBracket) {
						// 提取括号内的内容
						var inside = firstLine.substring(openBracket + 1, closeBracket);
						// 处理特殊标记
						if (inside == "git") {
							versionPart = "git";
						} else if (StringTools.startsWith(inside, "dev:")) {
							versionPart = "dev";
						} else if (inside == "current" || inside == "当前") {
							// 版本号在括号外（方括号之前的部分）
							var beforeBracket = firstLine.substring(0, openBracket);
							versionPart = StringTools.trim(beforeBracket);
						} else {
							// 括号内就是版本号
							versionPart = inside;
						}
					} else {
						// 没有方括号，使用整个字符串作为版本号
						versionPart = firstLine;
					}
				}
				
				// 如果版本号为空，设置默认文本
				if (versionPart.length == 0) {
					versionPart = "(no version)";
				}
				
				Context.info("  Parsed: " + lib + " -> '" + versionPart + "'", Context.currentPos());
				libInfoMap.set(lib, versionPart);
			}
			
			// 调试信息：记录我们解析到了什么
			Context.info("Found " + libNames.length + " haxelibs in Project.xml", Context.currentPos());
			for (lib in libNames) {
				if (libInfoMap.exists(lib)) {
					Context.info("  " + lib + " -> " + libInfoMap.get(lib), Context.currentPos());
				} else {
					Context.info("  " + lib + " -> NOT FOUND in haxelib list", Context.currentPos());
				}
			}
			
			// 构建信息字符串
			var infoLines = [];
			for (lib in libNames) {
				if (libInfoMap.exists(lib)) {
					infoLines.push(lib + " " + libInfoMap.get(lib));
				} else {
					infoLines.push(lib + " (unknown)");
				}
			}
			
			var result = infoLines.join("\n");
			Context.info("Final haxelib info string:\n" + result, Context.currentPos());
			return macro $v{result};
		} catch (e:Dynamic) {
			Context.warning("Failed to get haxelib info: " + Std.string(e), Context.currentPos());
			return macro $v{"(haxelib info unavailable)"};
		}
		#else
		return macro $v{""};
		#end
	}
}