(() => {
  const Hooks = {};

  Hooks.Clipboard = {
    mounted() {
      this.copy = async () => {
        try {
          const value = this.el.dataset.copy || "";
          const text = value.startsWith("/") ? new URL(value, window.location.origin).toString() : value;
          await navigator.clipboard.writeText(text);
          this.pushEvent("copied", {kind: this.el.dataset.copyKind});
        } catch (_error) {
          this.pushEvent("copy-failed", {});
        }
      };

      this.el.addEventListener("click", this.copy);
    },

    destroyed() {
      this.el.removeEventListener("click", this.copy);
    },
  };

  Hooks.ScrollToBottom = {
    mounted() {
      this.el.scrollTop = this.el.scrollHeight;
    },

    updated() {
      this.el.scrollTop = this.el.scrollHeight;
    },
  };

  const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
  const liveSocket = new LiveView.LiveSocket("/live", Phoenix.Socket, {
    hooks: Hooks,
    params: {_csrf_token: csrfToken},
  });

  liveSocket.connect();
  window.liveSocket = liveSocket;
})();
