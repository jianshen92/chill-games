#!/usr/bin/env node

/**
 * Minimal headless Phoenix Channel client.
 *
 * Usage:
 *   DOUDIZHU_TOKEN=... node clients/channel_cli.mjs \
 *     --game game_id --player player_id [--url ws://localhost:4000/socket/websocket]
 *
 * Commands: bid 1|2|3, auction-pass, play C3 D3 H3, pass, snapshot, quit
 */

import {createInterface} from "node:readline";
import {randomUUID} from "node:crypto";

const args = new Map();
for (let index = 2; index < process.argv.length; index += 2) {
  args.set(process.argv[index], process.argv[index + 1]);
}

const token = process.env.DOUDIZHU_TOKEN;
const gameId = args.get("--game");
const playerId = args.get("--player");
const baseUrl = args.get("--url") || "ws://localhost:4000/socket/websocket";

if (!token || !gameId || !playerId) {
  console.error("DOUDIZHU_TOKEN, --game, and --player are required");
  process.exit(2);
}

const url = `${baseUrl}?vsn=2.0.0&token=${encodeURIComponent(token)}`;
const topic = `game:${gameId}`;
const socket = new WebSocket(url);
let nextRef = 1;
let sequence = 0;
let heartbeat;

function send(event, payload, joinRef = "1") {
  const ref = String(nextRef++);
  socket.send(JSON.stringify([joinRef, ref, topic, event, payload]));
  return ref;
}

function sendCommand(action) {
  send("command", {
    protocol_version: 1,
    kind: "command",
    game_id: gameId,
    command_id: randomUUID(),
    expected_version: sequence,
    action,
  });
}

function observe(message) {
  if (Number.isInteger(message?.sequence)) sequence = Math.max(sequence, message.sequence);
  if (Number.isInteger(message?.game_version)) sequence = Math.max(sequence, message.game_version);
  if (Number.isInteger(message?.snapshot?.sequence)) sequence = Math.max(sequence, message.snapshot.sequence);
  console.log(JSON.stringify(message));
}

socket.addEventListener("open", () => {
  send("phx_join", {player_id: playerId});
  heartbeat = setInterval(() => {
    const ref = String(nextRef++);
    socket.send(JSON.stringify([null, ref, "phoenix", "heartbeat", {}]));
  }, 25_000);
});

socket.addEventListener("message", ({data}) => {
  const [_joinRef, _ref, incomingTopic, event, payload] = JSON.parse(data);
  if (incomingTopic !== topic && incomingTopic !== "phoenix") return;

  if (event === "phx_reply") observe(payload.response);
  else if (event === "message") observe(payload);
  else if (event === "phx_error" || event === "phx_close") observe({kind: event});
});

socket.addEventListener("close", () => {
  clearInterval(heartbeat);
  process.exit(0);
});

socket.addEventListener("error", (error) => {
  console.error(error.message || "websocket error");
});

const input = createInterface({input: process.stdin, output: process.stderr, prompt: "> "});
input.prompt();
input.on("line", (line) => {
  const [command, ...values] = line.trim().split(/\s+/);

  if (command === "bid") sendCommand({type: "place_bid", bid: Number(values[0])});
  else if (command === "auction-pass") sendCommand({type: "auction_pass"});
  else if (command === "play") sendCommand({type: "play_cards", cards: values});
  else if (command === "pass") sendCommand({type: "play_pass"});
  else if (command === "snapshot") send("resync", {});
  else if (command === "quit") socket.close();
  else console.error("commands: bid N, auction-pass, play CARD..., pass, snapshot, quit");

  input.prompt();
});
