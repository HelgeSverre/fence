// A click hides every tooltip (see .tips-dismissed in main.css) until the
// pointer reaches a different host, so a toggled setting is not covered by
// its own explanation.
export function setupTooltips() {
  const root = document.documentElement;
  let dismissedHost = null;
  document.addEventListener("mousedown", (event) => {
    dismissedHost = event.target.closest(".tip-host");
    root.classList.add("tips-dismissed");
  }, true);
  document.addEventListener("mouseover", (event) => {
    if (root.classList.contains("tips-dismissed") && event.target.closest(".tip-host") !== dismissedHost) {
      root.classList.remove("tips-dismissed");
    }
  });
}
