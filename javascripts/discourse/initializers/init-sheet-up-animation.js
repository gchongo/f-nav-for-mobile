// The hamburger sheet must expand upward from the bottom of the screen, but
// core animates the mobile slide-in panels with a hard-coded horizontal
// translateX through the Web Animations API — which outranks CSS animations,
// so the panel visibly slid in from the left no matter what the CSS said.
// Intercept animate() for slide-in menu panels only and hand them vertical
// keyframes instead: the hamburger sheet rises from above the f-nav bar and
// the user menu drops from the top. Every other animate() call passes
// through untouched.
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
        if (cl && cl.contains("menu-panel") && cl.contains("slide-in")) {
          const start = this.closest(".hamburger-panel")
            ? "translateY(100%)"
            : "translateY(-100%)";
          return origAnimate.call(
            this,
            [{ transform: start }, { transform: "translateY(0)" }],
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
