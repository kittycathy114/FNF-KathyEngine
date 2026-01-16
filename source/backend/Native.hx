package backend;

import lime.app.Application;
import lime.system.Display;
import lime.system.System;

import flixel.util.FlxColor;

#if (cpp && windows)
@:buildXml('
<target id="haxe">
	<lib name="dwmapi.lib" if="windows"/>
	<lib name="gdi32.lib" if="windows"/>
</target>
')
@:cppFileCode('
#include <windows.h>
#include <dwmapi.h>
#include <winuser.h>
#include <wingdi.h>

#define attributeDarkMode 20
#define attributeDarkModeFallback 19

#define attributeCaptionColor 34
#define attributeTextColor 35
#define attributeBorderColor 36

struct HandleData {
	DWORD pid = 0;
	HWND handle = 0;
};

BOOL CALLBACK findByPID(HWND handle, LPARAM lParam) {
	DWORD targetPID = ((HandleData*)lParam)->pid;
	DWORD curPID = 0;

	GetWindowThreadProcessId(handle, &curPID);
	if (targetPID != curPID || GetWindow(handle, GW_OWNER) != (HWND)0 || !IsWindowVisible(handle)) {
		return TRUE;
	}

	((HandleData*)lParam)->handle = handle;
	return FALSE;
}

HWND curHandle = 0;
WNDPROC originalWndProc = NULL;
bool isClosingRequested = false;
bool isCallbackInitialized = false;

LRESULT CALLBACK CustomWndProc(HWND hWnd, UINT uMsg, WPARAM wParam, LPARAM lParam) {
	// 只在初始化完成后才拦截关闭消息
	if (isCallbackInitialized && uMsg == WM_CLOSE) {
		isClosingRequested = true;
		return 0; // 阻止默认的关闭行为
	}
	return CallWindowProc(originalWndProc, hWnd, uMsg, wParam, lParam);
}

void getHandle() {
	if (curHandle == (HWND)0) {
		HandleData data;
		data.pid = GetCurrentProcessId();
		EnumWindows(findByPID, (LPARAM)&data);
		curHandle = data.handle;
	}
}

void initCloseCallback() {
	if (isCallbackInitialized) return;

	if (curHandle == (HWND)0) {
		getHandle();
	}

	if (curHandle != (HWND)0 && originalWndProc == NULL) {
		originalWndProc = (WNDPROC)SetWindowLongPtr(curHandle, GWLP_WNDPROC, (LONG_PTR)CustomWndProc);
		if (originalWndProc != NULL) {
			isCallbackInitialized = true;
		}
	}
}

bool cpp_isClosingRequested() {
	return isClosingRequested;
}

void cpp_resetClosingRequested() {
	isClosingRequested = false;
}

void setWindowAlpha(BYTE alpha) {
	if (curHandle != (HWND)0) {
		DWORD exStyle = GetWindowLong(curHandle, GWL_EXSTYLE);
		if (!(exStyle & WS_EX_LAYERED)) {
			SetWindowLong(curHandle, GWL_EXSTYLE, exStyle | WS_EX_LAYERED);
		}
		SetLayeredWindowAttributes(curHandle, 0, alpha, LWA_ALPHA);
	}
}

bool cpp_fadeOutWindow(int durationMs) {
	if (curHandle == (HWND)0) return false;

	DWORD exStyle = GetWindowLong(curHandle, GWL_EXSTYLE);
	if (!(exStyle & WS_EX_LAYERED)) {
		SetWindowLong(curHandle, GWL_EXSTYLE, exStyle | WS_EX_LAYERED);
	}

	int steps = 20;
	int stepDuration = durationMs / steps;

	for (int i = steps; i >= 0; i--) {
		BYTE alpha = (BYTE)(255 * i / steps);
		SetLayeredWindowAttributes(curHandle, 0, alpha, LWA_ALPHA);
		Sleep(stepDuration);
	}

	return true;
}
')
#end
class Native
{
	public static function __init__():Void
	{
		registerDPIAware();
	}

	public static function registerDPIAware():Void
	{
		#if (cpp && windows)
		// DPI Scaling fix for windows 
		// this shouldn't be needed for other systems
		// Credit to YoshiCrafter29 for finding this function
		untyped __cpp__('
			SetProcessDPIAware();	
			#ifdef DPI_AWARENESS_CONTEXT
			SetProcessDpiAwarenessContext(
				#ifdef DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2
				DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2
				#else
				DPI_AWARENESS_CONTEXT_SYSTEM_AWARE
				#endif
			);
			#endif
		');
		#end
	}

	private static var fixedScaling:Bool = false;
	private static var originalWidth:Int = 0;
	private static var originalHeight:Int = 0;

	public static function fixScaling():Void
	{
		if (fixedScaling) return;
		fixedScaling = true;

		#if (cpp && windows)
		final display:Null<Display> = System.getDisplay(0);
		if (display != null)
		{
			final dpiScale:Float = display.dpi / 96;
			originalWidth = Std.int(Main.game.width * dpiScale);
			originalHeight = Std.int(Main.game.height * dpiScale);
			@:privateAccess Application.current.window.width = originalWidth;
			@:privateAccess Application.current.window.height = originalHeight;

			Application.current.window.x = Std.int((Application.current.window.display.bounds.width - Application.current.window.width) / 2);
			Application.current.window.y = Std.int((Application.current.window.display.bounds.height - Application.current.window.height) / 2);
		}

		untyped __cpp__('
			getHandle();
			if (curHandle != (HWND)0) {
				HDC curHDC = GetDC(curHandle);
				RECT curRect;
				GetClientRect(curHandle, &curRect);
				FillRect(curHDC, &curRect, (HBRUSH)GetStockObject(BLACK_BRUSH));
				ReleaseDC(curHandle, curHDC);
			}
		');
		#end
	}

	/**
	 * 修复全屏时的分辨率问题
	 * 在全屏模式下使用显示器原生分辨率，而不是游戏逻辑分辨率
	 */
	public static function fixFullscreenResolution():Void
	{
		#if (cpp && windows)
		final display:Null<Display> = System.getDisplay(0);
		if (display != null && Application.current.window != null)
		{
			if (FlxG.fullscreen)
			{
				// 全屏模式：使用显示器原生分辨率
				@:privateAccess Application.current.window.width = Std.int(display.bounds.width);
				@:privateAccess Application.current.window.height = Std.int(display.bounds.height);
			}
			else
			{
				// 窗口模式：恢复原来的尺寸
				if (originalWidth > 0 && originalHeight > 0)
				{
					@:privateAccess Application.current.window.width = originalWidth;
					@:privateAccess Application.current.window.height = originalHeight;
				}
				else
				{
					final dpiScale:Float = display.dpi / 96;
					@:privateAccess Application.current.window.width = Std.int(Main.game.width * dpiScale);
					@:privateAccess Application.current.window.height = Std.int(Main.game.height * dpiScale);
				}

				// 居中窗口
				Application.current.window.x = Std.int((display.bounds.width - Application.current.window.width) / 2);
				Application.current.window.y = Std.int((display.bounds.height - Application.current.window.height) / 2);
			}
		}
		#end
	}

	/**
	 * 设置窗口透明度（仅Windows平台）
	 * @param alpha 透明度值 (0-255，0=完全透明，255=完全不透明)
	 */
	public static function setWindowAlpha(alpha:Int):Void
	{
		#if (cpp && windows)
		untyped __cpp__('
			setWindowAlpha({0});
		', alpha);
		#end
	}

	/**
	 * 渐隐关闭窗口（仅Windows平台）
	 * @param durationMs 渐隐持续时间（毫秒），默认500ms
	 * @return 是否成功启动渐隐动画
	 */
	public static function fadeOutWindow(?durationMs:Int = 500):Bool
	{
		#if (cpp && windows)
		var result:Bool = false;
		untyped __cpp__('
			result = cpp_fadeOutWindow({0});
		', durationMs);
		return result;
		#else
		return false;
		#end
	}

	/**
	 * 设置窗口关闭回调（仅Windows平台）
	 * 拦截 WM_CLOSE 消息，阻止默认关闭行为
	 */
	public static function setCloseCallback():Void
	{
		#if (cpp && windows)
		untyped __cpp__('
			initCloseCallback();
		');
		#end
	}

	/**
	 * 检查是否有关闭请求（仅Windows平台）
	 * @return 是否有未处理的关闭请求
	 */
	public static function isClosingRequested():Bool
	{
		#if (cpp && windows)
		var result:Bool = false;
		untyped __cpp__('
			result = cpp_isClosingRequested();
		');
		return result;
		#else
		return false;
		#end
	}

	/**
	 * 重置关闭请求标志（仅Windows平台）
	 */
	public static function resetClosingRequested():Void
	{
		#if (cpp && windows)
		untyped __cpp__('
			cpp_resetClosingRequested();
		');
		#end
	}
}