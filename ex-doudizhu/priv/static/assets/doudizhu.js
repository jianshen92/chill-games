const $ = (id) => document.getElementById(id);

const elements = {
  welcomePanel: $("welcome-panel"),
  welcomeForm: $("welcome-form"),
  playerName: $("player-name"),
  invitationNote: $("invitation-note"),
  createRoomButton: $("create-room-button"),
  joinRoomButton: $("join-room-button"),
  replayLibraryButton: $("replay-library-button"),
  welcomeError: $("welcome-error"),
  roomPanel: $("room-panel"),
  roomStatus: $("room-status"),
  invitationCard: $("invitation-card"),
  inviteCode: $("invite-code"),
  copyInviteButton: $("copy-invite-button"),
  seatList: $("seat-list"),
  readyButton: $("ready-button"),
  startButton: $("start-button"),
  roomMessage: $("room-message"),
  replayLibraryPanel: $("replay-library-panel"),
  closeReplayLibraryButton: $("close-replay-library-button"),
  replayIdForm: $("replay-id-form"),
  replayGameId: $("replay-game-id"),
  replayList: $("replay-list"),
  replayLibraryError: $("replay-library-error"),
  gamePanel: $("game-panel"),
  phaseTitle: $("phase-title"),
  rolePill: $("role-pill"),
  versionLabel: $("version-label"),
  replayControls: $("replay-controls"),
  replayExitButton: $("replay-exit-button"),
  copyReplayLinkButton: $("copy-replay-link-button"),
  replayPreviousButton: $("replay-previous-button"),
  replayPlayButton: $("replay-play-button"),
  replayNextButton: $("replay-next-button"),
  replaySlider: $("replay-slider"),
  replayPosition: $("replay-position"),
  opponents: $("opponents"),
  replayHands: $("replay-hands"),
  bottomArea: $("bottom-area"),
  bottomCards: $("bottom-cards"),
  turnIndicator: $("turn-indicator"),
  leadCards: $("lead-cards"),
  leadDescription: $("lead-description"),
  handHeading: $("hand-heading"),
  hand: $("hand"),
  handCount: $("hand-count"),
  selectionCount: $("selection-count"),
  actionBar: $("action-bar"),
  bidControls: $("bid-controls"),
  playControls: $("play-controls"),
  waitingMessage: $("waiting-message"),
  auctionPassButton: $("auction-pass-button"),
  playButton: $("play-button"),
  playPassButton: $("play-pass-button"),
  clearSelectionButton: $("clear-selection-button"),
  resyncButton: $("resync-button"),
  settlement: $("settlement"),
  winnerTitle: $("winner-title"),
  scoreList: $("score-list"),
  gameError: $("game-error"),
  eventLog: $("event-log"),
  connectionDot: $("connection-dot"),
  connectionLabel: $("connection-label"),
  reconnectButton: $("reconnect-button"),
  toast: $("toast"),
};

const params = new URLSearchParams(location.search);
const invitation = {
  roomId: params.get("room"),
  code: params.get("invite"),
};
const directReplayId = params.get("replay");

const state = {
  session: loadSession(),
  socket: null,
  lobbyChannel: null,
  roomChannel: null,
  gameChannel: null,
  replayLobbyChannel: null,
  replay: null,
  roomId: invitation.roomId,
  inviteCode: invitation.code,
  room: null,
  gameId: null,
  snapshot: null,
  selected: new Set(),
  pendingVersion: null,
  reconnecting: false,
};

class ChannelSocket {
  constructor(token, onState) {
    this.token = token;
    this.onState = onState;
    this.ref = 0;
    this.channels = new Map();
    this.pending = new Map();
    this.heartbeat = null;
    this.socket = null;
  }

  connect() {
    this.onState("connecting");
    const scheme = location.protocol === "https:" ? "wss" : "ws";
    const url = `${scheme}://${location.host}/socket/websocket?vsn=2.0.0&token=${encodeURIComponent(this.token)}`;

    return new Promise((resolve, reject) => {
      const socket = new WebSocket(url);
      this.socket = socket;

      socket.addEventListener("open", () => {
        this.onState("online");
        this.heartbeat = window.setInterval(() => this.sendHeartbeat(), 25_000);
        resolve();
      }, {once: true});

      socket.addEventListener("error", () => reject(new Error("Could not connect to the game server.")), {once: true});
      socket.addEventListener("message", (message) => this.receive(message.data));
      socket.addEventListener("close", () => this.closed());
    });
  }

  join(topic, payload, handler = () => {}) {
    const ref = this.nextRef();
    const channel = {topic, joinRef: ref, handler};
    this.channels.set(topic, channel);

    return new Promise((resolve, reject) => {
      this.pending.set(ref, {resolve, reject, topic, join: true});
      this.send([ref, ref, topic, "phx_join", payload]);
    });
  }

  push(channel, event, payload) {
    const ref = this.nextRef();

    return new Promise((resolve, reject) => {
      this.pending.set(ref, {resolve, reject, topic: channel.topic, join: false});
      this.send([channel.joinRef, ref, channel.topic, event, payload]);
    });
  }

  close() {
    this.socket?.close();
  }

  nextRef() {
    this.ref += 1;
    return String(this.ref);
  }

  send(frame) {
    if (!this.socket || this.socket.readyState !== WebSocket.OPEN) {
      throw new Error("The server connection is not open.");
    }
    this.socket.send(JSON.stringify(frame));
  }

  sendHeartbeat() {
    if (this.socket?.readyState === WebSocket.OPEN) {
      const ref = this.nextRef();
      this.send([null, ref, "phoenix", "heartbeat", {}]);
    }
  }

  receive(raw) {
    let frame;
    try {
      frame = JSON.parse(raw);
    } catch (_error) {
      return;
    }

    if (!Array.isArray(frame) || frame.length !== 5) return;
    const [_joinRef, ref, topic, event, payload] = frame;

    if (event === "phx_reply" && ref && this.pending.has(ref)) {
      const pending = this.pending.get(ref);
      this.pending.delete(ref);

      if (payload.status === "ok") pending.resolve(payload.response);
      else {
        if (pending.join) this.channels.delete(pending.topic);
        pending.reject(new Error(errorMessage(payload.response)));
      }
      return;
    }

    const channel = this.channels.get(topic);
    if (channel) channel.handler(event, payload);
  }

  closed() {
    window.clearInterval(this.heartbeat);
    this.onState("offline");
    const error = new Error("Connection closed.");
    for (const pending of this.pending.values()) pending.reject(error);
    this.pending.clear();
  }
}

function loadSession() {
  try {
    return JSON.parse(localStorage.getItem("doudizhu.session")) || null;
  } catch (_error) {
    return null;
  }
}

function saveSession(session) {
  localStorage.setItem("doudizhu.session", JSON.stringify(session));
  state.session = session;
}

async function createGuestSession(name) {
  const response = await fetch("/api/guest-session", {
    method: "POST",
    headers: {"content-type": "application/json", "accept": "application/json"},
    body: JSON.stringify({name}),
  });
  const payload = await response.json();
  if (!response.ok) throw new Error(errorMessage(payload));
  saveSession(payload);
  return payload;
}

async function ensureSession(name) {
  if (!state.session?.token) return createGuestSession(name);
  state.session.name = name;
  saveSession(state.session);
  return state.session;
}

async function connectSocket() {
  if (state.socket) state.socket.close();
  const socket = new ChannelSocket(state.session.token, setConnectionState);
  state.socket = socket;
  await socket.connect();
  return socket;
}

async function createRoom() {
  const socket = await connectSocket();
  state.lobbyChannel = await join(socket, "room:lobby", {}, () => {});
  const response = await socket.push(state.lobbyChannel, "create", {player_name: state.session.name});
  state.roomId = response.room_id;
  state.inviteCode = response.invite_code;
  const query = new URLSearchParams({room: state.roomId, invite: state.inviteCode});
  history.replaceState({}, "", `/?${query}`);
  await joinRoom();
}

async function joinRoom() {
  const socket = state.socket || await connectSocket();
  const payload = {player_name: state.session.name};
  if (state.inviteCode) payload.invite_code = state.inviteCode;

  state.roomChannel = await join(socket, `room:${state.roomId}`, payload, (event, message) => {
    if (event === "message" && message?.kind === "room_snapshot") updateRoom(message);
  });

  const response = state.roomChannel.joinResponse;
  updateRoom(response.room);
}

async function joinGame(gameId) {
  if (state.gameChannel?.topic === `game:${gameId}`) return;

  state.replay = null;
  state.gameId = gameId;
  state.gameChannel = await join(
    state.socket,
    `game:${gameId}`,
    {player_id: state.session.identity_id},
    handleGameMessage,
  );

  updateSnapshot(state.gameChannel.joinResponse.snapshot);
}

async function openReplayLibrary() {
  const name = elements.playerName.value.trim() || state.session?.name;
  if (!name) throw new Error("Enter your name first.");

  await ensureSession(name);
  const socket = await connectSocket();
  state.replayLobbyChannel = await join(socket, "replay:lobby", {}, () => {});
  renderReplayLibrary(state.replayLobbyChannel.joinResponse.games || []);
}

function renderReplayLibrary(games) {
  stopReplay();
  state.replay = null;
  state.snapshot = null;
  elements.welcomePanel.hidden = true;
  elements.roomPanel.hidden = true;
  elements.gamePanel.hidden = true;
  elements.replayLibraryPanel.hidden = false;
  elements.replayLibraryError.textContent = "";
  elements.replayList.replaceChildren();

  if (games.length === 0) {
    elements.replayList.append(element("div", "replay-empty", "No recorded games were found for this guest identity."));
    return;
  }

  for (const game of games) {
    const entry = element("article", "replay-entry");
    const details = element("div", "");
    const names = game.players.map((player) => player.name).join(" · ");
    const date = new Date(game.played_at).toLocaleString();
    const result = game.winner ? `${game.winner.side} won` : game.status;
    const resultLine = element("p", "", `${date} · ${game.final_version} turns · `);
    resultLine.append(element("span", "replay-result", result));
    details.append(
      element("h3", "", names),
      resultLine,
      element("p", "", `Game ID: ${game.public_replay_id}`),
    );

    const button = element("button", "button accent", "Watch replay");
    button.type = "button";
    button.addEventListener("click", () => startReplay(game.game_id).catch(showReplayError));
    entry.append(details, button);
    elements.replayList.append(entry);
  }
}

async function startReplay(gameId) {
  const channel = await join(state.socket, `replay:${gameId}`, {}, () => {});
  const response = channel.joinResponse;
  state.replay = {
    channel,
    metadata: response.replay,
    index: 0,
    playing: false,
    timer: null,
  };
  state.gameChannel = null;
  state.gameId = gameId;
  elements.replayGameId.value = gameId;
  history.replaceState({}, "", `/?${new URLSearchParams({replay: gameId})}`);
  elements.replayLibraryPanel.hidden = true;
  applyReplayFrame(response.frame);
}

async function requestReplayFrame(index) {
  if (!state.replay || index < 0 || index >= state.replay.metadata.frame_count) return;
  const frame = await state.socket.push(state.replay.channel, "frame", {index});
  applyReplayFrame(frame);
}

function applyReplayFrame(frame) {
  state.replay.index = frame.index;
  state.snapshot = frame.snapshot;
  state.selected.clear();
  elements.eventLog.replaceChildren();
  for (const event of frame.history || []) appendEvent(event);
  renderGame();
  renderReplayControls();
}

function renderReplayControls() {
  if (!state.replay) {
    elements.replayControls.hidden = true;
    return;
  }

  const count = state.replay.metadata.frame_count;
  const index = state.replay.index;
  elements.replayControls.hidden = false;
  elements.replaySlider.max = String(Math.max(0, count - 1));
  elements.replaySlider.value = String(index);
  elements.replayPosition.textContent = `Step ${index + 1} of ${count}`;
  elements.replayPreviousButton.disabled = index === 0;
  elements.replayNextButton.disabled = index >= count - 1;
  elements.replayPlayButton.textContent = state.replay.playing ? "Pause" : "Play";
}

function stopReplay() {
  if (!state.replay) return;
  state.replay.playing = false;
  window.clearTimeout(state.replay.timer);
  state.replay.timer = null;
}

function toggleReplayPlayback() {
  if (!state.replay) return;

  if (state.replay.playing) {
    stopReplay();
    renderReplayControls();
    return;
  }

  state.replay.playing = true;
  renderReplayControls();
  advanceReplay();
}

async function advanceReplay() {
  if (!state.replay?.playing) return;

  if (state.replay.index >= state.replay.metadata.frame_count - 1) {
    stopReplay();
    renderReplayControls();
    return;
  }

  try {
    await requestReplayFrame(state.replay.index + 1);
    if (state.replay?.playing) {
      state.replay.timer = window.setTimeout(advanceReplay, 1_100);
    }
  } catch (error) {
    stopReplay();
    showReplayError(error);
  }
}

function exitReplay() {
  stopReplay();
  state.replay = null;
  state.snapshot = null;
  elements.gamePanel.hidden = true;
  history.replaceState({}, "", "/");
  openReplayLibrary().catch(showReplayError);
}

function showReplayError(error) {
  elements.replayLibraryError.textContent = error.message || errorMessage(error);
  elements.gameError.textContent = error.message || errorMessage(error);
}

async function join(socket, topic, payload, handler) {
  const response = await socket.join(topic, payload, handler);
  const channel = socket.channels.get(topic);
  channel.joinResponse = response;
  return channel;
}

function updateRoom(room) {
  if (!room) return;
  state.room = room;
  renderRoom();

  if (room.game_id) {
    joinGame(room.game_id).catch(showRoomError);
  }
}

function handleGameMessage(event, message) {
  if (event !== "message") return;

  if (message.kind === "snapshot") updateSnapshot(message);
  if (message.kind === "game_event") appendEvent(message.event);
}

function updateSnapshot(snapshot) {
  if (!snapshot) return;
  state.snapshot = snapshot;
  state.pendingVersion = null;
  const held = new Set(snapshot.you?.hand || []);
  state.selected = new Set([...state.selected].filter((card) => held.has(card)));
  renderGame();
}

async function sendAction(action) {
  if (!state.snapshot || !state.gameChannel || state.pendingVersion !== null) return;
  elements.gameError.textContent = "";

  const envelope = {
    protocol_version: 1,
    kind: "command",
    game_id: state.gameId,
    command_id: crypto.randomUUID(),
    expected_version: state.snapshot.sequence,
    action,
  };

  state.pendingVersion = state.snapshot.sequence + 1;
  renderActions();

  try {
    const result = await state.socket.push(state.gameChannel, "command", envelope);
    if (result.status === "rejected" || result.kind === "protocol_error") {
      state.pendingVersion = null;
      elements.gameError.textContent = errorMessage(result);
      renderActions();
    } else {
      state.selected.clear();
    }
  } catch (error) {
    state.pendingVersion = null;
    elements.gameError.textContent = error.message;
    renderActions();
  }
}

function renderRoom() {
  const room = state.room;
  if (!room) return;

  elements.welcomePanel.hidden = true;
  elements.replayLibraryPanel.hidden = true;
  elements.gamePanel.hidden = Boolean(!room.game_id);
  elements.roomPanel.hidden = Boolean(room.game_id);
  elements.roomStatus.textContent = room.status;

  elements.invitationCard.hidden = !state.inviteCode;
  elements.inviteCode.textContent = state.inviteCode || "";

  elements.seatList.replaceChildren();
  const seats = new Map(room.seats.map((seat) => [seat.position, seat]));

  for (let position = 1; position <= 3; position += 1) {
    const seat = seats.get(position);
    const item = document.createElement("li");
    item.className = "seat";

    const number = element("span", "seat-number", String(position));
    const details = element("div", "seat-details");
    details.append(
      element("strong", "", seat?.player_name || "Open seat"),
      element("span", "", seat ? (seat.player_id === state.session.identity_id ? "You" : "Connected player") : "Waiting for a friend"),
    );
    item.append(number, details);
    if (seat) item.append(element("span", "ready-mark", seat.ready ? "Ready" : "Not ready"));
    elements.seatList.append(item);
  }

  const ownSeat = room.seats.find((seat) => seat.player_id === state.session.identity_id);
  elements.readyButton.textContent = ownSeat?.ready ? "Not ready" : "I’m ready";
  elements.readyButton.dataset.ready = String(Boolean(ownSeat?.ready));
  elements.readyButton.disabled = room.status !== "open";

  const owner = room.owner_id === state.session.identity_id;
  const canStart = owner && room.seats.length === 3 && room.seats.every((seat) => seat.ready);
  elements.startButton.hidden = !owner;
  elements.startButton.disabled = !canStart;
  elements.roomMessage.textContent = canStart ? "Everyone is ready." : "The game starts when all three players are ready.";
}

function renderGame() {
  const snapshot = state.snapshot;
  if (!snapshot) return;

  elements.welcomePanel.hidden = true;
  elements.roomPanel.hidden = true;
  elements.replayLibraryPanel.hidden = true;
  elements.gamePanel.hidden = false;

  const game = snapshot.game;
  const you = snapshot.you;
  const players = snapshot.players;
  elements.phaseTitle.textContent = `${state.replay ? "Replay · " : ""}${phaseName(game.phase)}`;
  elements.versionLabel.textContent = `Turn ${snapshot.sequence}`;
  elements.resyncButton.hidden = Boolean(state.replay);

  elements.rolePill.hidden = !you?.role;
  elements.rolePill.textContent = you?.role || "";

  elements.opponents.hidden = Boolean(state.replay);
  elements.handHeading.hidden = Boolean(state.replay);
  elements.hand.hidden = Boolean(state.replay);
  renderPlayers(players, game, you?.player_id);
  renderReplayHands(snapshot, players, game);
  renderLead(game.current_lead);
  renderHand(you?.hand || []);
  renderTurn(game, players);
  renderActions();
  renderReplayControls();
  renderSettlement(game, players);
}

function renderPlayers(players, game, ownId) {
  elements.opponents.replaceChildren();

  for (const player of players.filter((candidate) => candidate.player_id !== ownId)) {
    const summary = element("div", "player-summary");
    const currentId = game.current_player || game.current_bidder;
    if (player.player_id === currentId) summary.classList.add("current");

    const details = element("div", "");
    details.append(
      element("strong", "", player.name),
      element("span", "", `${game.hand_counts?.[player.player_id] ?? 0} cards`),
    );

    if (player.player_id === game.landlord) {
      details.append(element("span", "landlord-mark", "Landlord"));
    }

    summary.append(element("span", "avatar", player.name.slice(0, 1).toUpperCase()), details);
    elements.opponents.append(summary);
  }
}

function renderReplayHands(snapshot, players, game) {
  const replaying = Boolean(state.replay);
  elements.replayHands.hidden = !replaying;
  elements.bottomArea.hidden = !replaying;
  elements.replayHands.replaceChildren();
  elements.bottomCards.replaceChildren();
  if (!replaying) return;

  for (const player of players) {
    const cards = snapshot.hands?.[player.player_id] || [];
    const hand = element("div", "replay-hand");
    const heading = element("div", "replay-hand-heading");
    const role = snapshot.roles?.[player.player_id] || (player.player_id === game.landlord ? "landlord" : "");
    heading.append(
      element("strong", "", player.name),
      element("span", "", `${role || "Unassigned"} · ${cards.length} cards`),
    );

    const cardRow = element("div", "mini-cards replay-hand-cards");
    if (cards.length === 0) cardRow.append(element("span", "empty-state", "No cards"));
    for (const card of cards) cardRow.append(miniCard(card));
    hand.append(heading, cardRow);
    elements.replayHands.append(hand);
  }

  const bottomCards = snapshot.bottom_cards || [];
  if (bottomCards.length === 0) elements.bottomCards.append(element("span", "empty-state", "Not dealt"));
  for (const card of bottomCards) elements.bottomCards.append(miniCard(card));
}

function renderLead(lead) {
  elements.leadCards.replaceChildren();

  if (!lead) {
    elements.leadCards.append(element("span", "empty-state", "No cards led"));
    elements.leadDescription.textContent = "";
    return;
  }

  for (const card of lead.combination.cards || []) {
    elements.leadCards.append(miniCard(card));
  }
  elements.leadDescription.textContent = combinationName(lead.combination);
}

function renderHand(cards) {
  elements.hand.replaceChildren();
  elements.handCount.textContent = `${cards.length} ${cards.length === 1 ? "card" : "cards"}`;

  for (const cardId of cards) {
    const card = cardButton(cardId);
    if (state.selected.has(cardId)) card.classList.add("selected");

    if (!state.replay) {
      card.addEventListener("click", () => {
        if (state.selected.has(cardId)) state.selected.delete(cardId);
        else state.selected.add(cardId);
        renderHand(cards);
        renderActions();
      });
    } else {
      card.disabled = true;
    }
    elements.hand.append(card);
  }

  elements.selectionCount.textContent = `${state.selected.size} selected`;
}

function renderTurn(game, players) {
  const currentId = game.current_player || game.current_bidder;
  const current = players.find((player) => player.player_id === currentId);

  if (game.phase === "finished") elements.turnIndicator.textContent = "Game complete";
  else if (state.replay) elements.turnIndicator.textContent = current ? `Recorded turn: ${current.name}` : "Recorded state";
  else if (currentId === state.session.identity_id) elements.turnIndicator.textContent = "Your turn";
  else elements.turnIndicator.textContent = current ? `${current.name} is thinking` : "Waiting";
}

function renderActions() {
  const snapshot = state.snapshot;
  if (!snapshot) return;

  if (state.replay) {
    elements.actionBar.hidden = true;
    return;
  }

  elements.actionBar.hidden = false;
  const game = snapshot.game;
  const playerId = state.session.identity_id;
  const pending = state.pendingVersion !== null;
  const biddingTurn = game.phase === "bidding" && game.current_bidder === playerId;
  const playingTurn = game.phase === "playing" && game.current_player === playerId;

  elements.bidControls.hidden = !biddingTurn;
  elements.playControls.hidden = !playingTurn;
  elements.waitingMessage.hidden = biddingTurn || playingTurn || game.phase === "finished";

  for (const button of document.querySelectorAll(".bid-button")) button.disabled = pending;
  elements.auctionPassButton.disabled = pending;
  elements.playButton.disabled = pending || state.selected.size === 0;
  elements.playPassButton.disabled = pending || !game.current_lead;
  elements.clearSelectionButton.disabled = pending || state.selected.size === 0;
  elements.selectionCount.textContent = `${state.selected.size} selected`;
}

function renderSettlement(game, players) {
  const finished = game.phase === "finished" && game.settlement;
  elements.settlement.hidden = !finished;
  if (!finished) return;

  const settlement = game.settlement;
  const winner = players.find((player) => player.player_id === settlement.winning_player);
  elements.winnerTitle.textContent = `${winner?.name || "A player"} wins for the ${settlement.winning_side}`;
  elements.scoreList.replaceChildren();

  for (const player of players) {
    const delta = settlement.deltas[player.player_id] ?? 0;
    const row = element("div", "score-row");
    const score = element("strong", delta >= 0 ? "score-positive" : "score-negative", `${delta >= 0 ? "+" : ""}${delta}`);
    row.append(element("span", "", player.name), score);
    elements.scoreList.append(row);
  }
}

function appendEvent(event) {
  const item = document.createElement("li");
  item.textContent = eventDescription(event);
  elements.eventLog.append(item);
  while (elements.eventLog.children.length > 80) elements.eventLog.firstElementChild.remove();
  elements.eventLog.scrollTop = elements.eventLog.scrollHeight;
}

function cardButton(cardId) {
  const parsed = parseCard(cardId);
  const button = element("button", `card ${parsed.red ? "red" : ""} ${parsed.joker ? "joker" : ""}`.trim());
  button.type = "button";
  button.setAttribute("aria-label", parsed.label);
  button.append(
    element("span", "rank", parsed.rank),
    element("span", "suit", parsed.suit),
    element("span", "card-center", parsed.center),
  );
  return button;
}

function miniCard(cardId) {
  const parsed = parseCard(cardId);
  return element("span", `mini-card ${parsed.red ? "red" : ""}`, parsed.joker ? parsed.rank : `${parsed.rank}${parsed.suit}`);
}

function parseCard(cardId) {
  if (cardId === "JOKER_SMALL") return {rank: "小", suit: "", center: "JOKER", label: "Small joker", joker: true, red: false};
  if (cardId === "JOKER_BIG") return {rank: "大", suit: "", center: "JOKER", label: "Big joker", joker: true, red: true};

  const suitId = cardId.slice(0, 1);
  const rank = cardId.slice(1);
  const suits = {
    C: {symbol: "♣", name: "clubs", red: false},
    D: {symbol: "♦", name: "diamonds", red: true},
    H: {symbol: "♥", name: "hearts", red: true},
    S: {symbol: "♠", name: "spades", red: false},
  };
  const suit = suits[suitId];
  return {rank, suit: suit.symbol, center: suit.symbol, label: `${rank} of ${suit.name}`, joker: false, red: suit.red};
}

function phaseName(phase) {
  return ({awaiting_deal: "Waiting for deal", bidding: "Call the landlord", playing: "Play", finished: "Settlement"})[phase] || phase;
}

function combinationName(combination) {
  const names = {
    single: "Single", pair: "Pair", triple: "Triple", triple_with_single: "Triple with single",
    triple_with_pair: "Triple with pair", straight: "Straight", consecutive_pairs: "Consecutive pairs",
    airplane: "Airplane", airplane_with_singles: "Airplane with singles",
    airplane_with_pairs: "Airplane with pairs", four_with_singles: "Four with singles",
    four_with_pairs: "Four with pairs", bomb: "Bomb", rocket: "Rocket",
  };
  return names[combination.type] || combination.type;
}

function eventDescription(event) {
  const player = (id) => state.snapshot?.players?.find((candidate) => candidate.player_id === id)?.name || "A player";

  switch (event.type) {
    case "cards_dealt": return `Cards dealt. ${player(event.auction_starter)} starts the auction.`;
    case "auction_passed": return `${player(event.player_id)} passed in the auction.`;
    case "bid_placed": return `${player(event.player_id)} bid ${event.bid}.`;
    case "deal_voided": return "Everyone passed. The deal was voided.";
    case "landlord_chosen": return `${player(event.landlord)} became landlord with bid ${event.bid}.`;
    case "cards_played": return `${player(event.player_id)} played ${combinationName(event.combination)}.`;
    case "turn_passed": return `${player(event.player_id)} passed.`;
    case "lead_cleared": return `Lead cleared. ${player(event.next_leader)} leads again.`;
    case "game_finished": return `Game finished: ${event.settlement.winning_side} win.`;
    default: return event.type;
  }
}

function errorMessage(payload) {
  const error = payload?.error || payload;
  const code = error?.code || "unknown_error";
  const messages = {
    name_required: "Enter a name to continue.",
    name_too_long: "Names may contain at most 30 characters.",
    invalid_invite: "That invitation code is invalid.",
    room_full: "This table already has three players.",
    room_not_open: "This table is no longer open.",
    not_authorized: "You are not authorized for that seat.",
    controller_lease_invalid: "This seat was opened in another connection. Reconnect to reclaim it.",
    stale_game_version: "Your view was stale. Resync and try again.",
    not_players_turn: "It is not your turn.",
    bid_must_exceed: "Your bid must exceed the current bid.",
    invalid_combination: "Those cards do not form a legal combination.",
    cards_not_held: "Your hand does not contain those cards.",
    does_not_beat_current_lead: "That play does not beat the current lead.",
    cannot_pass_when_leading: "You cannot pass when you have the lead.",
    replay_not_finished: "Full-information replay becomes available after the game finishes.",
    replay_frame_not_found: "That replay position does not exist.",
    replay_diverged: "The recorded commands did not reproduce the saved result.",
    replay_corrupt: "This replay record could not be reconstructed.",
  };
  return messages[code] || String(code).replaceAll("_", " ");
}

function setConnectionState(connectionState) {
  elements.connectionDot.className = `status-dot ${connectionState}`;
  elements.connectionLabel.textContent = connectionState[0].toUpperCase() + connectionState.slice(1);
  elements.reconnectButton.hidden = connectionState !== "offline" || !state.session;
}

function showRoomError(error) {
  state.pendingVersion = null;
  elements.roomMessage.textContent = error.message || errorMessage(error);
}

function showToast(message) {
  elements.toast.textContent = message;
  elements.toast.hidden = false;
  window.setTimeout(() => { elements.toast.hidden = true; }, 2_400);
}

function element(tag, className = "", text = "") {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== "") node.textContent = text;
  return node;
}

async function reconnect() {
  if (state.reconnecting) return;
  state.reconnecting = true;
  elements.reconnectButton.hidden = true;

  try {
    const replayGameId = state.replay?.metadata.game_id;
    const replayIndex = state.replay?.index || 0;
    state.socket = null;
    state.roomChannel = null;
    state.gameChannel = null;
    await connectSocket();

    if (replayGameId) {
      await startReplay(replayGameId);
      if (replayIndex > 0) await requestReplayFrame(replayIndex);
    } else if (state.roomId) {
      await joinRoom();
    }
  } catch (error) {
    setConnectionState("offline");
    showToast(error.message);
  } finally {
    state.reconnecting = false;
  }
}

elements.welcomeForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  elements.welcomeError.textContent = "";
  const name = elements.playerName.value.trim();
  if (!name) return;
  elements.createRoomButton.disabled = true;
  elements.joinRoomButton.disabled = true;

  try {
    await ensureSession(name);
    if (state.roomId) await joinRoom();
    else await createRoom();
  } catch (error) {
    elements.welcomeError.textContent = error.message;
    setConnectionState("offline");
  } finally {
    elements.createRoomButton.disabled = false;
    elements.joinRoomButton.disabled = false;
  }
});

elements.replayLibraryButton.addEventListener("click", async () => {
  elements.welcomeError.textContent = "";
  elements.replayLibraryButton.disabled = true;

  try {
    await openReplayLibrary();
  } catch (error) {
    elements.welcomeError.textContent = error.message;
    setConnectionState("offline");
  } finally {
    elements.replayLibraryButton.disabled = false;
  }
});

elements.closeReplayLibraryButton.addEventListener("click", () => {
  stopReplay();
  state.socket?.close();
  state.socket = null;
  history.replaceState({}, "", "/");
  elements.replayLibraryPanel.hidden = true;
  elements.gamePanel.hidden = true;
  elements.welcomePanel.hidden = false;
});

elements.replayIdForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  elements.replayLibraryError.textContent = "";
  const gameId = elements.replayGameId.value.trim();
  if (!gameId) return;

  try {
    await startReplay(gameId);
  } catch (error) {
    showReplayError(error);
  }
});

elements.copyReplayLinkButton.addEventListener("click", async () => {
  const url = new URL(location.origin);
  url.search = new URLSearchParams({replay: state.replay.metadata.public_replay_id});
  await navigator.clipboard.writeText(url.toString());
  showToast("Public replay link copied");
});

elements.replayPreviousButton.addEventListener("click", () => {
  stopReplay();
  requestReplayFrame(state.replay.index - 1).catch(showReplayError);
});
elements.replayNextButton.addEventListener("click", () => {
  stopReplay();
  requestReplayFrame(state.replay.index + 1).catch(showReplayError);
});
elements.replayPlayButton.addEventListener("click", toggleReplayPlayback);
elements.replaySlider.addEventListener("change", () => {
  stopReplay();
  requestReplayFrame(Number(elements.replaySlider.value)).catch(showReplayError);
});
elements.replayExitButton.addEventListener("click", exitReplay);

elements.readyButton.addEventListener("click", async () => {
  try {
    const currentlyReady = elements.readyButton.dataset.ready === "true";
    await state.socket.push(state.roomChannel, "ready", {ready: !currentlyReady});
  } catch (error) {
    showRoomError(error);
  }
});

elements.startButton.addEventListener("click", async () => {
  try {
    const room = await state.socket.push(state.roomChannel, "start", {});
    updateRoom(room);
  } catch (error) {
    showRoomError(error);
  }
});

elements.copyInviteButton.addEventListener("click", async () => {
  const url = new URL(location.href);
  url.search = new URLSearchParams({room: state.roomId, invite: state.inviteCode});
  await navigator.clipboard.writeText(url.toString());
  showToast("Invitation link copied");
});

for (const button of document.querySelectorAll(".bid-button")) {
  button.addEventListener("click", () => sendAction({type: "place_bid", bid: Number(button.dataset.bid)}));
}

elements.auctionPassButton.addEventListener("click", () => sendAction({type: "auction_pass"}));
elements.playButton.addEventListener("click", () => sendAction({type: "play_cards", cards: [...state.selected]}));
elements.playPassButton.addEventListener("click", () => sendAction({type: "play_pass"}));
elements.clearSelectionButton.addEventListener("click", () => {
  state.selected.clear();
  renderGame();
});
elements.resyncButton.addEventListener("click", async () => {
  try {
    const snapshot = await state.socket.push(state.gameChannel, "resync", {});
    updateSnapshot(snapshot);
  } catch (error) {
    elements.gameError.textContent = error.message;
  }
});
elements.reconnectButton.addEventListener("click", reconnect);

if (state.session?.name) elements.playerName.value = state.session.name;
if (state.roomId && !directReplayId) {
  elements.invitationNote.hidden = false;
  elements.createRoomButton.hidden = true;
  elements.joinRoomButton.hidden = false;
}
setConnectionState("offline");

if (directReplayId) {
  elements.replayGameId.value = directReplayId;

  (async () => {
    try {
      if (!state.session?.token) await createGuestSession("Replay viewer");
      if (state.session?.name) elements.playerName.value = state.session.name;
      await openReplayLibrary();
      await startReplay(directReplayId);
    } catch (error) {
      elements.welcomePanel.hidden = true;
      elements.replayLibraryPanel.hidden = false;
      showReplayError(error);
    }
  })();
}
