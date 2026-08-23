// Device regression for the host-callback channel.
//
// Every host callback now travels HostCommand::InvokeHostHook -> the retained
// dispatcher, instead of eval'd source naming a holder content could also name.
// The failure mode of that migration is SILENCE: a call site left behind just
// stops firing. So this exercises one callback of each argument shape and says
// out loud what arrived.
const L = (...a) => console.error("[cbprobe]", ...a);

// ---- 1. The hole itself: content must not reach the holder ----------------
const sym = Symbol.for("Migo.hostBridge");
const holder = globalThis[sym];
L("holder =", typeof holder);
L("holder among globalThis symbols =",
  Object.getOwnPropertySymbols(globalThis).filter((s) => s === sym).length);
let forged = "unreachable";
try {
    holder._internalOnAdEvent(JSON.stringify({ adId: 1, event: "close", isEnded: true }));
    forged = "DELIVERED";
} catch (e) { forged = "threw " + e.constructor.name; }
L("forged _internalOnAdEvent =", forged);

// ---- 2. No-argument shape: lifecycle + resize ------------------------------
let shows = 0, hides = 0, resizes = 0;
wx.onShow(() => { shows++; L("SHAPE-none onShow n =", shows); paint(); });
wx.onHide(() => { hides++; L("SHAPE-none onHide n =", hides); });
wx.onWindowResize && wx.onWindowResize(() => { resizes++; L("SHAPE-none onWindowResize n =", resizes); });

// ---- 3. Numeric shape: modal + action sheet --------------------------------
// `_internalOnModalResult(confirm, cancel)` is the only two-argument hook.
setTimeout(() => {
    wx.showModal({
        title: "cbprobe", content: "tap either button",
        success: (r) => L("SHAPE-numeric showModal ->", JSON.stringify(r)),
        fail: (r) => L("SHAPE-numeric showModal FAIL ->", JSON.stringify(r)),
    });
}, 2500);
setTimeout(() => {
    wx.showActionSheet({
        itemList: ["one", "two"],
        success: (r) => L("SHAPE-numeric actionSheet ->", JSON.stringify(r)),
        fail: (r) => L("SHAPE-numeric actionSheet FAIL ->", JSON.stringify(r)),
    });
}, 6000);

// ---- 4. JSON-string shape: the 20 jni_json_callback! macros -----------------
// All of them share `forward_json_result_to_js`. A *failing* login still
// travels that exact path, so no account is needed to prove the channel works
// -- what is being tested is delivery, not the result.
setTimeout(() => {
    wx.login({
        success: (r) => L("SHAPE-json login success ->", JSON.stringify(r)),
        fail: (r) => L("SHAPE-json login fail ->", JSON.stringify(r)),
        complete: () => L("SHAPE-json login COMPLETE (channel delivered)"),
    });
}, 9000);

// ---- Something on screen so a dead runtime is visible ----------------------
const canvas = wx.createCanvas();
const ctx = canvas.getContext("2d");
let frame = 0;
function paint() {
    ctx.fillStyle = shows > 1 ? "#1f7a3d" : "#20304f";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = "#ffffff";
    ctx.font = "28px sans-serif";
    ctx.fillText("cbprobe", 30, 80);
    ctx.fillText("show=" + shows + " hide=" + hides + " resize=" + resizes, 30, 130);
    ctx.fillText("holder=" + typeof holder, 30, 180);
    ctx.fillText("forged=" + forged, 30, 230);
}
function loop() { frame++; paint(); requestAnimationFrame(loop); }
loop();
L("ready");
