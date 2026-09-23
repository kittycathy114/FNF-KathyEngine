package debug;

import openfl.Lib;
import openfl.display.FPS;
import flixel.FlxG;
import lime.app.Application;
import openfl.events.Event;
import openfl.system.System;
import openfl.text.TextField;
import openfl.text.TextFormat;
import backend.ClientPrefs;
import states.MainMenuState;

class SimpleInfoDisplay extends TextField
{
    public var infoDisplayed:Array<Bool> = [true, true, false];
	public var memPeak:Float = 0;
    public var currentFPS:Int = 0;

    var fpsCounter:FPS;

	public function new(inX:Float = 10.0, inY:Float = 10.0, inCol:Int = 0x000000)
	{
		super();

		x = inX;
		y = inY;
		selectable = false;
		
		// Leather: _sans 字体用 12px，其他字体用 14px
		defaultTextFormat = new TextFormat("_sans", 12, inCol);

		fpsCounter = new FPS(10000, 10000, inCol);
		fpsCounter.visible = false;
		Lib.current.addChild(fpsCounter);

		addEventListener(Event.ENTER_FRAME, onEnter);
		width = FlxG.width;
		height = FlxG.height;
		
		applySettings();
	}
	
	public function applySettings():Void
	{
		var colorInt:Int = (ClientPrefs.data.simpleInfoColor.red << 16) | (ClientPrefs.data.simpleInfoColor.green << 8) | ClientPrefs.data.simpleInfoColor.blue;
		
		defaultTextFormat = new TextFormat("_sans", ClientPrefs.data.simpleInfoFontSize, colorInt);
		setTextFormat(defaultTextFormat);
		infoDisplayed[0] = ClientPrefs.data.simpleInfoShowFPS;
		infoDisplayed[1] = ClientPrefs.data.simpleInfoShowMem;
		infoDisplayed[2] = ClientPrefs.data.simpleInfoShowVersion;
	}

	private function onEnter(event:Event)
	{
        currentFPS = fpsCounter.currentFPS;

        if(visible)
        {
            text = "";

            for(i in 0...infoDisplayed.length)
            {
                if(infoDisplayed[i])
                {
                    switch(i)
                    {
                        case 0:
                            text += fps_Function();
                        case 1:
                            text += memory_Function();
                        case 2:
                            text += version_Function();
                    }

                    if(i < infoDisplayed.length - 1)
                    	text += "\n";
                }
            }
        }
        else
            text = "";
	}

    function fps_Function():String
    {
        return currentFPS + " fps";
    }

    function memory_Function():String
    {
		var mem:Float = System.totalMemory / (1024 * 1024);
		
		if(mem > memPeak) memPeak = mem;

		return formatMemory(mem) + " / " + formatMemory(memPeak);
    }

    function version_Function():String
    {
        // 统一读 MainMenuState.kathyEngineVersion，带 rc/beta/alpha 后缀
        var version:String = MainMenuState.kathyEngineVersion;
        if(version == null) version = "0.0.0";
        return "v" + version;
    }
    
    function formatMemory(bytes:Float):String
    {
    	if(bytes < 1024)
    		return Math.round(bytes * 100) / 100 + "MB";
    	else
    		return Math.round((bytes / 1024) * 100) / 100 + "GB";
    }
	
	public function positionSimpleInfo(X:Float, Y:Float):Void
	{
		x = X;
		y = Y;
	}
}
