pragma Singleton

import QtQuick
import Aikatsu

// Promise-ish wrapper over Backend.call/get: call("search", {query}, ok, err).
QtObject {
    id: root

    property var pending: ({})

    signal pushed(string kind, var data)

    function call(method: string, args: var, onOk: var, onErr: var): int {
        const id = Backend.call(method, JSON.stringify(args ?? {}));
        pending[id] = {
            ok: onOk,
            err: onErr
        };
        return id;
    }

    // Drops a pending reply (e.g. the page that asked is gone).
    function forget(id: int): void {
        delete pending[id];
    }

    function get(method: string, args: var): var {
        return JSON.parse(Backend.get(method, JSON.stringify(args ?? {})));
    }

    // One plain sentence for a backend/mpv error; show the raw text as details.
    function describe(err: string): string {
        const offline = /^(.+?) is offline\b/.exec(String(err ?? ""));
        if (offline)
            return `${offline[1]} is offline. Open Aikatsu there and try again.`;
        const unreachable = /^(.+?) can't be reached\b/.exec(String(err ?? ""));
        if (unreachable)
            return `Can't reach ${unreachable[1]}. Check its firewall and that you're on the same network.`;
        const e = String(err ?? "").toLowerCase();
        if (/video chain/.test(e))
            return "This video's format can't play on this device.";
        if (/timed? ?out|timeout/.test(e))
            return "The site took too long to answer.";
        if (/dns|lookup address|connect|network|unreachable|connection|offline/.test(e))
            return "Couldn't reach the site. Check your internet connection.";
        if (/403|forbidden|429|too many requests|cloudflare|blocked/.test(e))
            return "The site refused the request. Try again in a minute.";
        if (/no playable|no .*(server|stream|media|player)|404|not found|unrecognized|layout changed/.test(e))
            return "No working stream was found for this episode.";
        return "Something went wrong.";
    }

    // The plugin's name for a source key; just the key's own part ("kyoko/x" → "x") when not installed.
    function sourceName(key: string): string {
        if (key === "local")
            return "Local files";
        return get("sources").find(s => s.key === key)?.name ?? String(key ?? "").split("/").pop();
    }

    function setting(key: string): string {
        return get("settings")[key] ?? "";
    }

    function setSetting(key: string, value: var): void {
        get("setSetting", {
            key: key,
            value: String(value)
        });
        settingChanged(key, String(value));
    }

    signal settingChanged(string key, string value)

    // Watchlist statuses, in menu order (core db::WatchEntry).
    readonly property var watchStatuses: [
        {
            value: "watching",
            text: "Watching",
            icon: "play_circle"
        },
        {
            value: "planning",
            text: "Plan to watch",
            icon: "schedule"
        },
        {
            value: "completed",
            text: "Completed",
            icon: "check_circle"
        },
        {
            value: "paused",
            text: "On hold",
            icon: "pause_circle"
        },
        {
            value: "dropped",
            text: "Dropped",
            icon: "cancel"
        }
    ]

    property Connections conn: Connections {
        target: Backend

        function onReply(id: int, ok: bool, json: string): void {
            const p = root.pending[id];
            if (!p)
                return;
            delete root.pending[id];
            const data = JSON.parse(json);
            if (ok && p.ok)
                p.ok(data);
            else if (!ok && p.err)
                p.err(data);
        }

        function onPushed(kind: string, json: string): void {
            root.pushed(kind, JSON.parse(json));
        }
    }
}
