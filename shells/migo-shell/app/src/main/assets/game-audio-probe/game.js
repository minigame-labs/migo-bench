// Audio output probe: generates a tone with WebAudio and reports what happened.
// No asset file on purpose -- this exercises the output path (JS -> engine mixer
// -> cpal/oboe -> AudioFlinger), which is the part a shared-STL question is
// actually about, without depending on a decoder or on any bundled media.
var say = function (m) { console.error("[audio-probe] " + m); };

try {
  var Ctor = (typeof AudioContext !== "undefined") ? AudioContext
           : (typeof migo !== "undefined" && migo.createWebAudioContext) ? null : null;
  var ctx = Ctor ? new Ctor() : (migo.createWebAudioContext ? migo.createWebAudioContext() : null);
  if (!ctx) { say("FAIL no AudioContext"); }
  else {
    say("ctx state=" + ctx.state + " rate=" + ctx.sampleRate);
    var osc = ctx.createOscillator();
    var gain = ctx.createGain();
    osc.type = "sine";
    osc.frequency.value = 440;
    gain.gain.value = 0.25;
    osc.connect(gain);
    gain.connect(ctx.destination);
    if (ctx.resume) { try { ctx.resume(); } catch (e) {} }
    osc.start();
    say("started 440Hz, state=" + ctx.state);
    setTimeout(function () {
      try { osc.stop(); } catch (e) {}
      say("stopped after 6s, ctx.currentTime=" + ctx.currentTime);
    }, 6000);
  }
} catch (e) {
  say("FAIL threw: " + (e && e.message ? e.message : e));
}

// Keep a frame loop so the runtime stays alive and reports readiness.
var f = 0;
var tick = function () { f++; requestAnimationFrame(tick); };
requestAnimationFrame(tick);
