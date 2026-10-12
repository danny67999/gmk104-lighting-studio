using System;
using System.Collections.Generic;
namespace Gmk104LightingStudio {
 internal static class LogicalMatrixRaster {
  internal static readonly Dictionary<string,byte> Assignments = new Dictionary<string,byte> {{"Escape",0},{"Backquote",32},{"Digit1",32},{"Tab",64},{"CapsLock",96},{"ShiftLeft",128},{"ControlLeft",160},{"F1",1},{"Digit2",33},{"KeyQ",65},{"KeyA",97},{"KeyZ",129},{"AltLeft",161},{"MetaLeft",161},{"F2",2},{"Digit3",34},{"KeyW",66},{"KeyS",98},{"KeyX",130},{"Space",162},{"F3",3},{"Digit4",35},{"KeyE",67},{"KeyD",99},{"KeyC",131},{"F4",4},{"Digit5",36},{"KeyR",68},{"KeyF",100},{"KeyV",132},{"F5",5},{"Digit6",37},{"KeyT",69},{"KeyG",101},{"KeyB",133},{"F6",6},{"Digit7",38},{"KeyY",70},{"KeyH",102},{"KeyN",134},{"F7",7},{"Digit8",39},{"KeyU",71},{"KeyJ",103},{"KeyM",135},{"F8",8},{"Digit9",40},{"KeyI",72},{"KeyK",104},{"Comma",136},{"F9",9},{"Digit0",41},{"KeyO",73},{"KeyL",105},{"Period",137},{"F10",10},{"Minus",42},{"KeyP",74},{"Semicolon",106},{"Slash",138},{"AltRight",170},{"F11",11},{"Equal",43},{"BracketLeft",75},{"Quote",107},{"ShiftRight",139},{"MetaRight",171},{"F12",12},{"Backspace",44},{"BracketRight",76},{"Enter",108},{"ContextMenu",172},{"Backslash",77},{"ControlRight",173},{"PrintScreen",14},{"Insert",46},{"Delete",78},{"ArrowLeft",174},{"ScrollLock",15},{"Home",47},{"End",79},{"ArrowUp",143},{"ArrowDown",175},{"Pause",16},{"PageUp",48},{"PageDown",80},{"ArrowRight",176},{"NumLock",49},{"Numpad7",81},{"Numpad4",113},{"Numpad1",145},{"Numpad0",177},{"NumpadDivide",50},{"Numpad8",82},{"Numpad5",114},{"Numpad2",146},{"NumpadMultiply",51},{"Numpad9",83},{"Numpad6",115},{"Numpad3",147},{"NumpadDecimal",179},{"NumpadSubtract",52},{"NumpadAdd",116},{"NumpadEnter",180}};
  internal static RGB Automatic(string keyID,double time,LightingSettings settings) {
   byte packed;if(!Assignments.TryGetValue(keyID,out packed)||(packed&31)%2!=0)return RGB.Black;
   return MatrixRainRaster.Pixel((packed&31)*2,(packed>>5)*2,0,10,time,settings);
  }
  private static uint Milliseconds(double time) {if(Double.IsNaN(time)||Double.IsInfinity(time))return 0;double ms=Math.Floor((time%(4294967296.0/1000))*1000);if(ms<0)ms+=4294967296.0;return (uint)ms;}
  private static int Mul(int a,int b){return (a*b+127)/255;}
  internal static RGB Reactive(string keyID,double time,List<KeyPulse> pulses,LightingSettings settings) {
   byte packed;if(!Assignments.TryGetValue(keyID,out packed))return RGB.Black;
   int column=packed&31,row=packed>>5,speed=(int)Math.Round(settings.speed*256,MidpointRounding.AwayFromZero),intensity=(int)Math.Round(settings.intensity*255,MidpointRounding.AwayFromZero);uint now=Milliseconds(time);RGB result=RGB.Black;
   foreach(var pulse in pulses){byte origin;if(pulse==null||!Assignments.TryGetValue(pulse.keyID,out origin)||(origin&31)!=column)continue;uint elapsed=unchecked(now-Milliseconds(pulse.time));if(elapsed>=18000)continue;int age=(int)elapsed*speed/1000;if(age>=1152)continue;int distance=age*1280/9-row*65536/6;if(distance<0||distance>=49152)continue;
    int white=0,glow;if(distance<8192){white=255-distance*255/8192;glow=255-distance*32/8192;}else glow=220*(49152-distance)/40960;
    int coverage=Mul(glow,intensity);result=new RGB((byte)Math.Max(result.r,Mul(settings.color.r+Mul(255-settings.color.r,white),coverage)),(byte)Math.Max(result.g,Mul(settings.color.g+Mul(255-settings.color.g,white),coverage)),(byte)Math.Max(result.b,Mul(settings.color.b+Mul(255-settings.color.b,white),coverage)));
   }return result;
  }
 }
}
