// dawlings' Discord bridge: a bot that follows its owner into whatever voice channel they are in
// and plays dawlings' discord stream there, as a member of its own.
//
// The game starts it (core/audio/discord_feed.gd) and keeps its stdin open; when that closes -- the
// game quit, or the feed was switched off -- it leaves the channel and exits. What it plays is the
// monitor of a null sink the game plays its `dawlings · discord` stream into, read with parec, so
// anything else on the machine can be routed into that sink as well.
//
// Configuration is never in the repo: ~/.config/dawlings/discord.json (or DAWLINGS_DISCORD_CONFIG)
//   { "token": "<the bot's token>", "user_id": "<your Discord user id>" }
// or the environment: DAWLINGS_DISCORD_TOKEN, DAWLINGS_DISCORD_USER.
//
// It says what it is doing as one JSON object a line on stdout, for the session panel:
//   {"state": "starting" | "waiting" | "joining" | "playing" | "error" | "stopped", "say": "...",
//    "channel": "...", "guild": "..."}

import { spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { Client, Events, GatewayIntentBits } from "discord.js";
import {
	AudioPlayerStatus, NoSubscriberBehavior, StreamType, VoiceConnectionStatus,
	createAudioPlayer, createAudioResource, entersState, getVoiceConnection, joinVoiceChannel,
} from "@discordjs/voice";

const args = Object.fromEntries(process.argv.slice(2).map((a) => a.replace(/^--/, "").split("=")));
const SOURCE = args.source ?? "dawlings_discord.monitor";

function say(state, words, extra = {}) {
	process.stdout.write(JSON.stringify({ state, say: words, ...extra }) + "\n");
}

function config() {
	const path = process.env.DAWLINGS_DISCORD_CONFIG ?? join(homedir(), ".config", "dawlings", "discord.json");
	let file = {};
	try {
		file = JSON.parse(readFileSync(path, "utf8"));
	} catch (e) {
		if (e.code !== "ENOENT") say("error", `could not read ${path}: ${e.message}`);
	}
	return {
		token: process.env.DAWLINGS_DISCORD_TOKEN ?? file.token ?? "",
		user: process.env.DAWLINGS_DISCORD_USER ?? file.user_id ?? "",
		path,
	};
}

const { token, user, path } = config();
if (!token || !user) {
	say("error", `no bot token or user id: put {"token": ..., "user_id": ...} in ${path} (see docs/discord.md)`);
	process.exit(2);
}

// The stream, raw 48 kHz stereo 16-bit, as Discord's encoder takes it. One parec for the life of the
// bridge: the player is fed from it whether or not anyone is listening, so joining is instant.
let parec = null;
function capture() {
	parec = spawn("parec", ["--raw", "--format=s16le", "--rate=48000", "--channels=2",
		`--device=${SOURCE}`, "--latency-msec=20", "--client-name=dawlings discord bridge",
		"--stream-name=dawlings discord bridge"], { stdio: ["ignore", "pipe", "pipe"] });
	parec.stderr.on("data", (d) => say("error", `parec: ${String(d).trim()}`));
	parec.on("exit", (code) => {
		if (!stopping) say("error", `the capture of ${SOURCE} stopped (${code})`);
	});
	return createAudioResource(parec.stdout, { inputType: StreamType.Raw });
}

const player = createAudioPlayer({ behaviors: { noSubscriber: NoSubscriberBehavior.Play } });
player.on("error", (e) => say("error", `player: ${e.message}`));
player.on(AudioPlayerStatus.Idle, () => {
	if (!stopping) {
		if (parec) parec.kill();
		player.play(capture());
	}
});
player.play(capture());

const client = new Client({ intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildVoiceStates] });
let here = null; // {guild, channel} the bot is in now
let stopping = false;

async function follow(channel) {
	const guildId = channel?.guild?.id;
	if (here && (!channel || here.channel !== channel.id)) {
		getVoiceConnection(here.guild)?.destroy();
		here = null;
	}
	if (!channel) {
		say("waiting", "waiting for you to join a voice channel");
		return;
	}
	if (here) return;
	say("joining", `joining ${channel.name}`, { channel: channel.name, guild: channel.guild.name });
	const connection = joinVoiceChannel({
		channelId: channel.id, guildId, adapterCreator: channel.guild.voiceAdapterCreator,
		selfDeaf: true, selfMute: false,
	});
	here = { guild: guildId, channel: channel.id };
	connection.on(VoiceConnectionStatus.Disconnected, async () => {
		try {
			// Moved between channels, or a blip: it comes back by itself.
			await Promise.race([
				entersState(connection, VoiceConnectionStatus.Signalling, 5000),
				entersState(connection, VoiceConnectionStatus.Connecting, 5000),
			]);
		} catch {
			connection.destroy();
			if (here?.channel === channel.id) here = null;
			if (!stopping) follow(ownerChannel());
		}
	});
	try {
		await entersState(connection, VoiceConnectionStatus.Ready, 20000);
		connection.subscribe(player);
		say("playing", `playing in ${channel.name}`, { channel: channel.name, guild: channel.guild.name });
	} catch (e) {
		say("error", `could not join ${channel.name}: ${e.message}`);
		connection.destroy();
		here = null;
	}
}

// Where the owner is now, in any server the bot is in.
function ownerChannel() {
	for (const guild of client.guilds.cache.values()) {
		const state = guild.voiceStates.cache.get(user);
		if (state?.channel) return state.channel;
	}
	return null;
}

client.once(Events.ClientReady, (c) => {
	say("waiting", `signed in as ${c.user.tag}; waiting for you to join a voice channel`);
	if (c.guilds.cache.size === 0) say("error", "the bot is in no server yet: invite it (see docs/discord.md)");
	follow(ownerChannel());
});

client.on(Events.VoiceStateUpdate, (before, after) => {
	if (after.id !== user && before.id !== user) return;
	follow(after.channel ?? null);
});

function stop() {
	if (stopping) return;
	stopping = true;
	if (here) getVoiceConnection(here.guild)?.destroy();
	player.stop(true);
	if (parec) parec.kill();
	say("stopped", "left voice");
	client.destroy().finally(() => process.exit(0));
}

// The game holds stdin open: closed, the game is gone or switched the feed off.
process.stdin.on("end", stop);
process.stdin.on("close", stop);
process.stdin.resume();
process.on("SIGTERM", stop);
process.on("SIGINT", stop);

say("starting", "signing in to Discord");
client.login(token).catch((e) => {
	say("error", `could not sign in: ${e.message}`);
	process.exit(3);
});
