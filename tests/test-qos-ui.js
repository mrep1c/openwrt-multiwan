'use strict';

// Run the shipped view with only LuCI's form registration mocked.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const uiDir = path.join(__dirname, '../luci-app-multiwan-qos/htdocs/luci-static/resources/multiwan-qos');
const options = {};
const fields = { enabled: '1', qdisc: 'hfsc', upload: '10000', download: '20000' };
let rateMode = 'manual';
const section = {
    option(type, name) {
        const option = {
            option: name, section: this, value() {}, dependencies: [],
            depends(key, value) { this.dependencies.push(typeof key === 'string' ? { [key]: value } : { ...key }); }
        };
        options[name] = option;
        return option;
    },
    formvalue(id, name) { return fields[name]; }
};
const context = vm.createContext({
    view: { extend: value => value },
    rpc: { declare: () => () => {} },
    ui: { createHandlerFn() {} },
    uci: { get: () => rateMode },
    widgets: {},
    form: { Map: function () { this.section = () => section; this.render = () => {}; } },
    _: value => value
});
vm.runInContext('String.prototype.format = function (...args) { let i = 0; return this.replace(/%[sd]/g, () => args[i++]); };', context);
const settings = vm.runInContext('(function () {\n' + fs.readFileSync(path.join(uiDir, 'settings.js'), 'utf8') + '\n})()', context);
settings.render();

function accepted(option, value) {
    return !options[option].validate || options[option].validate('wan', value) === true;
}

for (const [option, direction] of [['game_up', 'upload'], ['game_down', 'download']]) {
    for (const value of ['0', fields[direction], '999999', '-1', '1.5', 'abc'])
        assert.equal(accepted(option, value), false, `${option} accepted invalid reserve ${value}`);
    for (const value of ['', null, '1', String(Number(fields[direction]) - 1)])
        assert.equal(accepted(option, value), true, `${option} rejected reserve ${value}`);

    // A bandwidth edit must be checked before it has been saved to UCI.
    fields[direction] = '1500';
    assert.equal(accepted(option, '2000'), false, `${option} ignored edited bandwidth`);
    fields[direction] = '3000000';
    assert.equal(accepted(option, '2500000'), false, `${option} ignored backend maximum rate`);
    fields[direction] = '500';
    assert.equal(accepted(option, '999'), true, `${option} ignored backend minimum rate`);
    assert.equal(accepted(option, '1000'), false);
    fields[direction] = '10000';
}

fields.qdisc = 'hybrid';
assert.equal(accepted('game_down', '10000'), false);
for (const qdisc of ['cake', 'htb']) {
    fields.qdisc = qdisc;
    assert.equal(accepted('game_up', '999999'), true, `${qdisc} rejected an unused reserve`);
}
fields.qdisc = 'hfsc';
for (const mode of ['default', 'adaptive']) {
    rateMode = mode;
    assert.equal(accepted('game_up', '999999'), true, `${mode} rejected an unused reserve`);
}
rateMode = 'manual';
fields.enabled = '0';
assert.equal(accepted('game_up', '999999'), true, 'disabled interface rejected an unused reserve');

// Exercise the shipped warning callback without constructing the connection table.
context.limitWarning = { style: {}, textContent: '' };
const connections = fs.readFileSync(path.join(uiDir, 'connections.js'), 'utf8');
const warning = connections.match(/view\.updateLimitWarning = function \(status\) \{[\s\S]*?\n        \};/);
assert.ok(warning, 'connection limit warning callback missing');
vm.runInContext(warning[0], context);
context.view.updateLimitWarning({ max_connections: 0, effective_max_connections: 100, truncated: true });
assert.equal(context.limitWarning.style.display, 'block', 'automatic truncation warning hidden');
assert.match(context.limitWarning.textContent, /100 connections/);
assert.match(context.limitWarning.textContent, /larger flows/);
context.view.updateLimitWarning({ max_connections: 0, effective_max_connections: 2000, truncated: false });
assert.equal(context.limitWarning.style.display, 'none', 'complete automatic scan reported as truncated');
context.view.updateLimitWarning({ max_connections: 500 });
assert.equal(context.limitWarning.style.display, 'block', 'explicit limit warning lost');
assert.match(context.limitWarning.textContent, /500 connections/);
context.view.updateLimitWarning({});
assert.equal(context.limitWarning.style.display, 'none');

// Use the actual adaptive table builder with the existing table renderer stubbed.
context.E = (tag, attributes, children) => ({ tag, attributes, children });
const statistics = vm.runInContext('(function () {\n' + fs.readFileSync(path.join(uiDir, 'statistics.js'), 'utf8') + '\n})()', context);
statistics.createStatsTable = (title, headers, rows) => ({ title, headers, rows });
const adaptive = statistics.createAdaptiveTable([
    'device=wan0 direction=wan applied_rate=1000 requested_rate=1150 recommended_rate=1200 backlog_bytes=2048 freshness_target_ms=20 drop_delta=2 congestion_drop_delta=1 stats_last_ok_ms=1000 saturation=pressure state=degraded last_change_reason=demand-increase',
    'device=ifb-wan0 direction=lan scheduler_rate=1500 stats_last_ok_ms=0'
], 6500);
assert.equal(adaptive.rows.length, 2);
assert.equal(adaptive.rows[0][2], '1000 kbit/s');
assert.equal(adaptive.rows[0][3], '1150 kbit/s');
assert.equal(adaptive.rows[0][5], '2 KiB / 20 ms');
assert.equal(adaptive.rows[0][6], '2 / 1');
assert.equal(adaptive.rows[0][7].children, '5.5 s');
assert.equal(adaptive.rows[0][8], 'At ceiling; pressure continues');
assert.equal(adaptive.rows[1][1], 'Download');
assert.equal(adaptive.rows[1][2], '1500 kbit/s');
assert.equal(adaptive.rows[1][3], 'Unknown');
assert.equal(adaptive.rows[1][7].children, 'Unknown');
assert.equal(adaptive.rows[1][8], 'Unknown');
assert.equal(statistics.createAdaptiveTable(['device=wan0 direction=wan stats_last_ok_ms=7000 stats_age_ms=0'], 6500).rows[0][7].children, 'Unknown');
assert.equal(statistics.createAdaptiveTable(['device=wan0 direction=wan stats_last_ok_ms=1000'], 0).rows[0][7].children, 'Unknown');

// Render the actual HFSC view to check that both experimental features stay opt-in.
context.uci.load = async () => {};
context.uci.sections = (config, type, callback) => callback({ enabled: '1', qdisc: 'hfsc' });
context.uci.get = (config, section, option) => option === 'gameqdisc' ? 'bfifo' : option === 'realtime_rate_mode' ? 'adaptive' : undefined;
const hfsc = vm.runInContext('(function () {\n' + fs.readFileSync(path.join(uiDir, 'hfsc.js'), 'utf8') + '\n})()', context);
hfsc.render().then(() => {
    for (const option of ['adaptive_queue_budget', 'adaptive_freshness']) {
        assert.equal(options[option].default, '0', `${option} is enabled by default`);
        assert.equal(options[option].rmempty, false, `${option} does not persist its off value`);
    }
    const visible = values => options.adaptive_freshness.dependencies.some(dependency =>
        Object.entries(dependency).every(([key, value]) => values[key] === value));
    for (const gameqdisc of ['bfifo', 'pfifo'])
        assert.equal(visible({ realtime_rate_mode: 'adaptive', adaptive_queue_budget: '1', gameqdisc }), true);
    for (const gameqdisc of ['netem', 'qfq', 'red', 'fq_codel', 'drr'])
        assert.equal(visible({ realtime_rate_mode: 'adaptive', adaptive_queue_budget: '1', gameqdisc }), false);
    assert.equal(visible({ realtime_rate_mode: 'adaptive', adaptive_queue_budget: '0', gameqdisc: 'bfifo' }), false);
    assert.equal(visible({ realtime_rate_mode: 'manual', adaptive_queue_budget: '1', gameqdisc: 'bfifo' }), false);
    const config = fs.readFileSync(path.join(__dirname, '../multiwan-qos/etc/config/multiwan-qos'), 'utf8');
    assert.match(config, /option adaptive_freshness '0'/);
    console.log('QoS UI regression tests passed.');
}).catch(error => {
    console.error(error);
    process.exitCode = 1;
});
