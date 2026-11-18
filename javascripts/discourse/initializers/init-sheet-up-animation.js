// The hamburger sheet must expand upward from the bottom of the screen, but
// core animates the mobile slide-in panels with hard-coded horizontal
// translate3d through the Web Animations API — which outranks CSS
// animations, so the panel visibly slid in from the left no matter what the
// CSS said.
//
// Core drives these panels with SINGLE-FRAME animate() calls that lean on
// the spec's implicit "from" (the element's current transform under
// fill:forwards): one call parks the panel off-screen, one call sends it to
// its resting spot, and close reuses the same park call. So the only safe
// intervention is to swap the transform VALUE inside that single frame for
// its vertical equivalent — the implicit-from machinery then produces the
// right motion by itself: park below → rise to rest on open, sink back
// below on close. Rewriting the whole keyframe list (an earlier attempt)
// turned every close into a bogus second open — the sheet popped up again
// before being removed.
//
// The hamburger sheet parks below (translateY(100%)); the top-anchored user
// menu parks above (translateY(-100%)). Multi-frame calls (none today) and
// every other animate() call pass through untouched.
export default {
  name: "f-nav-sheet-up-animation",
  initialize() {
    const origAnimate = Element.prototype.animate;
    if (!origAnimate) {
      return;
    }
    Element.prototype.animate = function (keyframes, options) {
      try {
        const cl = this.classList;
        if (
          cl &&
          cl.contains("menu-panel") &&
          cl.contains("slide-in") &&
          Array.isArray(keyframes) &&
          keyframes.length === 1 &&
          keyframes[0] &&
          typeof keyframes[0].transform === "string"
        ) {
          const park = this.closest(".hamburger-panel")
            ? "translateY(100%)"
            : "translateY(-100%)";
          const tf = keyframes[0].transform.replace(/\s+/g, " ");
          const resting =
            tf.includes("translate3d(0") ||
            tf.includes("none") ||
            /^matrix\(1, 0, 0, 1, 0, 0\)$/.test(tf);
          return origAnimate.call(
            this,
            [{ transform: resting ? "translateY(0)" : park }],
            options
          );
        }
      } catch (e) {
        // fall through to the original call
      }
      return origAnimate.call(this, keyframes, options);
    };
  },
};
