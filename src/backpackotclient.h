// Copyright 2023 The Forgotten Server Authors. All rights reserved.
// Use of this source code is governed by the GPL-2.0 License that can be found in the LICENSE file.

#ifndef FS_BACKPACKOTCLIENT_H
#define FS_BACKPACKOTCLIENT_H

#include "xtea.h"

#include <chrono>
#include <cstdint>
#include <mutex>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>

// BackpackOT client gate (docs/client-launcher/PLAN.md phase 4; the wire format
// and a reference Lua port are in docs/client-launcher/GATE.md).
//
// The BackpackOT client puts the marker "BPOT" + u32 signature + u16 release in
// its login packets, inside the RSA block, with the other length-prefixed
// markers. The signature is mixed exactly like AstraClient's, with its own
// constants, so only a client that carries those constants produces it. It is
// a bar, not a wall: the constants live in the client.
//
// Config (config.lua): backpackClientGate = "off" | "warn" | "enforce",
// backpackMinClientRelease = <release>. "off" is the default and changes
// nothing; "warn" logs the logins it would refuse; "enforce" refuses them.
//
// This header has no server dependencies on purpose: the test program that
// produces the GATE.md test vectors compiles it on its own.
namespace BackpackOTClient {

inline constexpr std::string_view LOGIN_MARKER = "BPOT";

// Player-facing (A2 English, PLAN.md section 3.2). The client matches these
// strings to offer its "Check for updates" button, so change both together.
inline constexpr std::string_view OUTDATED_MESSAGE = "Your client is out of date. Please restart it to update.";
inline constexpr std::string_view REQUIRED_MESSAGE =
    "This server requires the BackpackOT client. Download it at backpackot.com/downloads.";

inline uint32_t rotateLeft(uint32_t value, uint8_t bits)
{
	return (value << bits) | (value >> (32 - bits));
}

inline uint32_t mixSignature(uint32_t hash, uint32_t value)
{
	hash ^= value + 0x9E3779B9 + (hash << 6) + (hash >> 2);
	return rotateLeft(hash, 7) ^ (value >> 3);
}

// operatingSystem and version are the two u16 at the head of the packet, as
// sent. The login server passes no challenge (0, 0); the game server passes
// the challenge it sent when the connection opened.
inline uint32_t generateSignature(uint16_t operatingSystem, uint16_t version, const xtea::key& key,
                                  uint32_t challengeTimestamp = 0, uint8_t challengeRandom = 0)
{
	uint32_t hash = 0xC19BC793;
	hash = mixSignature(hash, 0xA0722E49);
	hash = mixSignature(hash, 0xD17CE629);
	hash = mixSignature(hash, operatingSystem);
	hash = mixSignature(hash, version);
	for (const uint32_t value : key) {
		hash = mixSignature(hash, value);
	}
	hash = mixSignature(hash, challengeTimestamp);
	hash = mixSignature(hash, challengeRandom);
	return hash ^ 0x0FA53ED2;
}

enum class GateMode : uint8_t
{
	OFF = 0,
	WARN = 1,
	ENFORCE = 2,
};

// What one login packet said about the client.
struct Marker
{
	bool present = false; // a "BPOT" marker was read
	bool valid = false;   // and its signature matched
	uint16_t release = 0; // the release it claimed (only meaningful when valid)
};

enum class Verdict : uint8_t
{
	PASS,
	NO_MARKER,
	BAD_SIGNATURE,
	OUTDATED,
};

inline Verdict judge(const Marker& marker, int64_t minRelease)
{
	if (!marker.present) {
		return Verdict::NO_MARKER;
	}
	if (!marker.valid) {
		return Verdict::BAD_SIGNATURE;
	}
	if (marker.release < minRelease) {
		return Verdict::OUTDATED;
	}
	return Verdict::PASS;
}

inline std::string_view refusalMessage(Verdict verdict)
{
	return verdict == Verdict::OUTDATED ? OUTDATED_MESSAGE : REQUIRED_MESSAGE;
}

// One log line per login the gate refuses, or in "warn" would refuse, e.g.
// "[ClientGate] would refuse account foo from 1.2.3.4: release 1342 < 1343".
// context is appended as is (the game server passes " (game login)").
inline std::string describeRefusal(bool enforced, std::string_view accountName, std::string_view ip, Verdict verdict,
                                   uint16_t release, int64_t minRelease, std::string_view context = {})
{
	std::string line = enforced ? "[ClientGate] refused account " : "[ClientGate] would refuse account ";
	// The name comes off the wire: keep the log entry one printable line.
	for (const char c : accountName.substr(0, 64)) {
		line.push_back(c >= 0x20 && c < 0x7F ? c : '?');
	}
	line += " from ";
	line += ip;
	line += ": ";
	switch (verdict) {
		case Verdict::NO_MARKER:
			line += "no marker";
			break;
		case Verdict::BAD_SIGNATURE:
			line += "bad signature";
			break;
		case Verdict::OUTDATED:
			line += "release " + std::to_string(release) + " < " + std::to_string(minRelease);
			break;
		case Verdict::PASS:
			line += "pass";
			break;
	}
	line += context;
	return line;
}

// The account login (login server) and the game login are two connections.
// Until the game login carries its own marker (phase 4b), the game server
// judges it by the account login that came before it: the login server records
// {account, ip} -> release when it accepts a valid marker, and the game server
// looks that up. Entries live two minutes; expired ones are pruned on insert.
//
// The client keeps its character list after a logout or a kick and goes
// straight to the game server, so a game login can come long after the account
// login. With the hand-off alone, "enforce" refuses those (GATE.md, "4a only").
class LoginHandoff
{
public:
	static constexpr std::chrono::milliseconds TTL{2 * 60 * 1000};

	static LoginHandoff& getInstance()
	{
		static LoginHandoff instance;
		return instance;
	}

	void record(uint32_t accountId, uint32_t ip, uint16_t release)
	{
		const auto now = std::chrono::steady_clock::now();
		std::scoped_lock lock(mu);
		std::erase_if(entries, [now](const auto& entry) { return now - entry.second.recordedAt > TTL; });
		entries[makeKey(accountId, ip)] = Entry{release, now};
	}

	std::optional<uint16_t> find(uint32_t accountId, uint32_t ip)
	{
		const auto now = std::chrono::steady_clock::now();
		std::scoped_lock lock(mu);
		auto it = entries.find(makeKey(accountId, ip));
		if (it == entries.end() || now - it->second.recordedAt > TTL) {
			return std::nullopt;
		}
		return it->second.release;
	}

private:
	LoginHandoff() = default;

	static uint64_t makeKey(uint32_t accountId, uint32_t ip) { return (static_cast<uint64_t>(accountId) << 32) | ip; }

	struct Entry
	{
		uint16_t release = 0;
		std::chrono::steady_clock::time_point recordedAt;
	};

	std::mutex mu;
	std::unordered_map<uint64_t, Entry> entries;
};

} // namespace BackpackOTClient

#endif // FS_BACKPACKOTCLIENT_H
