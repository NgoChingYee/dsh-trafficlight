// host/subscriptions.ts — which sessions are shown on the traffic light.
//
// The subscription list is authoritative: the overlay renders ONLY the
// sessions the user explicitly subscribed to (via the dsh web session menu),
// never the whole session set. The list is persisted to a small JSON file so
// it survives dsh web restarts.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
/** Resolve the persistence file. Override with DSH_TL_SUBS_FILE; otherwise the
 * dsh storage convention `~/.dsh/storages/<name>.json` (see dsh-home-paths). */
export function defaultSubsFile() {
    if (process.env.DSH_TL_SUBS_FILE)
        return process.env.DSH_TL_SUBS_FILE;
    const home = process.env.DSH_HOME || path.join(os.homedir(), '.dsh');
    return path.join(home, 'storages', 'dsh-trafficlight.json');
}
export class SubscriptionStore {
    ids = new Set();
    titles = new Map();
    file;
    home;
    ctx;
    saveTimer;
    constructor(ctx, file) {
        this.ctx = ctx;
        this.file = file;
        this.home = process.env.DSH_HOME || path.join(os.homedir(), '.dsh');
        this.load();
    }
    list() {
        return [...this.ids];
    }
    has(sessionId) {
        return this.ids.has(sessionId);
    }
    /** Authoritative conversation title, cached across DSH restarts. */
    title(sessionId) {
        // DSH's persisted title projection is the source of truth. Re-read it on
        // every access: an earlier user-message fallback may have been cached
        // before the real session/title event was generated.
        const projected = this.readProjectionTitle(sessionId);
        if (projected !== undefined) {
            if (this.titles.get(sessionId) !== projected) {
                this.titles.set(sessionId, projected);
                this.scheduleSave();
            }
            return projected;
        }
        return this.titles.get(sessionId);
    }
    /** Remember the title DSH's sessionTitle service or session log resolved. */
    setTitle(sessionId, title) {
        const clean = String(title ?? '').trim();
        if (sessionId === '' || clean === '' || this.titles.get(sessionId) === clean) return false;
        this.titles.set(sessionId, clean);
        this.scheduleSave();
        return true;
    }
    /** Add a subscription. Returns true when the set actually changed. */
    add(sessionId) {
        if (this.ids.has(sessionId))
            return false;
        this.ids.add(sessionId);
        this.scheduleSave();
        return true;
    }
    /** Remove a subscription. Returns true when the set actually changed. */
    remove(sessionId) {
        if (!this.ids.delete(sessionId))
            return false;
        this.scheduleSave();
        return true;
    }
    load() {
        try {
            const raw = fs.readFileSync(this.file, 'utf8');
            const parsed = JSON.parse(raw);
            if (Array.isArray(parsed)) {
                for (const id of parsed) {
                    if (typeof id === 'string' && id !== '')
                        this.ids.add(id);
                }
                return;
            }
            if (parsed !== null && typeof parsed === 'object') {
                const record = parsed;
                if (Array.isArray(record.subscriptions)) {
                    for (const id of record.subscriptions) {
                        if (typeof id === 'string' && id !== '')
                            this.ids.add(id);
                    }
                }
                if (record.titles !== null && typeof record.titles === 'object') {
                    for (const [id, title] of Object.entries(record.titles)) {
                        if (typeof title === 'string' && title.trim() !== '')
                            this.titles.set(id, title.trim());
                    }
                }
            }
        }
        catch {
            // First run / corrupt file → start empty.
        }
    }
    /** Read DSH's persisted session title projection for a non-live session. */
    readProjectionTitle(sessionId) {
        if (sessionId === '' || sessionId.includes('/') || sessionId.includes('\\'))
            return undefined;
        const file = path.join(this.home, 'storages', 'session_projcache', 'sessions', sessionId + '.json');
        try {
            const raw = fs.readFileSync(file, 'utf8');
            const parsed = JSON.parse(raw);
            const value = parsed.record?.rows?.title?.val;
            if (typeof value === 'string' && value.trim() !== '')
                return value.trim();
        }
        catch {
            // No projection cache yet — fall back to the ID placeholder.
        }
        return undefined;
    }
    /** Debounced atomic write so bursts of toggle clicks don't thrash the disk. */
    scheduleSave() {
        if (this.saveTimer !== undefined)
            clearTimeout(this.saveTimer);
        this.saveTimer = setTimeout(() => this.save(), 300);
    }
    save() {
        this.saveTimer = undefined;
        try {
            fs.mkdirSync(path.dirname(this.file), { recursive: true });
            const tmp = this.file + '.tmp';
            const payload = {
                subscriptions: this.list(),
                titles: Object.fromEntries(this.titles),
            };
            fs.writeFileSync(tmp, JSON.stringify(payload, null, 2), 'utf8');
            fs.renameSync(tmp, this.file);
        }
        catch (error) {
            this.warn(`subscriptions persist failed: ${String(error)}`);
        }
    }
    warn(message) {
        try {
            this.ctx.logger?.warn?.(`[dsh-trafficlight] ${message}`);
        }
        catch {
            /* ignore */
        }
    }
}
