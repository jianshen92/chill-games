(() => {
  const Hooks = {};

  Hooks.Clipboard = {
    mounted() {
      this.showToast = (message, error = false) => {
        const toast = document.getElementById("clipboard-toast");
        if (!toast) return;

        window.clearTimeout(toast.hideTimer);
        toast.textContent = message;
        toast.classList.toggle("error", error);
        toast.hidden = false;
        toast.hideTimer = window.setTimeout(() => {
          toast.hidden = true;
          toast.classList.remove("error");
        }, 2400);
      };

      this.copy = async () => {
        try {
          const value = this.el.dataset.copy || "";
          const text = value.startsWith("/") ? new URL(value, window.location.origin).toString() : value;
          await navigator.clipboard.writeText(text);
          this.showToast(this.el.dataset.copySuccess || "Copied");
        } catch (_error) {
          this.showToast(this.el.dataset.copyFailure || "Could not copy", true);
        }
      };

      this.el.addEventListener("click", this.copy);
    },

    destroyed() {
      this.el.removeEventListener("click", this.copy);
    },
  };

  Hooks.CardSelection = {
    mounted() {
      this.selected = new Set();
      this.submitting = false;

      this.click = (event) => {
        const card = event.target.closest("[data-card-id]");
        if (card && this.el.contains(card) && !card.disabled) {
          const cardId = card.dataset.cardId;
          if (this.selected.has(cardId)) this.selected.delete(cardId);
          else this.selected.add(cardId);
          this.renderSelection();
          return;
        }

        const clear = event.target.closest("[data-card-selection-clear]");
        if (clear && this.el.contains(clear) && !clear.disabled) {
          this.selected.clear();
          this.renderSelection();
          return;
        }

        const play = event.target.closest("[data-card-selection-play]");
        if (play && this.el.contains(play) && !play.disabled) {
          this.submitting = true;
          this.renderSelection();
          this.pushEvent("play-selected", {cards: Array.from(this.selected)}, () => {
            this.submitting = false;
            this.renderSelection();
          });
        }
      };

      this.el.addEventListener("click", this.click);
      this.reconcileSelection();
    },

    updated() {
      this.reconcileSelection();
    },

    destroyed() {
      this.el.removeEventListener("click", this.click);
    },

    reconcileSelection() {
      const heldCardIds = new Set(
        Array.from(this.el.querySelectorAll("[data-card-id]"), (card) => card.dataset.cardId),
      );
      for (const cardId of this.selected) {
        if (!heldCardIds.has(cardId)) this.selected.delete(cardId);
      }
      this.renderSelection();
    },

    renderSelection() {
      for (const card of this.el.querySelectorAll("[data-card-id]")) {
        const selected = this.selected.has(card.dataset.cardId);
        card.classList.toggle("selected", selected);
        card.setAttribute("aria-pressed", String(selected));
      }

      const count = this.el.querySelector("#selection-count");
      if (count) count.textContent = count.textContent.replace(/\d+/, String(this.selected.size));

      const play = this.el.querySelector("[data-card-selection-play]");
      const pending = play?.dataset.pending === "true";
      if (play) play.disabled = pending || this.submitting || this.selected.size === 0;

      const clear = this.el.querySelector("[data-card-selection-clear]");
      if (clear) clear.disabled = pending || this.submitting || this.selected.size === 0;
    },
  };

  Hooks.ReplaySeek = {
    mounted() {
      this.committedValue = this.el.querySelector("input[name='index']")?.value;
      this.input = (event) => {
        if (event.target.name !== "index") return;
        const position = document.getElementById("replay-position");
        if (position) {
          position.textContent = position.textContent.replace(
            /\d+/,
            String(Number(event.target.value) + 1),
          );
        }
      };
      this.change = (event) => {
        if (event.target.name !== "index" || event.target.value === this.committedValue) return;
        this.committedValue = event.target.value;
        this.pushEvent("seek-replay", {index: event.target.value});
      };
      this.el.addEventListener("input", this.input);
      this.el.addEventListener("change", this.change);
    },

    updated() {
      this.committedValue = this.el.querySelector("input[name='index']")?.value;
    },

    destroyed() {
      this.el.removeEventListener("input", this.input);
      this.el.removeEventListener("change", this.change);
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

  Hooks.GameAudio = {
    mounted() {
      this.manifest = null;
      this.audio = new Map();
      this.playerPersonas = new Map();
      this.queuedEvents = [];
      this.currentAudio = null;
      this.handleEvent("game-audio", ({event}) => this.playEvent(event));
      this.loadManifest();
    },

    updated() {
      this.refreshPlayerPersonas();
    },

    destroyed() {
      this.currentAudio?.pause();
      this.audio.clear();
      this.playerPersonas.clear();
      this.queuedEvents = [];
    },

    async loadManifest() {
      try {
        const manifestUrl = new URL(this.el.dataset.audioManifest, window.location.origin);
        const response = await fetch(manifestUrl, {credentials: "same-origin"});
        if (!response.ok) throw new Error(`Audio manifest returned ${response.status}`);

        this.manifest = await response.json();
        this.manifestUrl = manifestUrl;
        this.refreshPlayerPersonas();
        this.preload(this.manifest.events);

        const queuedEvents = this.queuedEvents;
        this.queuedEvents = [];
        for (const event of queuedEvents) this.playEvent(event);
      } catch (error) {
        console.warn("Game audio is unavailable.", error);
      }
    },

    refreshPlayerPersonas() {
      if (!this.manifest) return;

      const assignment = this.manifest.player_voice_assignment || {};
      const personaIds = assignment.personas || [];
      let playerIds = [];

      try {
        playerIds = JSON.parse(this.el.dataset.audioPlayerIds || "[]");
      } catch (_error) {
        console.warn("Game audio player assignment is invalid.");
      }

      this.playerPersonas.clear();
      playerIds.forEach((playerId, index) => {
        const personaId = personaIds[index];
        if (this.manifest.personas?.[personaId]) {
          this.playerPersonas.set(String(playerId), personaId);
        }
      });
    },

    personaEntries() {
      const personas = this.manifest.personas;
      return personas && Object.keys(personas).length > 0
        ? Object.entries(personas)
        : [["default", {base_path: "", volume: 1}]];
    },

    audioKey(personaId, file) {
      return `${personaId}:${file}`;
    },

    preload(entry) {
      if (!entry || typeof entry !== "object") return;

      if (entry.file) {
        for (const [personaId, persona] of this.personaEntries()) {
          const key = this.audioKey(personaId, entry.file);
          if (this.audio.has(key)) continue;

          const path = [persona.base_path, entry.file].filter(Boolean).join("/");
          const audio = new Audio(new URL(path, this.manifestUrl).toString());
          audio.preload = "auto";
          const volume = (this.manifest.pack?.volume ?? 1) * (persona.volume ?? 1);
          const playbackRate = this.manifest.pack?.playback_rate ?? 1;
          audio.volume = Math.max(0, Math.min(1, volume));
          audio.playbackRate = Math.max(0.25, Math.min(4, playbackRate));
          audio.preservesPitch = true;
          this.audio.set(key, audio);
        }
        return;
      }

      for (const variant of Object.values(entry.variants || entry)) this.preload(variant);
    },

    personaFor(event) {
      const assignment = this.manifest.player_voice_assignment || {};
      const fallback = assignment.fallback || this.personaEntries()[0][0];
      return this.playerPersonas.get(String(event.player_id)) || fallback;
    },

    playEvent(event) {
      if (!this.manifest) {
        this.queuedEvents.push(event);
        return;
      }

      const cue = this.resolve(this.manifest.events?.[event.type], event);
      if (!cue) return;

      const personaId = this.personaFor(event);
      const audio = this.audio.get(this.audioKey(personaId, cue.file));
      if (!audio) return;

      this.currentAudio?.pause();
      audio.currentTime = 0;
      this.currentAudio = audio;
      audio.play().catch(() => {});
    },

    resolve(entry, payload) {
      if (!entry) return null;
      if (entry.file) return entry;
      if (!entry.select || !entry.variants) return null;

      const selected = entry.select
        .split(".")
        .reduce((value, key) => value?.[key], payload);

      return this.resolve(entry.variants[String(selected)] || entry.fallback, payload);
    },
  };

  window.addEventListener("phx:store-locale", (event) => {
    const {locale, language_tag: languageTag} = event.detail;
    document.cookie = `doudizhu_locale=${encodeURIComponent(locale)}; Max-Age=31536000; Path=/; SameSite=Lax`;
    document.documentElement.lang = languageTag;
  });

  const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
  const liveSocket = new LiveView.LiveSocket("/live", Phoenix.Socket, {
    hooks: Hooks,
    params: {_csrf_token: csrfToken},
  });

  liveSocket.connect();
  window.liveSocket = liveSocket;
})();
